#!/usr/bin/env python3
"""Fetch pinned, approved OpenJDK artifacts for the isolated iOS experiment."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-root', type=Path, required=True)
    parser.add_argument('--simulator', action='store_true', help='Also unpack the upstream simulator classes (known startup issue)')
    args = parser.parse_args()
    root = args.runtime_root.resolve()
    experiment = Path(__file__).resolve().parent
    repo = experiment.parents[1]
    if root == repo or repo in root.parents:
        raise ValueError('Keep downloaded runtime binaries outside the Git checkout')
    root.mkdir(parents=True, exist_ok=True)
    wanted = {'OpenJDK.xcframework.zip', 'java_bundle-device.zip'}
    if args.simulator:
        wanted.add('java_bundle-simulator.zip')
    record = json.loads((experiment / 'OPENJDK-SNAPSHOT.json').read_text())
    for artifact in record['assets']:
        name = artifact['name']
        if name not in wanted:
            continue
        destination = root / name
        if not destination.exists():
            request = urllib.request.Request(artifact['browser_download_url'], headers={'User-Agent': 'HonbakoRuntimeProbe/1'})
            with urllib.request.urlopen(request, timeout=90) as response, destination.open('wb') as output:
                for block in iter(lambda: response.read(1024 * 1024), b''):
                    output.write(block)
        value = hashlib.sha256(destination.read_bytes()).hexdigest()
        if artifact['digest'] != 'sha256:' + value:
            raise ValueError('Runtime artifact changed: ' + name)
        folder = root
        folder.mkdir(exist_ok=True)
        with zipfile.ZipFile(destination) as archive:
            for entry in archive.infolist():
                relative = Path(entry.filename)
                if relative.is_absolute() or '..' in relative.parts:
                    raise ValueError('Unsafe runtime archive entry')
            archive.extractall(folder)
        print('Verified:', name)


if __name__ == '__main__':
    main()
