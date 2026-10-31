#!/usr/bin/env python3
"""Fetch exact upstream release assets; verify before any execution."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parent
RELEASES = json.loads((ROOT / 'releases.json').read_text())
RUNTIME = ROOT / 'runtime'
RUNTIME.mkdir(mode=0o700, exist_ok=True)

def fetch(item):
    name, asset = item
    destination = RUNTIME / asset['filename']
    def digest(path):
        h = hashlib.sha256()
        with path.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                h.update(chunk)
        return h.hexdigest()
    if destination.exists() and digest(destination) == asset['sha256']:
        return {'provider': name, 'version': asset['version'], 'sha256_verified': True, 'cached': True}
    temporary = destination.with_suffix(destination.suffix + '.partial')
    try:
        request = urllib.request.Request(asset['url'], headers={'User-Agent': 'Honbako-review-fixture'})
        with urllib.request.urlopen(request, timeout=60) as response, temporary.open('wb') as out:
            for chunk in iter(lambda: response.read(1024 * 1024), b''):
                out.write(chunk)
        if digest(temporary) != asset['sha256']:
            raise RuntimeError(name + ': upstream SHA256 mismatch')
        temporary.replace(destination)
        return {'provider': name, 'version': asset['version'], 'sha256_verified': True, 'cached': False}
    finally:
        temporary.unlink(missing_ok=True)

if __name__ == '__main__':
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for result in pool.map(fetch, [(k, v) for k, v in RELEASES.items() if isinstance(v, dict)]):
            print(json.dumps(result), flush=True)
