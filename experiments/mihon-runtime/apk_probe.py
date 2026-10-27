#!/usr/bin/env python3
"""Host proof: published APK -> real DEX translation -> unchanged extension bridge.

The original APK file hash is pinned. APK cryptographic signature verification
is deliberately NOT claimed. The translated JAR is unsigned test output.
"""
import argparse
import atexit
import hashlib
import json
from pathlib import Path
import re
import select
import subprocess
import threading
import urllib.parse
import urllib.request
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APK_URL = "https://github.com/keiyoushi/extensions/releases/download/ff521c1/tachiyomi-all.komga-v1.6.74.apk"
APK_SHA = "0fd95b938742d7f203281350c7f901098425b6fe5eafab873411e2430bd693b9"
REF_URL = "https://github.com/Suwayomi/Suwayomi-Server/releases/download/v2.4.2366/Suwayomi-Server-v2.4.2366.jar"
REF_SHA = "af9feb20af9d7ebe9e30769e6c6ebc7fc7ab1c447388d42e0280b1da5fe07bfd"
BRIDGE_SHA = "a8df6ed084b0499f97ae869d071b89b7dac16357f6fa917b6732a78bbdd9a931"
DEPS_SHA = "2de9571730c4742e531b27019ea86a62cf74a36ebe44f7e72a60ca30777d7b0b"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fetch(path, url, expected):
    if not path.exists():
        with urllib.request.urlopen(url, timeout=90) as source, path.open("wb") as target:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                target.write(chunk)
    assert digest(path.read_bytes()) == expected, "Artifact hash mismatch: " + path.name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--java-home", type=Path, default=Path("/opt/homebrew/opt/openjdk@27"))
    parser.add_argument("--keep-reference", action="store_true", help="Retain the pinned reference temporarily for conversion diagnostics")
    args = parser.parse_args()
    runtime = args.runtime_root.resolve()
    experiment = Path(__file__).resolve().parent
    repo = experiment.parents[1]
    assert repo not in runtime.parents and runtime != repo, "Downloaded artifacts must remain outside the checkout"
    runtime.mkdir(parents=True, exist_ok=True)
    apk = runtime / "tachiyomi-all.komga-v1.6.74.apk"
    reference = runtime / "Suwayomi-Server-v2.4.2366.jar"
    if not args.keep_reference:
        atexit.register(lambda: reference.unlink(missing_ok=True))
    converted = runtime / "komga-apk-converted-1.6.74.jar"
    bridge = runtime / "honbako-extension-bridge.jar"
    dependencies = runtime / "komga-proof-dependencies.jar"
    before = {bridge: digest(bridge.read_bytes()), dependencies: digest(dependencies.read_bytes())}
    assert before[bridge] == BRIDGE_SHA and before[dependencies] == DEPS_SHA, "Frozen proof dependencies changed"
    fetch(apk, APK_URL, APK_SHA)
    fetch(reference, REF_URL, REF_SHA)
    converter_classes = runtime / "apk-probe-classes"
    converter_classes.mkdir(exist_ok=True)
    java = str(args.java_home / "bin/java")
    javac = str(args.java_home / "bin/javac")
    subprocess.run([javac, "--release", "17", "-classpath", str(reference), "-d", str(converter_classes),
        str(experiment / "java/com/missingems/honbako/runtime/ApkConversionProbe.java")], check=True)
    if converted.exists():
        converted.unlink()  # Only this script's named throwaway conversion output.
    with (runtime / "apk-conversion.log").open("w") as log:
        subprocess.run([java, "-cp", str(converter_classes) + ":" + str(reference),
            "com.missingems.honbako.runtime.ApkConversionProbe", str(apk), str(converted)],
            check=True, stdout=log, stderr=subprocess.STDOUT, timeout=60)
    conversion_log = (runtime / "apk-conversion.log").read_text()
    normalized = re.search(r"restored R8 constructor calls: (\d+)", conversion_log)
    assert normalized and "translation errors: zero" in conversion_log, "Conversion did not report clean completion"
    converted_sha = digest(converted.read_bytes())
    # DEX-to-JVM verification can resolve Android preference hierarchies that
    # were lazy in the separately published JAR. Keep an independent overlay;
    # never modify the frozen direct-JAR proof dependencies.
    extra = runtime / "apk-proof-extra-dependencies.jar"
    with zipfile.ZipFile(reference) as source, zipfile.ZipFile(extra, "w", compression=zipfile.ZIP_DEFLATED) as target:
        seen = set()
        notices = 0
        for item in source.infolist():
            name = item.filename
            if item.is_dir():
                continue
            keep = name.endswith(".class") and name.startswith(("android/", "androidx/preference/",
                "eu/kanade/tachiyomi/source/", "eu/kanade/tachiyomi/network/"))
            keep |= name.startswith("META-INF/") and ("LICENSE" in name.upper() or "NOTICE" in name.upper())
            if keep:
                data = source.read(item)
                if name in seen:
                    # The shaded reference contains different original notices
                    # under repeated names. Preserve each without ZIP ambiguity.
                    notices += 1
                    name = "META-INF/reference-notices/%04d-%s" % (notices, Path(name).name)
                seen.add(name)
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                target.writestr(info, data)
    # Reuse only our checked-in original fixture DATA literal, without modifying
    # the frozen device probe or relaxing any of its verification checks.
    fixture_source = (experiment / "java/com/missingems/honbako/runtime/KomgaDeviceProbe.java").read_text()
    found = re.search(r'private static final String DATA = """\s*(.*?)\s*""";', fixture_source, re.S)
    assert found, "Original fixture data is unavailable"
    fixture = json.loads(found.group(1))
    series, chapter = fixture["series"], fixture["chapter"]
    art = repo / "Aidoku/App/Resources/Assets.xcassets"
    pages = [(art / ("HonbakoTutorialPage%dArt.imageset" % n) / "art.png").read_bytes() for n in (1, 2, 3)]
    requests, operations = [], []

    def collection(items):
        return {"content": items, "empty": not items, "first": True, "last": True, "number": 0,
                "numberOfElements": len(items), "size": 20, "totalElements": len(items), "totalPages": 1}

    class Fixture(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass

        def do_GET(self):
            uri = urllib.parse.urlparse(self.path)
            requests.append(self.path)
            content, media_type = None, "application/json"
            if uri.path == "/api/v1/series":
                query = urllib.parse.parse_qs(uri.query).get("search", [""])[0]
                content = collection([series] if query.lower() in series["name"].lower() else [])
            elif uri.path == "/api/v1/series/honbako-original":
                content = series
            elif uri.path == "/api/v1/series/honbako-original/books":
                content = collection([chapter])
            elif uri.path == "/api/v1/books/original-1/pages":
                content = [{"number": n, "fileName": "page-%d.png" % n, "mediaType": "image/png"} for n in (1, 2, 3)]
            elif uri.path.startswith("/api/v1/books/original-1/pages/"):
                index = int(uri.path.rsplit("/", 1)[1]) - 1
                if 0 <= index < len(pages):
                    content, media_type = pages[index], "image/png"
            if content is None:
                self.send_error(404)
                return
            data = content if isinstance(content, bytes) else json.dumps(content).encode()
            self.send_response(200)
            self.send_header("Content-Type", media_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    base = "http://127.0.0.1:%d" % server.server_port
    with (runtime / "apk-extension.stderr.log").open("w") as log:
        process = subprocess.Popen([java, "--limit-modules=java.base,java.xml,java.logging", "-cp", str(bridge) + ":" + str(dependencies) + ":" + str(extra),
            "com.missingems.honbako.runtime.ExtensionBridge"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=log, text=True, bufsize=1)
        try:
            def call(operation, **fields):
                request = {"operation": operation, "extensionPath": str(converted), "preferences": {"Address": base}, **fields}
                process.stdin.write(json.dumps(request) + "\n")
                process.stdin.flush()
                ready, _, _ = select.select([process.stdout], [], [], 40)
                assert ready, "Extension operation timed out: " + operation
                response = json.loads(process.stdout.readline())
                operations.append({"operation": operation, "response": response})
                assert response["ok"], response
                return response["result"]

            discovered = call("discover")
            assert discovered["package"] == "eu.kanade.tachiyomi.extension.all.komga"
            assert discovered["entryClass"] == "keiyoushi.source.Generated"
            ids = [item["id"] for item in discovered["sources"]]
            assert ids == ["4508733312114627536", "8074481155021144106", "5132811728275817394"]
            assert discovered["version"] == "1.6.74"
            source_id = ids[0]
            results = call("search", sourceId=source_id, query="Your First")
            assert len(results["entries"]) == 1 and not results["hasNextPage"]
            manga = results["entries"][0]
            assert manga["title"] == "Your First Chapter" and manga["author"] == "Honbako"
            details = call("details", sourceId=source_id, manga=manga)["manga"]
            assert details["status"] == 2
            chapters = call("chapters", sourceId=source_id, manga=manga)["chapters"]
            assert len(chapters) == 1 and chapters[0]["number"] == 1 and chapters[0]["uploadedAt"] > 0
            resolved = call("pages", sourceId=source_id, chapter=chapters[0])["pages"]
            assert [page["index"] for page in resolved] == [1, 2, 3]
            images = [call("image", sourceId=source_id, page=page) for page in resolved]
            hashes = [image["sha256"] for image in images]
            assert hashes == [digest(page) for page in pages] and len(set(hashes)) == 3
            assert call("search", sourceId=source_id, query="No Such Original Book")["entries"] == []
            report = {"status": "passed", "execution": "host JVM, not iOS", "apk_url": APK_URL,
                "apk_sha256": APK_SHA, "apk_file_hash_verified": True, "apk_cryptographic_signature_verified": False,
                "converted_jar_sha256": converted_sha, "converted_jar_is_signed": False,
                "conversion": "actual APK DEX via Dex2jar and Suwayomi BytecodeEditor; no translation errors accepted",
                "constructor_normalization": {"restored_call_sites": int(normalized.group(1)),
                    "scope": "R8 new-instance/direct-Object constructor calls and erased empty local superclass chains",
                    "safety": "Preserves allocated concrete types; synthesizes only empty constructor delegation; never invokes an existing constructor or replaces source methods/results"},
                "conversion_reference": {"url": REF_URL, "sha256": REF_SHA},
                "extra_dependency_jar": {"sha256": digest(extra.read_bytes()), "bytes": extra.stat().st_size,
                    "scope": "Android/preference reference classes required by this translated APK proof"},
                "frozen_bridge_unchanged": True, "frozen_dependency_jar_unchanged": True,
                "jdk_modules": ["java.base", "java.xml", "java.logging"],
                "scope": "One pinned real extension against original controlled fixture; not a general Android runtime, production installer, iOS execution, or cryptographic APK trust proof",
                "source_ids": ids, "operations": operations,
                "http_requests": requests, "page_sha256": hashes, "suwayomi_server_started": False}
            (runtime / "apk-host-proof.json").write_text(json.dumps(report, indent=2) + "\n")
            print("PASS: actual APK DEX conversion, factory discovery, search/details/chapters/pages, and three distinct extension-loaded original images")
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
            assert all(digest(path.read_bytes()) == expected for path, expected in before.items()), "Frozen proof JAR changed"
            if not args.keep_reference:
                reference.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
