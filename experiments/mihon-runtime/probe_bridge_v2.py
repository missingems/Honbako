#!/usr/bin/env python3
"""Bounded binary-image host proof using the unchanged published Komga JAR.

No server backend or public provider is contacted. The separate original source
fixture proves real HttpSource resolver/header/client APIs, not Komga behavior.
Frozen baseline JARs and their device proof are never overwritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import select
import shutil
import subprocess
import threading
import urllib.parse
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--java-home", type=Path, default=Path("/opt/homebrew/opt/openjdk@27"))
    args = parser.parse_args()
    root = args.runtime_root.resolve()
    experiment = Path(__file__).resolve().parent
    repo = experiment.parents[1]
    assert root != repo and repo not in root.parents
    old = root / "honbako-extension-bridge.jar"
    dependencies = root / "komga-proof-dependencies.jar"
    compile_extra = root / "bridge-compile-dependencies.jar"
    upgraded = root / "honbako-extension-bridge-v2.jar"
    package = root / "tachiyomi-all.komga-v1.6.74.jar"
    for path in (upgraded, dependencies, compile_extra, package):
        if not path.is_file():
            raise ValueError("Run prepare_host_runtime.py first; missing " + path.name)
    before = {path: sha(path.read_bytes()) for path in (upgraded, dependencies, compile_extra, package)}
    if old.is_file():
        before[old] = sha(old.read_bytes())
    assert before[package] == "9f1b4a05113f33d4de7f5177dded79419ef33e5d91c3ce38a3e55b609c522013"
    provenance = root / "bridge-v2-build.json"
    if provenance.is_file():
        built = json.loads(provenance.read_text())
        assert built["sha256"] == before[upgraded]
        assert built["dependency_jar_sha256"] == before[dependencies]
        assert built["compile_only_dependencies_sha256"] == before[compile_extra]
    java, javac = (str(args.java_home / "bin" / name) for name in ("java", "javac"))
    driver, fixture_classes = (root / name for name in ("bridge-v2-host-classes", "bridge-v2-fixture-classes"))
    for directory in (driver, fixture_classes):
        if directory.exists():
            shutil.rmtree(directory)
        directory.mkdir(exist_ok=True)
    compiler_classpath = ":".join(map(str, (upgraded, dependencies, compile_extra)))
    base = experiment / "java/com/missingems/honbako/runtime"
    subprocess.run([javac, "--release", "17", "-cp", str(upgraded) + ":" + compiler_classpath, "-d", str(driver),
                    str(experiment / "host_tests/BridgeV2Host.java")], check=True)
    subprocess.run([javac, "--release", "17", "-cp", compiler_classpath, "-d", str(fixture_classes),
                    str(experiment / "host_tests/BridgeFixtureSource.java")], check=True)
    fixture_jar = root / "honbako-original-source-fixture.jar"
    with zipfile.ZipFile(fixture_jar, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for item in fixture_classes.rglob("*.class"):
            archive.writestr(item.relative_to(fixture_classes).as_posix(), item.read_bytes())
        archive.writestr("AndroidManifest.xml", """<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.missingems.honbako.fixture" android:versionName="1.6.1"><application><meta-data android:name="tachiyomi.extension.class" android:value="com.missingems.honbako.fixture.BridgeFixtureSource"/><meta-data android:name="tachiyomix.extensionLib" android:value="1.6"/></application></manifest>""")
    original = (base / "KomgaDeviceProbe.java").read_text()
    fixture = json.loads(re.search(r'private static final String DATA = """\s*(.*?)\s*""";', original, re.S).group(1))
    art = repo / "Aidoku/App/Resources/Assets.xcassets"
    pages = [(art / ("HonbakoTutorialPage%dArt.imageset" % n) / "art.png").read_bytes() for n in (1, 2, 3)]
    cover = (art / "HonbakoTutorialCoverArt.imageset/art.png").read_bytes()
    requests, operations = [], []
    maximum = 32 * 1024 * 1024

    def collection(items):
        return {"content": items, "empty": not items, "first": True, "last": True, "number": 0,
                "numberOfElements": len(items), "size": 20, "totalElements": len(items), "totalPages": 1}

    class Fixture(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass

        def do_GET(self):
            uri = urllib.parse.urlparse(self.path)
            requests.append({"path": self.path, "sourceHeader": self.headers.get("X-Honbako-Source"),
                             "clientHook": self.headers.get("X-Honbako-Client"), "pageHook": self.headers.get("X-Honbako-Page")})
            if uri.path in ("/large-known", "/large-unknown"):
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                if uri.path == "/large-known":
                    self.send_header("Content-Length", str(maximum + 1))
                self.end_headers()
                if uri.path == "/large-unknown":
                    try:
                        block = b"0" * (64 * 1024)
                        for _ in range(maximum // len(block)):
                            self.wfile.write(block)
                        self.wfile.write(b"1")
                    except (BrokenPipeError, ConnectionResetError):
                        pass
                return
            content, media = None, "application/json"
            if uri.path == "/api/v1/series":
                query = urllib.parse.parse_qs(uri.query).get("search", [""])[0]
                content = collection([fixture["series"]] if query.lower() in fixture["series"]["name"].lower() else [])
            elif uri.path == "/api/v1/series/honbako-original":
                content = fixture["series"]
            elif uri.path == "/api/v1/series/honbako-original/books":
                content = collection([fixture["chapter"]])
            elif uri.path == "/api/v1/books/original-1/pages":
                content = [{"number": n, "fileName": "page-%d.png" % n, "mediaType": "image/png"} for n in (1, 2, 3)]
            elif uri.path.startswith("/api/v1/books/original-1/pages/"):
                content, media = pages[int(uri.path.rsplit("/", 1)[1]) - 1], "image/png"
            elif uri.path == "/api/v1/series/honbako-original/thumbnail" or uri.path == "/fixture-cover":
                content, media = cover, "image/png"
            elif uri.path == "/resolver":
                content, media = (base_url + "/fixture-image").encode(), "text/plain"
            elif uri.path == "/fixture-image":
                content, media = pages[0], "image/png"
            if content is None:
                self.send_error(404)
                return
            data = content if isinstance(content, bytes) else json.dumps(content).encode()
            self.send_response(200)
            self.send_header("Content-Type", media)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    base_url = "http://127.0.0.1:%d" % server.server_port
    common = {"extensionPath": str(package), "preferences": {"Address": base_url}, "packageSHA256": before[package],
              "packageName": "eu.kanade.tachiyomi.extension.all.komga", "versionName": "1.6.74", "extensionLibrary": "1.6"}
    with (root / "bridge-v2-host.stderr.log").open("w") as log:
        process = subprocess.Popen([java, "--limit-modules=java.base,java.xml,java.logging", "-Xmx192m", "-cp",
            ":".join(map(str, (driver, upgraded, dependencies))), "com.missingems.honbako.runtime.BridgeV2Host"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True, bufsize=1)
        try:
            def send(request):
                process.stdin.write(json.dumps(request) + "\n")
                process.stdin.flush()
                ready, _, _ = select.select([process.stdout], [], [], 45)
                assert ready, "Bridge operation timed out"
                line = process.stdout.readline()
                assert line, "Bridge exited: " + (root / "bridge-v2-host.stderr.log").read_text()[-4000:]
                return json.loads(line)

            def call(operation, ok=True, binary=False, session=None, **fields):
                request = {**(session or common), "operation": operation, **fields}
                response = send({"binary": request} if binary else request)
                operations.append({"operation": operation, "binary": binary, "response": response})
                assert response["ok"] == ok, response
                return response["result"] if ok else response

            own = {"extensionPath": str(fixture_jar), "preferences": {}, "sourceId": "9007199254740993"}
            wrong = call("discover", ok=False, session=own, packageSHA256="0" * 64)
            assert "Package identity mismatch" in wrong["error"]
            assert send({"property": "honbako.fixture.initialized"})["value"] is None
            wrong = call("discover", ok=False, session=own, packageName="incorrect.package")
            assert "Package identity mismatch" in wrong["error"]
            assert send({"property": "honbako.fixture.initialized"})["value"] is None
            discovered = call("discover")
            assert discovered["extensionLibrary"] == "1.6" and discovered["packageSHA256"] == before[package]
            ids = [source["id"] for source in discovered["sources"]]
            assert ids == ["4508733312114627536", "8074481155021144106", "5132811728275817394"]
            source = ids[0]
            manga = call("search", sourceId=source, query="Your First")["entries"][0]
            assert call("details", sourceId=source, manga=manga)["manga"]["status"] == 2
            chapters = call("chapters", sourceId=source, manga=manga)["chapters"]
            listed = call("pages", sourceId=source, chapter=chapters[0])["pages"]
            images = [call("image", binary=True, sourceId=source, page=page) for page in listed]
            assert [image["sha256"] for image in images] == [sha(page) for page in pages]
            assert all(image["sha256"] == image["independentlyComputedSHA256"] for image in images)
            cover_result = call("cover", binary=True, sourceId=source, url=manga["cover"])
            assert cover_result["sha256"] == sha(cover)
            assert call("search", sourceId=source, query="No Such Original Book")["entries"] == []
            lazy = call("image", session=own, binary=True, page={"index": 0, "url": base_url + "/resolver", "imageUrl": None})
            assert lazy["sha256"] == sha(pages[0])
            own_cover = call("cover", session=own, binary=True, url=base_url + "/fixture-cover")
            assert own_cover["sha256"] == sha(cover)
            for request in requests:
                if request["path"].startswith(("/resolver", "/fixture-")):
                    assert request["sourceHeader"] == "original-fixture" and request["clientHook"] == "extension-client-hook"
                    assert (request["pageHook"] == "extension-image-request-hook") == (request["path"] == "/fixture-image")
            for path in ("/large-known", "/large-unknown"):
                response = call("image", binary=True, ok=False, sourceId=source, page={"index": 0, "url": "", "imageUrl": base_url + path})
                assert "33554432-byte limit" in response["error"]
            for raw in ['{"operation":"discover","operation":"search"}', '{} {}', '{"x":' + '[' * 20 + '0' + ']' * 20 + '}']:
                assert send({"raw": raw})["ok"] is False
            assert not call("search", ok=False, sourceId=source, query="q" * 16_385)["ok"]
            assert not call("pages", ok=False, sourceId="1", chapter={"url": "/unused"})["ok"]
            # Actual factory IDs select independent named preference scopes.
            for sid, address in [(ids[0], base_url + "/a"), (ids[1], base_url + "/b")]:
                session = {**common, "preferences": {"Address": address}, "sourceId": sid}
                call("discover", session=session)
                assert send({"preference": {"namespace": "one", "key": "Address"}})["value"] == address
                if sid == ids[0]:
                    send({"preference": {"namespace": "one", "key": "Remember", "put": "source-a"}})
                    assert send({"preference": {"namespace": "two", "key": "Remember"}})["value"] == "missing"
                else:
                    assert send({"preference": {"namespace": "one", "key": "Remember"}})["value"] == "missing"
            call("discover", session={**common, "preferences": {"Address": base_url + "/a"}, "sourceId": ids[0]})
            assert send({"preference": {"namespace": "one", "key": "Remember"}})["value"] == "source-a"
            report = {"status": "passed", "execution": "host JVM, not iOS", "bridge_v2_sha256": sha(upgraded.read_bytes()),
                      "runtime_dependency_jar_sha256": before[dependencies], "compile_only_dependencies_sha256": before[compile_extra],
                      "published_komga_unchanged": True, "published_komga_sha256": before[package],
                      "binary_page_sha256": [image["sha256"] for image in images], "binary_cover_sha256": cover_result["sha256"],
                      "original_fixture_lazy_resolver_and_hooks": True, "source_and_namespace_preferences_isolated": True,
                      "image_limit_bytes": maximum, "known_and_unknown_length_oversize_rejected": True,
                      "identity_checked_before_fixture_class_initialization": True, "operations": operations,
                      "http_requests": requests, "external_network_enabled": False, "frozen_artifacts_unchanged": True}
            (root / "bridge-v2-host-proof.json").write_text(json.dumps(report, indent=2) + "\n")
            print("PASS: unchanged Komga binary pages/cover, actual lazy resolver and image/client hooks, early image bounds, strict inputs, scoped preferences")
        finally:
            process.stdin.close()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=10)
            server.shutdown()
            server.server_close()
            worker.join(timeout=5)
            assert all(sha(path.read_bytes()) == digest for path, digest in before.items())


if __name__ == "__main__":
    main()
