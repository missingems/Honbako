#!/usr/bin/env python3
"""Build portable Java modules against the official March 15 mobile java.base.

All source checkouts, generated sources, classes, logs and provenance stay under
--runtime-root, outside the app repository. This does not build or install iOS
targets and does not modify the previously prepared experimental runtime.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess


SOURCE_REPOSITORY = "https://github.com/openjdk/mobile.git"
SOURCE_REVISION = "1606564eddfd17f74015e219cd5b754ec35bf0c8"
SOURCE_DATE = "2026-03-14T14:06:38Z"
MOBILE_IMAGE_SHA256 = "37387a48bdd7f1ce1d3a38e88356e61288673c91b42ef27cf1b71d27e05cc54a"
MODULES = ("java.logging", "java.xml")
SPARSE_PATHS = (
    "src/java.logging", "src/java.xml", "make/modules/java.logging",
    "make/modules/java.xml", "make/jdk/src/classes/build/tools/compileproperties",
    "src/java.base/share/classes/jdk/internal/module",
)


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


def run(command, *, cwd=None, log=None):
    command = [str(part) for part in command]
    if log:
        with log.open("w") as stream:
            result = subprocess.run(command, cwd=cwd, stdout=stream,
                                    stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f"Command failed ({result.returncode}): {command[0]}\n"
                               + log.read_text()[-12000:])
        return log.read_text()
    return subprocess.run(command, cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE).stdout.strip()


def classfile_attributes(path):
    """Read descriptor attributes, rather than trusting host javap formatting."""
    data = path.read_bytes()
    if data[:4] != b"\xca\xfe\xba\xbe":
        raise ValueError(f"Invalid class file: {path}")
    major = struct.unpack_from(">H", data, 6)[0]
    pool_count = struct.unpack_from(">H", data, 8)[0]
    offset, index, strings = 10, 1, {}
    sizes = {3: 4, 4: 4, 5: 8, 6: 8, 7: 2, 8: 2, 9: 4, 10: 4, 11: 4,
             12: 4, 15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2}
    while index < pool_count:
        tag = data[offset]
        offset += 1
        if tag == 1:
            length = struct.unpack_from(">H", data, offset)[0]
            offset += 2
            strings[index] = data[offset:offset + length].decode("utf-8")
            offset += length
        else:
            offset += sizes[tag]
            if tag in (5, 6):
                index += 1
        index += 1
    # access_flags, this_class, super_class, interfaces_count
    interfaces = struct.unpack_from(">H", data, offset + 6)[0]
    offset += 8 + 2 * interfaces
    for _ in range(2):  # fields, methods
        count = struct.unpack_from(">H", data, offset)[0]
        offset += 2
        for _ in range(count):
            attributes = struct.unpack_from(">H", data, offset + 6)[0]
            offset += 8
            for _ in range(attributes):
                length = struct.unpack_from(">I", data, offset + 2)[0]
                offset += 6 + length
    count = struct.unpack_from(">H", data, offset)[0]
    offset += 2
    names = []
    for _ in range(count):
        name, length = struct.unpack_from(">HI", data, offset)
        names.append(strings[name])
        offset += 6 + length
    return {"class_major": major, "attributes": names}


SMOKE_SOURCE = r'''import java.io.StringReader;
import java.io.StringWriter;
import java.util.Locale;
import java.util.logging.Level;
import java.util.logging.Logger;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.stream.XMLInputFactory;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;
import javax.xml.xpath.XPathFactory;
import org.xml.sax.InputSource;

public final class MatchingModulesSmoke {
    public static void main(String[] args) throws Exception {
        Locale.setDefault(Locale.JAPANESE);
        Logger.getLogger("Honbako.MatchingModules").info("Logging module passed");
        if (Level.INFO.getLocalizedName().isEmpty()) throw new AssertionError();
        var factory = DocumentBuilderFactory.newInstance();
        factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        var document = factory.newDocumentBuilder().parse(new InputSource(
            new StringReader("<manifest package='honbako.test'><application/></manifest>")));
        if (!"honbako.test".equals(XPathFactory.newInstance().newXPath()
            .evaluate("/manifest/@package", document))) throw new AssertionError();
        var transformed = new StringWriter();
        TransformerFactory.newInstance().newTransformer().transform(
            new DOMSource(document), new StreamResult(transformed));
        if (!transformed.toString().contains("honbako.test")) throw new AssertionError();
        var stream = XMLInputFactory.newInstance().createXMLStreamReader(
            new StringReader("<root/>"));
        while (stream.hasNext()) stream.next();
        stream.close();
        System.out.println("Logging, localized bundles, secure DOM, XPath, transform and StAX passed");
        System.out.println("Logging class: " + Logger.class.getResource("Logger.class"));
        System.out.println("XML class: " + DocumentBuilderFactory.class.getResource("DocumentBuilderFactory.class"));
    }
}
'''


PACKAGES_SOURCE = r'''import java.lang.module.ModuleDescriptor;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Set;
import java.util.TreeSet;
import jdk.internal.module.ModuleInfoExtender;

public final class MatchingModulePackages {
    public static void main(String[] args) throws Exception {
        for (String name : args) {
            Path root = Path.of(name);
            Path descriptor = root.resolve("module-info.class");
            Set<String> packages = new TreeSet<>();
            try (var files = Files.walk(root)) {
                for (Path file : files.filter(Files::isRegularFile)
                        .filter(p -> p.toString().endsWith(".class")).toList()) {
                    Path parent = root.relativize(file).getParent();
                    if (parent != null) packages.add(parent.toString()
                        .replace(java.io.File.separatorChar, '.'));
                }
            }
            byte[] bytes;
            try (var input = Files.newInputStream(descriptor)) {
                bytes = ModuleInfoExtender.newExtender(input).packages(packages).toByteArray();
            }
            Files.write(descriptor, bytes);
            // No package finder: the descriptor itself must contain the full set.
            try (var input = Files.newInputStream(descriptor)) {
                var module = ModuleDescriptor.read(input);
                if (!module.packages().equals(packages)) throw new AssertionError(
                    "Concealed packages missing from " + module.name());
                if (module.name().equals("java.xml") &&
                        !module.packages().contains("jdk.xml.internal")) throw new AssertionError();
                System.out.println(module.name() + ": " + packages.size() + " packages verified");
            }
        }
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--java-home", type=Path, required=True)
    parser.add_argument("--fetch-source", action="store_true",
                        help="Fetch only the pinned official source paths if absent")
    args = parser.parse_args()
    root = args.runtime_root.resolve()
    repo = Path(__file__).resolve().parents[2]
    if root == repo or repo in root.parents:
        raise ValueError("Runtime build output must be outside the app checkout")
    root.mkdir(parents=True, exist_ok=True)
    source = root / "mobile-matched-source"
    if args.fetch_source:
        if not source.exists():
            run(["git", "clone", "--filter=blob:none", "--no-checkout", "--depth", "1",
                 SOURCE_REPOSITORY, source])
        run(["git", "fetch", "--filter=blob:none", "--depth", "1", "origin", SOURCE_REVISION], cwd=source)
        run(["git", "sparse-checkout", "set", *SPARSE_PATHS], cwd=source)
        run(["git", "checkout", "--detach", SOURCE_REVISION], cwd=source)
    if run(["git", "rev-parse", "HEAD"], cwd=source) != SOURCE_REVISION:
        raise ValueError("Source checkout does not match the pinned revision")
    run(["git", "diff", "--quiet", "HEAD", "--", *SPARSE_PATHS], cwd=source)
    image_zip = root / "java_bundle-device.zip"
    if sha256(image_zip) != MOBILE_IMAGE_SHA256:
        raise ValueError("Official mobile image archive does not match the pinned release")
    base = root / "java.base-matched-device/java.base"
    base_info = classfile_attributes(base / "module-info.class")
    if base_info["class_major"] != 71:
        raise ValueError("Expected the March 15 Java 27 mobile java.base")
    java_home = args.java_home.resolve()
    javac, java = java_home / "bin/javac", java_home / "bin/java"
    compiler_version = run([javac, "-version"])
    if compiler_version != "javac 27":
        raise ValueError(f"Use the Java 27 compiler, got {compiler_version!r}")
    output = root / "java-extra-matched"
    generated = root / "matching-module-generated"
    tools = root / "matching-module-tools"
    for directory in (output, generated, tools):
        if directory.exists():
            shutil.rmtree(directory)
        directory.mkdir()
    commands = []
    generator = source / "make/jdk/src/classes/build/tools/compileproperties/CompileProperties.java"
    command = [javac, "-d", tools, generator]
    commands.append([str(part) for part in command])
    run(command)
    command = [java, "-cp", tools, "build.tools.compileproperties.CompileProperties", "-quiet"]
    logging_source = source / "src/java.logging/share/classes"
    for properties in sorted((logging_source / "sun/util/logging/resources").glob("*.properties")):
        target = generated / "java.logging" / properties.relative_to(logging_source).with_suffix(".java")
        target.parent.mkdir(parents=True, exist_ok=True)
        command += ["-compile", properties, target, "ListResourceBundle"]
    commands.append([str(part) for part in command])
    run(command)
    command = [javac, "-J-Xmx2g", "--system", "none", "--module-path", base.parent,
               "-Xlint:none", "-d", output]
    # Explicit mappings prevent sparse java.base tool sources from shadowing
    # the exact binary java.base supplied on the module path.
    for module in MODULES:
        roots = [source / "src" / module / "share/classes"]
        if (generated / module).is_dir():
            roots.append(generated / module)
        command += ["--module-source-path", module + "=" + os.pathsep.join(map(str, roots))]
    command += ["-m", ",".join(MODULES)]
    commands.append([str(part) for part in command])
    run(command, log=root / "matching-module-compile.log")
    # OpenJDK java.xml/Java.gmk copies these resources. Properties remain
    # semantically unchanged; the upstream CLEAN pass only removes comments.
    resources = []
    xml_source = source / "src/java.xml/share/classes"
    for item in sorted(xml_source.rglob("*")):
        if item.is_file() and item.suffix in (".properties", ".dtd", ".xsd", ".xml", ".ent", ".mod"):
            target = output / "java.xml" / item.relative_to(xml_source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(item, target)
            resources.append(item.relative_to(xml_source).as_posix())
    conf = root / "java-extra-matched-conf"
    conf.mkdir(exist_ok=True)
    legal = root / "java-extra-matched-legal"
    legal.mkdir(exist_ok=True)
    for module in MODULES:
        for item in (source / "src" / module / "share/conf").glob("*"):
            if item.is_file():
                shutil.copyfile(item, conf / item.name)
        module_legal = source / "src" / module / "share/legal"
        if module_legal.exists():
            shutil.copytree(module_legal, legal / module, dirs_exist_ok=True)
    for name in ("LICENSE", "ADDITIONAL_LICENSE_INFO", "ASSEMBLY_EXCEPTION"):
        if (source / name).is_file():
            shutil.copyfile(source / name, legal / name)
    # Unlike an exploded module directory, a JIMAGE finder cannot discover
    # concealed packages by scanning files. Apply the same ModulePackages
    # metadata that the official jlink SystemModulesPlugin/ModuleInfoExtender
    # supplies, using the pinned extender source as a host-only tool.
    extender_relative = Path("src/java.base/share/classes/jdk/internal/module/ModuleInfoExtender.java")
    extender_source = tools / "extender-source/jdk/internal/module"
    extender_source.mkdir(parents=True)
    shutil.copyfile(source / extender_relative, extender_source / "ModuleInfoExtender.java")
    extender_classes = tools / "extender-classes"
    extender_classes.mkdir()
    command = [javac, "--patch-module", f"java.base={tools / 'extender-source'}",
               "-d", extender_classes, extender_source / "ModuleInfoExtender.java"]
    commands.append([str(part) for part in command])
    run(command)
    package_source = tools / "MatchingModulePackages.java"
    package_source.write_text(PACKAGES_SOURCE)
    command = [javac, "--add-exports", "java.base/jdk.internal.module=ALL-UNNAMED",
               "-d", tools, package_source]
    commands.append([str(part) for part in command])
    run(command)
    command = [java, "--patch-module", f"java.base={extender_classes}",
               "--add-exports", "java.base/jdk.internal.module=ALL-UNNAMED",
               "-cp", tools, "MatchingModulePackages", *[output / name for name in MODULES]]
    commands.append([str(part) for part in command])
    package_result = run(command, log=root / "matching-module-packages.log")
    modules = {}
    for module in MODULES:
        descriptor = classfile_attributes(output / module / "module-info.class")
        if ("ModuleTarget" in descriptor["attributes"] or descriptor["class_major"] != 71
                or "ModulePackages" not in descriptor["attributes"]):
            raise ValueError(f"Unexpected platform stamp or class version: {module}")
        packages = {p.parent.relative_to(output / module).as_posix().replace("/", ".")
                    for p in (output / module).rglob("*.class") if p.name != "module-info.class"}
        modules[module] = {"path": str(output / module), **tree_digest(output / module),
                           "class_count": len(list((output / module).rglob("*.class"))),
                           "package_count": len(packages),
                           "descriptor": descriptor}
    smoke = root / "matching-module-smoke"
    smoke.mkdir(exist_ok=True)
    smoke_source = smoke / "MatchingModulesSmoke.java"
    smoke_source.write_text(SMOKE_SOURCE)
    run([javac, "-d", smoke, smoke_source])
    command = [java, "--limit-modules", "java.base,java.logging,java.xml"]
    for module in MODULES:
        command += ["--patch-module", f"{module}={output / module}"]
    command += ["-cp", smoke, "MatchingModulesSmoke"]
    smoke_result = run(command, log=root / "matching-module-smoke.log")
    for module in MODULES:
        if str(output / module) not in smoke_result:
            raise ValueError(f"Host smoke test did not load rebuilt {module}")
    report = {
        "experimental": True,
        "source_repository": SOURCE_REPOSITORY,
        "source_revision": SOURCE_REVISION,
        "source_revision_date": SOURCE_DATE,
        "source_revision_selection": "Latest official mobile commit before 2026-03-15T05:00:00Z; release does not publish its source SHA",
        "source_url": f"https://github.com/openjdk/mobile/tree/{SOURCE_REVISION}",
        "source_matches_release_proven": False,
        "compiles_against_exact_mobile_base": True,
        "mobile_base": {"path": str(base), **tree_digest(base), "descriptor": base_info},
        "mobile_release_archive_sha256": MOBILE_IMAGE_SHA256,
        "compiler": {"version": compiler_version, "path": str(javac), "sha256": sha256(javac)},
        "compilation_commands": commands,
        "modules": modules,
        "xml_resource_count": len(resources),
        "conf_path": str(conf), "legal_path": str(legal),
        "platform_stamp": "No ModuleTarget attribute on either rebuilt module",
        "module_packages": {"verified": True, "log": str(root / "matching-module-packages.log"),
                            "result": package_result.strip(), "extender_source": str(extender_relative),
                            "extender_source_sha256": sha256(source / extender_relative),
                            "method": "Pinned official ModuleInfoExtender adds every compiled class package; ModuleDescriptor.read without a finder verifies exact sets, including concealed jdk.xml.internal"},
        "host_smoke": {"passed": True, "log": str(root / "matching-module-smoke.log"),
                       "checks": "Logging, localized bundle, secure DOM, XPath, transform, StAX; actual rebuilt class URLs verified"},
        "physical_device_verified": False,
        "note": "Pure Java modules only. No Homebrew module classes or module-info files copied. Source revision is pinned by date, not established as the exact release build SHA. No production dependency consistency claim.",
    }
    provenance = root / "matching-modules-provenance.json"
    provenance.write_text(json.dumps(report, indent=2) + "\n")
    # Generator tools/classes are reproducible intermediates, not runtime files.
    shutil.rmtree(tools)
    print(json.dumps({"modules": modules, "provenance": str(provenance),
                      "host_smoke_passed": True}, indent=2))


if __name__ == "__main__":
    main()
