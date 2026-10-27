#!/usr/bin/env python3
"""Combine unchanged mobile classes using the pinned official JIMAGE 1.0 writer.

The current host JDK writes format 1.1, which the March mobile runtime rejects.
This builds the original March image writer plus its original ImageHeader as
host-only tools. It does not patch, downgrade, transform, or relink any runtime
class. All outputs and temporary files stay outside the app repository.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess


SOURCE_REVISION = "1606564eddfd17f74015e219cd5b754ec35bf0c8"
WRITER_CLASSES = ("BasicImageWriter", "ImageLocationWriter", "ImageResourcesTree",
                  "ImageStringsWriter", "PerfectHashBuilder")
REQUIRED_VM_OPTION = "-Djdk.system.module.finder.disableFastPath=true"


def sha256(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def tree_digest(path):
    value = hashlib.sha256()
    files = sorted(p for p in path.rglob("*") if p.is_file())
    for item in files:
        value.update(item.relative_to(path).as_posix().encode() + b"\0")
        value.update(bytes.fromhex(sha256(item)))
    return {"sha256": value.hexdigest(), "file_count": len(files),
            "bytes": sum(p.stat().st_size for p in files)}


def run(command, *, cwd=None):
    result = subprocess.run([str(part) for part in command], cwd=cwd,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command[0]}\n"
                           + result.stdout[-12000:])
    return result.stdout.strip()


WRITER_SOURCE = r'''package jdk.tools.jlink.internal;

import java.io.BufferedOutputStream;
import java.io.DataOutputStream;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;

/** The original ImageFileCreator write sequence, without plugins or transforms. */
public final class HonbakoMobileImageWriter {
    private record Entry(Path source, String name, long size) {}

    public static void main(String[] args) throws Exception {
        Path output = Path.of(args[0]);
        var entries = new ArrayList<Entry>();
        var paths = new ArrayList<String>();
        var writer = new BasicImageWriter(ByteOrder.LITTLE_ENDIAN);
        long offset = 0;
        for (int i = 1; i < args.length; i++) {
            Path root = Path.of(args[i]);
            String module = root.getFileName().toString();
            try (var files = Files.walk(root)) {
                for (Path file : files.filter(Files::isRegularFile)
                        .sorted(Comparator.comparing(Path::toString)).toList()) {
                    String path = "/" + module + "/" + root.relativize(file)
                        .toString().replace(java.io.File.separatorChar, '/');
                    long size = Files.size(file);
                    writer.addLocation(path, offset, 0, size);
                    paths.add(path);
                    entries.add(new Entry(file, path, size));
                    offset += size;
                }
            }
        }
        // The upstream tree generates /modules and /packages lookup metadata.
        var tree = new ImageResourcesTree(offset, writer, paths);
        try (var stream = new DataOutputStream(new BufferedOutputStream(
                Files.newOutputStream(output)))) {
            stream.write(writer.getBytes());
            for (Entry entry : entries) Files.copy(entry.source(), stream);
            tree.addContent(stream);
        }
        System.out.println("Wrote " + entries.size() + " unchanged resources to " + output);
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--java-home", type=Path, required=True,
                        help="Host JDK 27 used only to compile and run the image writer")
    parser.add_argument("--jimage", type=Path, required=True,
                        help="JDK 17 jimage executable, which reads original format 1.0")
    parser.add_argument("--fetch-source", action="store_true",
                        help="Materialize the writer paths in the existing pinned sparse source checkout")
    args = parser.parse_args()
    root = args.runtime_root.resolve()
    repo = Path(__file__).resolve().parents[2]
    if root == repo or repo in root.parents:
        raise ValueError("Image output must be outside the app checkout")
    source = root / "mobile-matched-source"
    if run(["git", "rev-parse", "HEAD"], cwd=source) != SOURCE_REVISION:
        raise ValueError("Use the pinned official source revision")
    if args.fetch_source:
        run(["git", "sparse-checkout", "add", "src/jdk.jlink/share/classes/jdk/tools/jlink/internal",
             "src/java.base/share/classes/jdk/internal/jimage"], cwd=source)
    header_relative = Path("src/java.base/share/classes/jdk/internal/jimage/ImageHeader.java")
    writer_relative = Path("src/jdk.jlink/share/classes/jdk/tools/jlink/internal")
    source_files = [header_relative] + [writer_relative / (name + ".java") for name in WRITER_CLASSES]
    run(["git", "diff", "--quiet", "HEAD", "--", *source_files], cwd=source)
    for path in source_files:
        if not (source / path).is_file():
            raise ValueError("Sparse-checkout required source path: " + str(path))
    inputs = (root / "java.base-matched-device/java.base",
              root / "java-extra-matched/java.logging", root / "java-extra-matched/java.xml")
    for path in inputs:
        if not (path / "module-info.class").is_file():
            raise ValueError("Prepare exact base and rebuilt modules first: " + str(path))
    expected_inputs = {path.name: tree_digest(path) for path in inputs}
    matching_provenance = root / "matching-modules-provenance.json"
    provenance = json.loads(matching_provenance.read_text())
    if not provenance.get("module_packages", {}).get("verified"):
        raise ValueError("Rebuild modules with complete ModulePackages metadata before image creation")
    if provenance["mobile_base"]["sha256"] != expected_inputs["java.base"]["sha256"]:
        raise ValueError("Exact mobile base changed since module compilation")
    for name in ("java.logging", "java.xml"):
        if "ModulePackages" not in provenance["modules"][name]["descriptor"]["attributes"]:
            raise ValueError("Missing concealed-package metadata: " + name)
        if provenance["modules"][name]["sha256"] != expected_inputs[name]["sha256"]:
            raise ValueError("Rebuilt module changed since compilation: " + name)
    work = root / "mobile-image-builder"
    if work.exists():
        shutil.rmtree(work)
    header_source = work / "header-source/jdk/internal/jimage"
    header_source.mkdir(parents=True)
    shutil.copyfile(source / header_relative, header_source / "ImageHeader.java")
    writer_source = work / "writer-source/jdk/tools/jlink/internal"
    writer_source.mkdir(parents=True)
    for name in WRITER_CLASSES:
        shutil.copyfile(source / writer_relative / (name + ".java"), writer_source / (name + ".java"))
    (writer_source / "HonbakoMobileImageWriter.java").write_text(WRITER_SOURCE)
    header_classes, writer_classes = work / "header-classes", work / "writer-classes"
    header_classes.mkdir()
    writer_classes.mkdir()
    javac, java = args.java_home / "bin/javac", args.java_home / "bin/java"
    if run([javac, "-version"]) != "javac 27":
        raise ValueError("Use a Java 27 host compiler")
    run([javac, "--patch-module", f"java.base={work / 'header-source'}",
         "-d", header_classes, header_source / "ImageHeader.java"])
    run([javac, "-Xlint:none", "--patch-module", f"jdk.jlink={work / 'writer-source'}",
         "-d", writer_classes, *sorted(writer_source.glob("*.java"))])
    image_root = root / "combinedimage"
    (image_root / "lib").mkdir(parents=True, exist_ok=True)
    image = image_root / "lib/modules"
    result = run([java, "--patch-module", f"java.base={header_classes}",
                  "--patch-module", f"jdk.jlink={writer_classes}",
                  "-m", "jdk.jlink/jdk.tools.jlink.internal.HonbakoMobileImageWriter",
                  image, *inputs])
    with image.open("rb") as stream:
        header = struct.unpack("<7I", stream.read(28))
    if header[0] != 0xCAFEDADA or header[1] != 0x00010000 or header[2] != 0:
        raise ValueError("Image is not original format 1.0 with zero flags")
    verification = root / "mobile-image-verification"
    if verification.exists():
        shutil.rmtree(verification)
    try:
        info = run([args.jimage, "info", image])
        run([args.jimage, "extract", "--dir", verification, image])
        extracted = {path.name: tree_digest(path) for path in verification.iterdir() if path.is_dir()}
        if extracted != expected_inputs:
            raise ValueError("Image extraction differs from unchanged source module trees")
    finally:
        if verification.exists():
            shutil.rmtree(verification)
    (image_root / "release").write_text('MODULES="java.base java.logging java.xml"\n')
    report = {
        "experimental": True, "image": str(image), "image_sha256": sha256(image),
        "image_bytes": image.stat().st_size, "format": "1.0", "header_flags": 0,
        "required_vm_options": [REQUIRED_VM_OPTION],
        "source_revision": SOURCE_REVISION,
        "source_url": f"https://github.com/openjdk/mobile/tree/{SOURCE_REVISION}",
        "writer_sources": {str(path): sha256(source / path) for path in source_files},
        "base_and_module_bytes_unchanged": True,
        "module_descriptor_packages_complete": True,
        "verification": "JDK 17 jimage extraction tree hashes exactly match all three input module trees",
        "modules": expected_inputs,
        "matching_module_provenance_sha256": sha256(matching_provenance),
        "jimage_info": info,
        "note": "Original ImageResourcesTree includes /modules and /packages lookup metadata. No transforms or generated SystemModules classes applied. Disable the old java.base-only precomputed module graph using the required VM option. No host module classes enter the runtime image.",
    }
    (root / "mobile-image-provenance.json").write_text(json.dumps(report, indent=2) + "\n")
    print(result)
    print(json.dumps(report, indent=2))
    # The writer is reproducible and host-only; retain sources and outputs, but
    # discard exploratory whole-tool compilation created before this minimal path.
    for name in ("matching-jlink-tool", "matching-jimage-header", "matching-jimage-header-source"):
        path = root / name
        if path.exists():
            shutil.rmtree(path)


if __name__ == "__main__":
    main()
