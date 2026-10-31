#!/usr/bin/env python3
"""Build an explicit allowlisted deployment archive; never copy runtime secrets."""
import hashlib
import gzip
import json
from pathlib import Path
import tarfile

REPO=Path(__file__).resolve().parents[3]
TOOLS=REPO/'Tools/reviewer-fixtures'
OUT=REPO/'AppStore/review/build73/honbako-review-vm-bundle.tar.gz'


def main():
    files=[TOOLS/name for name in ['README.md','support.py','bootstrap.py','probe.py','probe-https.py','suwayomi_gateway.py']]
    files.extend(p for p in (TOOLS/'vm').glob('*') if p.is_file() and p.suffix in {'.md','.py','.sh','.json','.yaml','.conf'})
    files.append(REPO/'Aidoku/Core/Sources/BuiltIn/Suwayomi/SuwayomiSource.swift')
    files.extend(p for p in (TOOLS/'generated/libraries').rglob('*') if p.is_file() and p.suffix in {'.cbz','.png'})
    files.extend([REPO/'AppStore/review/build73/reviewer-fixtures.json',REPO/'AppStore/review/build73/reviewer-instructions-prepared.txt'])
    credentials=json.loads((TOOLS/'runtime/credentials.json').read_text())
    secret_values=[v['password'].encode() for account in credentials.values() for v in account.values()]
    entries=[]
    for path in sorted(set(files)):
        data=path.read_bytes()
        if any(value in data for value in secret_values):raise RuntimeError('Refusing to package a private credential')
        if path.is_symlink() or 'runtime' in path.relative_to(REPO).parts:raise RuntimeError('Refusing runtime or symlink content')
        entries.append({'path':str(path.relative_to(REPO)),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
    with OUT.open('wb') as output, gzip.GzipFile(fileobj=output,mode='wb',filename='',mtime=0) as compressed, tarfile.open(fileobj=compressed,mode='w') as archive:
        for entry in entries:
            path=REPO/entry['path'];info=archive.gettarinfo(str(path),arcname='honbako-review/'+entry['path'])
            info.uid=info.gid=0;info.uname=info.gname='root';info.mtime=1793318400
            with path.open('rb') as stream:archive.addfile(info,stream)
    with tarfile.open(OUT) as archive:
        assert len(archive.getnames())==len(entries)
        assert not any('/runtime/' in name or 'credentials.json' in name or name.endswith('.jar') for name in archive.getnames())
    manifest={'archive':OUT.name,'sha256':hashlib.sha256(OUT.read_bytes()).hexdigest(),'bytes':OUT.stat().st_size,'secret_scan_passed':True,'mac_runtime_included':False,'linux_runtime_downloads_verified_at_install':True,'cloud_resource_created':False,'public_access_created':False,'contents':entries}
    OUT.with_suffix(OUT.suffix+'.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({k:v for k,v in manifest.items() if k!='contents'}))

if __name__=='__main__':main()
