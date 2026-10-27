#!/usr/bin/env python3
"""Reproduce a real extension proof; downloaded binaries stay outside the checkout."""
import argparse
import atexit
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

REFERENCE = {
    "file": "Suwayomi-Server-v2.4.2366.jar",
    "url": "https://github.com/Suwayomi/Suwayomi-Server/releases/download/v2.4.2366/Suwayomi-Server-v2.4.2366.jar",
    "sha256": "af9feb20af9d7ebe9e30769e6c6ebc7fc7ab1c447388d42e0280b1da5fe07bfd",
}
EXTENSION = {
    "file": "tachiyomi-all.komga-v1.6.74.jar",
    "url": "https://github.com/keiyoushi/extensions/releases/download/ff521c1/tachiyomi-all.komga-v1.6.74.jar",
    "sha256": "9f1b4a05113f33d4de7f5177dded79419ef33e5d91c3ce38a3e55b609c522013",
}


def checksum(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def fetch(root, artifact):
    path = root / artifact["file"]
    if not path.exists():
        with urllib.request.urlopen(artifact["url"], timeout=90) as source, path.open("wb") as target:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                target.write(block)
    if checksum(path) != artifact["sha256"]:
        raise ValueError("Artifact checksum mismatch: " + path.name)
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--java-home", type=Path, default=Path("/opt/homebrew/opt/openjdk@27"))
    parser.add_argument("--keep-reference", action="store_true", help="Keep the 183 MB reference JAR for debugging")
    args = parser.parse_args()
    experiment = Path(__file__).resolve().parent
    repo = experiment.parents[1]
    root = args.runtime_root.resolve()
    if root == repo or repo in root.parents:
        raise ValueError("Runtime binaries must be stored outside the Git checkout")
    root.mkdir(parents=True, exist_ok=True)
    reference = root / REFERENCE["file"]
    if not args.keep_reference:
        atexit.register(lambda: reference.unlink(missing_ok=True))
    reference = fetch(root, REFERENCE)
    package = fetch(root, EXTENSION)
    classes = root / "bridge-v2-classes"
    if classes.exists():
        shutil.rmtree(classes)
    classes.mkdir(exist_ok=True)
    # Compile only the bridge and its own host services. APK conversion tools
    # and host-only test sources must never leak into the native bridge JAR.
    sources = [str(experiment / "java" / name) for name in [
        "android/os/Handler.java", "android/os/Looper.java",
        "eu/kanade/tachiyomi/network/NetworkHelper.java",
        "eu/kanade/tachiyomi/network/interceptor/CloudflareInterceptor.java",
        "com/missingems/honbako/runtime/ExtensionBridge.java",
        "com/missingems/honbako/runtime/KomgaDeviceProbe.java"]]
    java, javac = str(args.java_home / "bin/java"), str(args.java_home / "bin/javac")
    subprocess.run([javac, "--release", "17", "-classpath", str(reference), "-d", str(classes)] + sources, check=True)
    log = root / "komga-reference-classes.log"
    common = ["python3", str(experiment / "probe_komga.py"), "--runtime-root", str(root), "--java", java,
              "--bridge-classpath", str(classes),
              "--jvm-arg=--limit-modules=java.base,java.xml,java.logging"]
    subprocess.run(common + ["--class-log", str(log)], check=True)
    text = log.read_text()
    loaded = set()
    for line in text.splitlines():
        found = re.search(r"\[class,load\] ([^ ]+) source: file:(.*)", line)
        if found and Path(urllib.request.url2pathname(found.group(2))).resolve() == reference:
            loaded.add(found.group(1).replace(".", "/") + ".class")
    assert loaded, "Reference runtime classes were not profiled"
    reduced = root / "komga-proof-dependencies.jar"
    entries = {}
    with zipfile.ZipFile(reference) as source:
        names = set(source.namelist())
        # Coroutine completion paths can link exception/helper classes only on
        # a different scheduling interleaving. Keep these complete libraries,
        # rather than treating one class-loading trace as a complete API.
        library_prefixes = ("kotlin/", "kotlinx/", "okhttp3/", "okio/", "com/fasterxml/jackson/")
        selected = loaded | {name for name in names if name.endswith(".class") and name.startswith(library_prefixes)}
        for name in sorted(selected):
            if name not in names:
                raise ValueError("Unable to resolve profiled class: " + name)
            entries[name] = source.read(name)
        # Preserve bundled notices/provenance and runtime service configuration.
        # This is a measured proof subset, not a distributable general runtime.
        for info in source.infolist():
            name = info.filename
            if info.is_dir() or info.file_size > 256 * 1024 or name.endswith(".class"):
                continue
            if (name.startswith("META-INF/") and ("LICENSE" in name.upper() or "NOTICE" in name.upper()
                                                  or name.endswith("pom.properties") or name.endswith("pom.xml")
                                                  or name.startswith("META-INF/services/"))):
                entries[name] = source.read(info)
    with zipfile.ZipFile(reduced, "w", compression=zipfile.ZIP_DEFLATED) as target:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(info, data)
    upgraded = root / "honbako-extension-bridge-v2.jar"
    with zipfile.ZipFile(upgraded, "w", compression=zipfile.ZIP_DEFLATED) as target, zipfile.ZipFile(reference) as source:
        bridge_entries = {item.relative_to(classes).as_posix(): item.read_bytes() for item in classes.rglob("*.class")}
        # Real HttpSource default imageRequest needs this helper. Komga's
        # override alone does not load it during the initial reference trace.
        name = "eu/kanade/tachiyomi/network/RequestsKt.class"
        bridge_entries[name] = source.read(name)
        for name, data in sorted(bridge_entries.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(info, data)
    # A compile-only subset supports type checking the first-party HttpSource
    # test subclass. It is not bundled in the native app and does not rely on
    # the independent APK experiment or a historical bridge binary.
    compile_dependencies = root / "bridge-compile-dependencies.jar"
    with zipfile.ZipFile(reference) as source, zipfile.ZipFile(compile_dependencies, "w", compression=zipfile.ZIP_DEFLATED) as target:
        prefixes = ("android/", "androidx/preference/", "eu/kanade/tachiyomi/source/", "eu/kanade/tachiyomi/network/", "rx/")
        for name in sorted(set(source.namelist())):
            if name.endswith(".class") and name.startswith(prefixes):
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                target.writestr(info, source.read(name))
    (root / "bridge-v2-build.json").write_text(json.dumps({
        "artifact": upgraded.name, "sha256": checksum(upgraded), "reference": REFERENCE,
        "java_home": str(args.java_home), "target_release": 17,
        "source_sha256": {str(Path(name).relative_to(experiment)): checksum(Path(name)) for name in sources},
        "compile_only_dependencies_sha256": checksum(compile_dependencies),
        "dependency_jar_sha256": checksum(reduced), "requests_helper_from_pinned_reference": True,
        "historical_baseline_jar_modified": False}, indent=2) + "\n")
    subprocess.run(common + ["--classpath", str(reduced), "--class-log", str(root / "komga-reduced-classes.log")], check=True)
    # Run the same in-process socket fixture intended for the native JNI host.
    # Its image bytes come solely from this repository's original tutorial art.
    with tempfile.TemporaryDirectory(prefix="honbako-device-fixture-", dir=root) as temporary:
        bundle = Path(temporary)
        fixture = bundle / "fixture"
        fixture.mkdir()
        artwork = repo / "Aidoku/App/Resources/Assets.xcassets"
        for index in range(1, 4):
            shutil.copy2(artwork / ("HonbakoTutorialPage%dArt.imageset" % index) / "art.png", fixture / ("page-%d.png" % index))
        shutil.copy2(artwork / "HonbakoTutorialCoverArt.imageset/art.png", fixture / "cover.png")
        shutil.copy2(package, bundle / package.name)
        process = subprocess.run([java, "--limit-modules=java.base,java.xml,java.logging", "-cp", str(classes) + ":" + str(reduced),
            "com.missingems.honbako.runtime.KomgaDeviceProbe", str(bundle)], text=True, capture_output=True, timeout=45)
        (root / "komga-device-probe-host.stderr.log").write_text(process.stderr)
        (root / "komga-device-probe-host.json").write_text(process.stdout)
        assert process.returncode == 0 and json.loads(process.stdout)["ok"], "Self-contained device probe failed on host"
    proof = json.loads((root / "komga-host-proof.json").read_text())
    proof["classpath"] = {"file": reduced.name, "sha256": checksum(reduced), "bytes": reduced.stat().st_size,
                          "loaded_reference_classes": len(loaded), "reference_artifact": REFERENCE,
                          "scope": "only the measured Komga proof; not general Android compatibility"}
    proof["jdk_modules_required_for_http_proof"] = ["java.base", "java.xml", "java.logging"]
    proof["extension_artifact"] = EXTENSION
    (root / "komga-host-proof.json").write_text(json.dumps(proof, indent=2) + "\n")
    (root / "komga-proof-classpath.json").write_text(json.dumps({"classes": sorted(loaded), "reference": REFERENCE,
        "dependency_jar_sha256": checksum(reduced), "extension": EXTENSION}, indent=2) + "\n")
    subprocess.run(["python3", str(experiment / "probe_bridge_v2.py"), "--runtime-root", str(root),
                    "--java-home", str(args.java_home)], check=True)
    if not args.keep_reference:
        reference.unlink(missing_ok=True)
    print("Reduced test dependency JAR:", reduced.stat().st_size, "bytes;", len(loaded), "reference classes")


if __name__ == "__main__":
    main()
