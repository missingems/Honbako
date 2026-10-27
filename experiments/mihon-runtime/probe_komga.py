#!/usr/bin/env python3
"""Exercise an unmodified published Komga extension against original local content.

This is a host-JVM compatibility probe, not an iOS runtime claim. It never
starts Suwayomi Server or contacts a public manga provider.
"""
import argparse
import hashlib
import json
from pathlib import Path
import select
import subprocess
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--java", default="/opt/homebrew/opt/openjdk@27/bin/java")
    parser.add_argument("--classpath", help="Override the reference dependency JAR")
    parser.add_argument("--bridge-classpath", type=Path, help="Explicit bridge classes or JAR; defaults to the historical bridge-classes directory")
    parser.add_argument("--class-log", type=Path, help="Record JVM class loading for a reproducible reduced test classpath")
    parser.add_argument("--jvm-arg", action="append", default=[], help="Additional host JVM option (use --jvm-arg=VALUE)")
    args = parser.parse_args()
    runtime = args.runtime_root.resolve()
    repo = Path(__file__).resolve().parents[2]
    package = runtime / "tachiyomi-all.komga-v1.6.74.jar"
    expected = "9f1b4a05113f33d4de7f5177dded79419ef33e5d91c3ce38a3e55b609c522013"
    assert digest(package.read_bytes()) == expected, "Published extension package hash changed"
    art_root = repo / "Aidoku/App/Resources/Assets.xcassets"
    pages = [(art_root / ("HonbakoTutorialPage%dArt.imageset" % n) / "art.png").read_bytes() for n in (1, 2, 3)]
    cover = (art_root / "HonbakoTutorialCoverArt.imageset/art.png").read_bytes()
    timestamp = "2026-10-27T00:00:00Z"
    series = {
        "id": "honbako-original", "libraryId": "owned-content", "name": "Your First Chapter",
        "created": timestamp, "lastModified": timestamp, "fileLastModified": timestamp, "booksCount": 1,
        "metadata": {
            "status": "ENDED", "created": timestamp, "lastModified": timestamp,
            "title": "Your First Chapter", "titleSort": "Your First Chapter",
            "summary": "Original Honbako compatibility test content.", "summaryLock": False,
            "readingDirection": "RIGHT_TO_LEFT", "readingDirectionLock": False,
            "publisher": "Honbako", "publisherLock": False, "ageRating": None, "ageRatingLock": False,
            "language": "en", "languageLock": False, "genres": [], "genresLock": False,
            "tags": [], "tagsLock": False, "totalBookCount": 1,
        },
        "booksMetadata": {
            "authors": [{"name": "Honbako", "role": "writer"}], "tags": [],
            "releaseDate": "2026-10-27", "summary": "An original story.", "summaryNumber": "1",
            "created": timestamp, "lastModified": timestamp,
        },
    }
    chapter = {
        "id": "original-1", "seriesId": series["id"], "seriesTitle": series["name"],
        "name": "Your First Chapter", "number": 1, "created": timestamp,
        "lastModified": timestamp, "fileLastModified": timestamp,
        "sizeBytes": sum(map(len, pages)), "size": "Original Test Pages",
        "media": {"status": "READY", "mediaType": "application/zip", "pagesCount": 3},
        "metadata": {
            "title": "Your First Chapter", "titleLock": False, "summary": "An original story.",
            "summaryLock": False, "number": "1", "numberLock": False,
            "numberSort": 1, "numberSortLock": False, "releaseDate": "2026-10-27", "releaseDateLock": False,
            "authors": [{"name": "Honbako", "role": "writer"}], "authorsLock": False,
            "tags": [], "tagsLock": False,
        },
    }

    def collection(items):
        return {"content": items, "empty": not items, "first": True, "last": True, "number": 0,
                "numberOfElements": len(items), "size": 20, "totalElements": len(items), "totalPages": 1}

    requests = []

    class Fixture(BaseHTTPRequestHandler):
        def log_message(self, fmt, *values):
            pass

        def do_GET(self):
            path = urllib.parse.urlparse(self.path).path
            requests.append({"method": "GET", "path": self.path})
            payload, content_type = None, "application/json"
            if path == "/api/v1/series":
                query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("search", [""])[0]
                payload = collection([series] if query.lower() in series["name"].lower() else [])
            elif path == "/api/v1/series/honbako-original":
                payload = series
            elif path == "/api/v1/series/honbako-original/books":
                payload = collection([chapter])
            elif path == "/api/v1/books/original-1/pages":
                payload = [{"number": n, "fileName": "page-%d.png" % n, "mediaType": "image/png"} for n in (1, 2, 3)]
            elif path.startswith("/api/v1/books/original-1/pages/"):
                try:
                    payload = pages[int(path.rsplit("/", 1)[1]) - 1]
                    content_type = "image/png"
                except (ValueError, IndexError):
                    pass
            elif path == "/api/v1/series/honbako-original/thumbnail":
                payload, content_type = cover, "image/png"
            if payload is None:
                self.send_error(404)
                return
            data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    base = "http://127.0.0.1:%d" % server.server_port
    classpath = str(args.bridge_classpath or runtime / "bridge-classes") + ":" + (args.classpath or str(runtime / "Suwayomi-Server-v2.4.2366.jar"))
    responses = []
    stderr_path = runtime / "komga-probe.stderr.log"
    with stderr_path.open("w") as stderr:
        command = [args.java] + args.jvm_arg
        if args.class_log:
            command.append("-Xlog:class+load=info:file=" + str(args.class_log.resolve()))
        process = subprocess.Popen(command + ["-cp", classpath, "com.missingems.honbako.runtime.ExtensionBridge"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr, text=True, bufsize=1)
        try:
            def call(operation, expected_ok=True, preferences=None, **values):
                request = {"operation": operation, "extensionPath": str(package),
                           "preferences": preferences or {"Address": base}, **values}
                process.stdin.write(json.dumps(request) + "\n")
                process.stdin.flush()
                ready, _, _ = select.select([process.stdout], [], [], 40)
                if not ready:
                    raise TimeoutError("Extension operation timed out: " + operation)
                line = process.stdout.readline()
                result = json.loads(line)
                responses.append({"operation": operation, "response": result})
                assert result["ok"] is expected_ok, result
                return result["result"] if expected_ok else result

            discovered = call("discover")
            assert discovered["version"] == "1.6.74"
            assert len(discovered["sources"]) == 3
            source_id = discovered["sources"][0]["id"]
            assert source_id == "4508733312114627536"
            found = call("search", sourceId=source_id, query="Your First")
            assert len(found["entries"]) == 1 and not found["hasNextPage"]
            manga = found["entries"][0]
            assert manga["title"] == "Your First Chapter" and manga["author"] == "Honbako"
            detail = call("details", sourceId=source_id, manga=manga)
            assert detail["manga"]["status"] == 2
            chapters = call("chapters", sourceId=source_id, manga=manga)["chapters"]
            assert len(chapters) == 1 and chapters[0]["number"] == 1
            assert chapters[0]["uploadedAt"] > 0
            resolved = call("pages", sourceId=source_id, chapter=chapters[0])["pages"]
            assert [p["index"] for p in resolved] == [1, 2, 3]
            actual = [call("image", sourceId=source_id, page=page) for page in resolved]
            assert [image["sha256"] for image in actual] == [digest(data) for data in pages]
            assert len(set(image["sha256"] for image in actual)) == 3
            assert [image["bytes"] for image in actual] == [len(data) for data in pages]
            empty = call("search", sourceId=source_id, query="No Such Original Book")
            assert empty["entries"] == []
            unknown = call("search", sourceId="9223372036854775807", query="ignored", expected_ok=False)
            assert unknown["error"] == "Unknown sourceId"
            refused = call("search", sourceId=source_id, query="ignored", expected_ok=False,
                           preferences={"Address": "https://example.invalid"})
            assert "permits only 127.0.0.1" in refused["error"]
            report = {"status": "passed", "execution": "host JVM, not iOS", "extension_sha256": expected,
                      "extension_version": "1.6.74", "source_ids": [s["id"] for s in discovered["sources"]],
                      "operations": responses, "http_requests": requests,
                      "page_sha256": [image["sha256"] for image in actual], "suwayomi_server_started": False}
            dependency = Path(args.classpath) if args.classpath else runtime / "Suwayomi-Server-v2.4.2366.jar"
            report["classpath"] = {"file": dependency.name, "sha256": digest(dependency.read_bytes()),
                                   "bytes": dependency.stat().st_size,
                                   "scope": "only the measured Komga proof; not general Android compatibility"}
            if "--limit-modules=java.base,java.xml,java.logging" in args.jvm_arg:
                report["jdk_modules_required_for_http_proof"] = ["java.base", "java.xml", "java.logging"]
            (runtime / "komga-host-proof.json").write_text(json.dumps(report, indent=2) + "\n")
            print("PASS: published Komga JAR discovery, search, details, chapters, ordered original pages, empty search, unknown-source rejection, and loopback isolation")
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
            (runtime / "komga-last-responses.json").write_text(json.dumps(responses, indent=2) + "\n")


if __name__ == "__main__":
    main()
