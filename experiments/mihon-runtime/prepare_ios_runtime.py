#!/usr/bin/env python3
"""Prepare isolated native-probe resources; never modifies Honbako's app target."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from build_matching_modules import tree_digest


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-root', type=Path, required=True)
    parser.add_argument('--java-home', type=Path, required=True)
    args = parser.parse_args()
    root = args.runtime_root.resolve()
    experiment = Path(__file__).resolve().parent
    repo = experiment.parents[1]
    if root == repo or repo in root.parents:
        raise ValueError('Put downloaded runtime artifacts outside the Git checkout')
    for name in ['honbako-extension-bridge-v2.jar', 'komga-proof-dependencies.jar', 'tachiyomi-all.komga-v1.6.74.jar']:
        if not (root / name).is_file():
            raise ValueError('Prepare the verified host runtime first: ' + name)
    bridge_proof_path = root / 'bridge-v2-host-proof.json'
    if not bridge_proof_path.is_file():
        raise ValueError('Run probe_bridge_v2.py before staging the native executor')
    bridge_proof = json.loads(bridge_proof_path.read_text())
    if bridge_proof.get('status') != 'passed' or digest(root / 'honbako-extension-bridge-v2.jar') != bridge_proof.get('bridge_v2_sha256'):
        raise ValueError('The current v2 bridge does not match its passing host proof')
    dependency_pin = bridge_proof.get('runtime_dependency_jar_sha256')
    if dependency_pin is not None and digest(root / 'komga-proof-dependencies.jar') != dependency_pin:
        raise ValueError('The runtime dependency JAR does not match its passing v2 host proof')
    # Desktop jmods carry a macOS ModuleTarget and cannot be mixed with the
    # iOS java.base. Rebuild pure-Java modules against the exact mobile base.
    provenance_path = root / 'matching-modules-provenance.json'
    if not provenance_path.is_file():
        raise ValueError('Run build_matching_modules.py first; desktop jmods are not accepted')
    module_inputs = json.loads(provenance_path.read_text())
    for name in ['java.logging', 'java.xml']:
        module = root / 'java-extra-matched' / name
        if not (module / 'module-info.class').is_file():
            raise ValueError('Missing rebuilt mobile module: ' + name)
        if tree_digest(module)['sha256'] != module_inputs['modules'][name]['sha256']:
            raise ValueError('Rebuilt mobile module hash mismatch: ' + name)
    image_inputs = json.loads((root / 'mobile-image-provenance.json').read_text())
    image = root / 'combinedimage/lib/modules'
    if (digest(image) != image_inputs['image_sha256'] or
        digest(provenance_path) != image_inputs['matching_module_provenance_sha256']):
        raise ValueError('Combined image or matching module provenance changed')
    # These selected, non-secret configuration files are diagnostic inputs.
    # Do not copy a host trust store, credentials or local security overrides.
    conf = root / 'java-conf'
    if conf.is_symlink():
        conf.unlink()
    elif conf.exists():
        shutil.rmtree(conf)
    conf.mkdir()
    configuration_inputs = {}
    selected = ['net.properties', 'logging.properties', 'security/java.security',
                'security/java.policy']
    selected += [str(p.relative_to(args.java_home / 'conf'))
                 for p in sorted((args.java_home / 'conf/security/policy').rglob('*.policy'))]
    for name in selected:
        source = args.java_home / 'conf' / name
        if source.is_file():
            target = conf / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            configuration_inputs[name] = digest(source)
    for source in sorted((root / 'java-extra-matched-conf').rglob('*')):
        if source.is_file():
            name = source.relative_to(root / 'java-extra-matched-conf')
            target = conf / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            configuration_inputs[str(name)] = digest(source)
    # The upstream compact image omits the portable time-zone data required by
    # java.time. Record this standard JDK data file separately from class code.
    timezone = args.java_home / 'lib/tzdb.dat'
    if not timezone.is_file():
        raise ValueError('JDK time-zone database is missing')
    (root / 'java-data').mkdir(exist_ok=True)
    shutil.copyfile(timezone, root / 'java-data/tzdb.dat')
    fixture = root / 'fixture'
    fixture.mkdir(exist_ok=True)
    art = repo / 'Aidoku/App/Resources/Assets.xcassets'
    for number in range(1, 4):
        shutil.copyfile(art / ('HonbakoTutorialPage%dArt.imageset' % number) / 'art.png', fixture / ('page-%d.png' % number))
    shutil.copyfile(art / 'HonbakoTutorialCoverArt.imageset/art.png', fixture / 'cover.png')
    classes = root / 'probe-classes'
    classes.mkdir(exist_ok=True)
    subprocess.run([str(args.java_home / 'bin/javac'), '--release', '17', '-d', str(classes),
                    str(experiment / 'java/RuntimeProbe.java')], check=True)
    subprocess.run([str(args.java_home / 'bin/jar'), '--create', '--file', str(root / 'RuntimeProbe.jar'),
                    '-C', str(classes), '.'], check=True)
    (root / 'native-probe-inputs.json').write_text(json.dumps({
        'experimental': True,
        'production_dependency_revision_consistent': False,
        'note': 'Official March15 iOS framework/base plus portable modules compiled from the pinned official mobile source against the exact deployed base. Exact release source SHA is unpublished; selected host configuration remains diagnostic-only.',
        'extra_module_inputs': module_inputs,
        'runtime_image_sha256': digest(image),
        'configuration_sha256': configuration_inputs,
        'timezone_database': {'source': str(timezone), 'sha256': digest(timezone)},
        'bridge_bundle_alias': {'source': 'honbako-extension-bridge-v2.jar', 'bundled_name': 'honbako-extension-bridge.jar'},
        'jars': {name: digest(root / name) for name in ['honbako-extension-bridge-v2.jar',
                  'komga-proof-dependencies.jar', 'tachiyomi-all.komga-v1.6.74.jar']},
        'fixture_sha256': {path.name: digest(path) for path in fixture.glob('*.png')}
    }, indent=2) + '\n')
    print('Prepared isolated native probe; no production target changed.')


if __name__ == '__main__':
    main()
