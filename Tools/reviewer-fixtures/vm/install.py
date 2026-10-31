#!/usr/bin/env python3
"""Dedicated VM installer. Never run on the developer Mac; no cloud APIs."""
import concurrent.futures
import grp
import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request

REPO=Path(sys.argv[1]).resolve()
TOOLS=REPO/'Tools/reviewer-fixtures'
BIN=Path('/opt/honbako-review-binaries')
CONTENT=Path('/srv/honbako-review')
SETUP=Path('/var/lib/honbako-review-setup')
ETC=Path('/etc/honbako-review')


def private(path,text,owner=None):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(text);path.chmod(0o600)
    if owner:os.chown(path,pwd.getpwnam(owner).pw_uid,grp.getgrnam(owner).gr_gid)


def fetch(item):
    name,asset=item;destination=BIN/asset['filename']
    def digest(path):
        h=hashlib.sha256()
        with path.open('rb') as stream:
            for data in iter(lambda:stream.read(1024*1024),b''):h.update(data)
        return h.hexdigest()
    if not destination.exists() or digest(destination)!=asset['sha256']:
        temporary=destination.with_suffix(destination.suffix+'.partial')
        request=urllib.request.Request(asset['url'],headers={'User-Agent':'Honbako-review-VM-installer'})
        try:
            with urllib.request.urlopen(request,timeout=60) as response,temporary.open('wb') as stream:shutil.copyfileobj(response,stream)
            if digest(temporary)!=asset['sha256']:raise RuntimeError('Upstream SHA256 mismatch: '+name)
            temporary.replace(destination)
        finally:temporary.unlink(missing_ok=True)
    destination.chmod(0o644)
    return name,destination


def unit(name,command,working,write_paths,memory='900M',environment=None):
    user='honbako-'+name
    env=''.join('Environment='+k+'='+v+'\n' for k,v in (environment or {}).items())
    text='''[Unit]
Description=Honbako original review fixture '''+name+'''
After=network.target
[Service]
Type=simple
User='''+user+'''
Group='''+user+'''
WorkingDirectory='''+str(working)+'''
'''+env+'''ExecStart='''+command+'''
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
IPAddressDeny=any
IPAddressAllow=localhost
UMask=0077
ReadWritePaths='''+' '.join(str(v) for v in write_paths)+'''
MemoryMax='''+memory+'''
CPUQuota=150%
TasksMax=128
[Install]
WantedBy=multi-user.target
'''
    Path('/etc/systemd/system/honbako-'+name+'.service').write_text(text)


