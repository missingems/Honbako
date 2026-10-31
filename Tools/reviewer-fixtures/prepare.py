#!/usr/bin/env python3
"""Prepare isolated provider state and CBZs from unchanged original Honbako assets."""
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import tarfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
RUNTIME = ROOT / 'runtime'
GENERATED = ROOT / 'generated'
ASSETS = GENERATED / 'assets'
BOOKS = [
    ('komga', 'guide-connect', 'Your Collections'),
    ('kavita', 'guide-read', 'Read Your Way'),
    ('suwayomi', 'guide-find', 'Search & Delete'),
    ('mcp', 'bookshop', 'The Bookshop Between Pages')
]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_private(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.write_text(value)
    path.chmod(0o600)

def main():
    RUNTIME.mkdir(mode=0o700, parents=True, exist_ok=True)
    credentials_path = RUNTIME / 'credentials.json'
    if not credentials_path.exists():
        credentials = {name: {'admin': {'username': 'admin-review@honbako.invalid', 'password': secrets.token_urlsafe(24) + 'aA1!'},
                              'reviewer': {'username': 'reviewer@honbako.invalid', 'password': secrets.token_urlsafe(24) + 'aA1!'}}
                       for name in ['komga', 'kavita', 'suwayomi']}
        write_private(credentials_path, json.dumps(credentials, indent=2) + '\n')
    credentials = json.loads(credentials_path.read_text())
    manifest = {'original_content_only': True, 'renderer': 'Aidoku/Features/Bookshelf/Services/HonbakoGuideRenderer.swift',
                'renderer_sha256': sha(REPO / 'Aidoku/Features/Bookshelf/Services/HonbakoGuideRenderer.swift'),
                'text_sha256': sha(REPO / 'Aidoku/App/Resources/Localization/en.lproj/Localizable.strings'), 'books': []}
    for provider, identifier, title in BOOKS:
        source = REPO / 'site/originals/bookshop' if identifier == 'bookshop' else ASSETS / identifier
        count = 6 if identifier == 'bookshop' else 4
        pages = [source / 'cover.png'] + [source / ('page-%d.png' % i) for i in range(1, count + 1)]
        if not all(p.exists() for p in pages):
            raise RuntimeError('Export existing native guide artwork before packaging: ' + identifier)
        directory = GENERATED / 'libraries' / provider / title
        directory.mkdir(parents=True, exist_ok=True)
        destination = directory / (title + ' v01 c001.cbz')
        info = ET.Element('ComicInfo')
        for key, value in [('Title', title), ('Series', title), ('Number', '1'), ('Volume', '1'), ('Count', '1'),
                           ('Writer', 'Honbako'), ('LanguageISO', 'en'), ('Manga', 'YesAndRightToLeft'),
                           ('Summary', 'Original first-party Honbako review sample. No third-party manga.'), ('PageCount', str(len(pages)))]:
            ET.SubElement(info, key).text = value
        ET.SubElement(ET.SubElement(info, 'Pages'), 'Page', {'Image': '0', 'Type': 'FrontCover'})
        with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            for i, page in enumerate(pages): archive.write(page, '%03d.png' % i)
            archive.writestr('ComicInfo.xml', ET.tostring(info, encoding='utf-8', xml_declaration=True))
        # Suwayomi also uses a manga-level thumbnail beside the chapter archive.
        if provider == 'suwayomi': shutil.copyfile(pages[0], directory / 'cover.png')
        manifest['books'].append({'provider': provider, 'identifier': identifier, 'title': title, 'chapters': 1,
                                  'pages_including_cover': len(pages), 'cbz': str(destination.relative_to(REPO)),
                                  'sha256': sha(destination), 'asset_sha256': {p.name: sha(p) for p in pages}})
    kavita = RUNTIME / 'Kavita'
    if not (kavita / 'Kavita').exists():
        with tarfile.open(RUNTIME / 'kavita-osx-arm64.tar.gz') as archive:
            for member in archive.getmembers():
                target = (RUNTIME / member.name).resolve()
                if RUNTIME.resolve() not in target.parents: raise RuntimeError('Unexpected archive path')
            archive.extractall(RUNTIME)
    kavita_config = {'TokenKey': secrets.token_urlsafe(64), 'Port': 39102, 'IpAddresses': '127.0.0.1', 'BaseUrl': '/', 'Cache': 10}
    config_path = kavita / 'config/appsettings.json'
    if not config_path.exists(): write_private(config_path, json.dumps(kavita_config, indent=2))
    for name in ['komga', 'suwayomi']:
        (RUNTIME / name).mkdir(mode=0o700, exist_ok=True)
    komga = RUNTIME / 'komga'
    write_private(komga / 'application.yml', 'server:\n  address: 127.0.0.1\n  port: 39101\nkomga:\n  config-dir: ' + json.dumps(str(komga)) + '\n  libraries-scan-startup: false\n')
    suwayomi = RUNTIME / 'suwayomi'
    settings = {'server.ip': '127.0.0.1', 'server.port': 39103, 'server.authMode': 'UI_LOGIN',
                'server.authUsername': credentials['suwayomi']['admin']['username'], 'server.authPassword': credentials['suwayomi']['admin']['password'],
                'server.localSourcePath': str(GENERATED / 'libraries/suwayomi'), 'server.webUIEnabled': False,
                'server.initialOpenInBrowserEnabled': False, 'server.systemTrayEnabled': False, 'server.kcefEnabled': False,
                'server.webUIUpdateCheckInterval': 0, 'server.extensionStores': [], 'server.backupInterval': 0}
    write_private(suwayomi / 'server.conf', '\n'.join(key + ' = ' + json.dumps(value) for key, value in settings.items()) + '\n')
    report = REPO / 'AppStore/review/build73/reviewer-fixtures.json'
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(manifest, indent=2) + '\n')
    # The verified archive is expendable after extraction; executable runtime is retained for review preparation.
    (RUNTIME / 'kavita-osx-arm64.tar.gz').unlink(missing_ok=True)
    print(json.dumps({'books_prepared': len(BOOKS), 'distinct_titles': len(set(b[2] for b in BOOKS)), 'private_credentials_printed': False, 'public_deployment': False}))

if __name__ == '__main__': main()