def main():
    if os.geteuid()!=0 or platform.system()!='Linux':raise SystemExit('Dedicated Linux review VM only')
    if ' ' in str(REPO):raise SystemExit('Extract bundle into a path without spaces, e.g. /opt/honbako-review')
    if os.sysconf('SC_PHYS_PAGES')*os.sysconf('SC_PAGE_SIZE')<3800*1024*1024:raise SystemExit('At least4GB VM RAM required')
    architecture={'aarch64':'arm64','arm64':'arm64','x86_64':'amd64'}.get(platform.machine())
    if not architecture:raise SystemExit('Use ARM64 or AMD64 Ubuntu24.04')
    for directory in [BIN,CONTENT,SETUP,ETC]:directory.mkdir(parents=True,exist_ok=True)
    BIN.chmod(0o755);CONTENT.chmod(0o755)
    SETUP.chmod(0o700);ETC.chmod(0o700)
    credentials_path=ETC/'private-accounts.json'
    if credentials_path.exists():credentials=json.loads(credentials_path.read_text())
    else:
        credentials={name:{'admin':{'username':'honbako-admin' if name=='kavita' else 'admin-review@honbako.invalid','email':'admin-review@honbako.invalid','password':secrets.token_urlsafe(24)+'aA1!'},'reviewer':{'username':'honbako-reviewer' if name=='kavita' else 'reviewer@honbako.invalid','email':'reviewer@honbako.invalid','password':secrets.token_urlsafe(24)+'aA1!'}} for name in ['komga','kavita','suwayomi']}
        private(credentials_path,json.dumps(credentials,indent=2)+'\n')
    releases=json.loads((TOOLS/'vm/releases-linux.json').read_text())
    selected={'komga':releases['komga'],'suwayomi':releases['suwayomi'],'kavita':releases['kavita'][architecture]}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:assets=dict(pool.map(fetch,selected.items()))
    kavita=BIN/'Kavita'
    if not (kavita/'Kavita').exists():
        with tarfile.open(assets['kavita']) as archive:
            for entry in archive.getmembers():
                if BIN.resolve() not in (BIN/entry.name).resolve().parents:raise RuntimeError('Invalid upstream archive path')
            archive.extractall(BIN)
        (kavita/'Kavita').chmod(0o755)
    assets['kavita'].unlink(missing_ok=True)
    for name in ['komga','kavita','suwayomi','gateway']:
        user='honbako-'+name
        try:pwd.getpwnam(user)
        except KeyError:subprocess.run(['useradd','--system','--user-group','--home-dir','/var/lib/'+user,'--shell','/usr/sbin/nologin',user],check=True)
        directory=Path('/var/lib/'+user);directory.mkdir(parents=True,exist_ok=True);directory.chmod(0o700)
        os.chown(directory,pwd.getpwnam(user).pw_uid,grp.getgrnam(user).gr_gid)
    source=TOOLS/'generated/libraries'
    for name in ['komga','kavita','suwayomi','mcp']:
        destination=CONTENT/name
        if destination.exists():
            existing=set(p.relative_to(destination).as_posix() for p in destination.rglob('*') if p.is_file())
            expected=set(p.relative_to(source/name).as_posix() for p in (source/name).rglob('*') if p.is_file())
            if existing-expected:raise RuntimeError('Unexpected content in fixture directory; refusing to alter it')
        shutil.copytree(source/name,destination,dirs_exist_ok=True)
        for file in destination.rglob('*'):
            file.chmod(0o755 if file.is_dir() else 0o644)
    komga=Path('/var/lib/honbako-komga')
    private(komga/'application.yml','server:\n  address: 127.0.0.1\n  port: 39101\nkomga:\n  config-dir: '+json.dumps(str(komga))+'\n','honbako-komga')
    kavita_state=Path('/var/lib/honbako-kavita')
    for name in ['config','cache','logs','backups','temp','wwwroot']:
        target=kavita_state/name;target.mkdir(exist_ok=True);os.chown(target,pwd.getpwnam('honbako-kavita').pw_uid,grp.getgrnam('honbako-kavita').gr_gid)
        original=kavita/name
        if original.is_dir() and not original.is_symlink():
            shutil.copytree(original,target,dirs_exist_ok=True);shutil.rmtree(original)
        if not original.exists():original.symlink_to(target,target_is_directory=True)
    # The official first-run migration otherwise downloads templates at runtime.
    # Pre-seed the pinned official assets while root setup has Internet access;
    # provider service networking remains loopback-only.
    templates=kavita_state/'config/templates'
    templates.mkdir(parents=True,exist_ok=True)
    for name,asset in releases['kavita_email_templates']['assets'].items():
        _,download=fetch(('kavita-email-'+name,asset))
        target=templates/asset['filename']
        if not target.exists():shutil.copyfile(download,target)
    settings=kavita_state/'config/appsettings.json'
    if not settings.exists():private(settings,json.dumps({'TokenKey':secrets.token_urlsafe(64),'Port':39102,'IpAddresses':'127.0.0.1','BaseUrl':'/','Cache':10}),'honbako-kavita')
    subprocess.run(['chown','-R','honbako-kavita:honbako-kavita',str(kavita_state)],check=True)
    suwayomi=Path('/var/lib/honbako-suwayomi')
    config={'server.ip':'127.0.0.1','server.port':39103,'server.authMode':'UI_LOGIN','server.authUsername':credentials['suwayomi']['admin']['username'],'server.authPassword':credentials['suwayomi']['admin']['password'],'server.localSourcePath':str(CONTENT/'suwayomi'),'server.webUIEnabled':False,'server.initialOpenInBrowserEnabled':False,'server.systemTrayEnabled':False,'server.kcefEnabled':False,'server.extensionStores':[],'server.backupInterval':0,'server.webUIUpdateCheckInterval':0}
    private(suwayomi/'server.conf','\n'.join(k+' = '+json.dumps(v) for k,v in config.items())+'\n','honbako-suwayomi')
    unit('komga','/usr/bin/java -Xms32m -Xmx512m -XX:ActiveProcessorCount=2 -jar '+str(assets['komga'])+' --komga.config-dir='+str(komga)+' --server.address=127.0.0.1 --server.port=39101',komga,[komga])
    unit('kavita',str(kavita/'Kavita'),kavita,[kavita_state],'1100M',{'DOTNET_PROCESSOR_COUNT':'2'})
    unit('suwayomi','/usr/bin/java -Xms32m -Xmx512m -XX:ActiveProcessorCount=2 -Djava.awt.headless=true -Dsuwayomi.tachidesk.config.server.rootDir='+str(suwayomi)+' -jar '+str(assets['suwayomi']),suwayomi,[suwayomi])
    subprocess.run(['systemctl','daemon-reload'],check=True)
    subprocess.run(['systemctl','enable','--now','honbako-komga','honbako-kavita','honbako-suwayomi'],check=True)
    for port in [39101,39102,39103]:
        import socket
        for attempt in range(360):
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=1):break
            except OSError:time.sleep(.5)
        else:raise RuntimeError('Provider not ready on fixture port'+str(port))
    env=os.environ.copy();env.update({'HONBAKO_REVIEW_RUNTIME':str(SETUP),'HONBAKO_REVIEW_CREDENTIALS_FILE':str(credentials_path),'HONBAKO_REVIEW_LIBRARY_ROOT':str(CONTENT)})
    subprocess.run(['/usr/bin/python3',str(TOOLS/'bootstrap.py')],env=env,check=True)
    gateway=Path('/var/lib/honbako-gateway')
    private(gateway/'credentials.json',json.dumps({'suwayomi':credentials['suwayomi']},indent=2),'honbako-gateway')
    shutil.copyfile(SETUP/'suwayomi-fixture.json',gateway/'suwayomi-fixture.json');os.chown(gateway/'suwayomi-fixture.json',pwd.getpwnam('honbako-gateway').pw_uid,grp.getgrnam('honbako-gateway').gr_gid)
    unit('gateway','/usr/bin/python3 '+str(TOOLS/'suwayomi_gateway.py')+' --runtime '+str(gateway),gateway,[gateway],'128M',{'HONBAKO_REVIEW_RUNTIME':str(gateway),'HONBAKO_REVIEW_CREDENTIALS_FILE':str(gateway/'credentials.json')})
    subprocess.run(['systemctl','daemon-reload'],check=True);subprocess.run(['systemctl','enable','--now','honbako-gateway'],check=True)
    # No public proxy is enabled here. DNS/TLS/public activation is a separate reviewed step.
    print(json.dumps({'local_services_installed':True,'architecture':architecture,'public_proxy_activated':False,'secrets_printed':False}))

if __name__=='__main__':main()
