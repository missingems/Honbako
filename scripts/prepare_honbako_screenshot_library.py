#!/usr/bin/env python3
"""Prepare only the named disposable screenshot simulator with native original books.

Requires explicit --replace-disposable-app; never use a physical/user device.
The public app stays unmodified: this imports genuine local cover-art CBZs into
its actual library, alongside its five bundled guides. No third-party pages,
content-provider credentials, personal feature unlocks or UI mockups are used.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import sys
import time
import uuid
from urllib.parse import quote, unquote, urlparse

REPO = Path(__file__).resolve().parent.parent
ASSETS = REPO / 'AppStore/original-covers'
CONVERTER = REPO / 'scripts/honbako_make_gallery_local.py'
SIMCTL = '/Applications/Xcode 27.1 Public.app/Contents/Developer/usr/bin/simctl'
BUNDLE = 'com.missingems.honbaku'
DEVICES = {'iphone': '5BA61F93-11A7-4F62-9E6A-0A513C557E08', 'ipad': '2894F317-56AD-47E0-965E-62D57B74D995'}
DEVICE_NAMES = {'iphone': 'Honbako Capture iphone-large', 'ipad': 'Honbako Capture ipad'}
LOCALES = {'en-US': ('en', 'en_US'), 'ja': ('ja', 'ja_JP'), 'zh-Hans': ('zh-Hans', 'zh_CN'), 'zh-Hant': ('zh-Hant', 'zh_TW')}
EPOCH = 978307200

def require(value, message):
    if not value: raise RuntimeError(message)

def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def run(*args, check=True):
    value = subprocess.run([SIMCTL, *map(str,args)], capture_output=True, text=True)
    if check and value.returncode: raise RuntimeError(value.stderr.strip())
    return value

def seed_staging_rows(container):
    """Create only a bounded fixture in a fresh, stopped app; converter makes native local CBZ links."""
    specs = json.loads((ASSETS / 'manifest.json').read_text())['covers']
    require(len(specs) == 12 and all(sha256(ASSETS / s['file']) == s['sha256'] for s in specs), 'Original cover manifest validation failed')
    covers = container / 'Documents/ScreenshotOriginalCovers'
    shutil.copytree(ASSETS, covers, dirs_exist_ok=True)
    store = container / 'Library/Application Support/Aidoku.sqlite'
    backup = container / 'tmp/DarkGalleryStagingBackup.sqlite'
    backup.parent.mkdir(exist_ok=True)
    c = sqlite3.connect(store, timeout=5)
    c.row_factory = sqlite3.Row
    # Core Data's derived chapterCount triggers perform the actual SQL count
    # updates, then notify their in-memory context through these callbacks.
    # No managed-object context is alive while the capture app is stopped.
    # Keep all derived-count triggers intact; only their context notifications
    # are no-ops on this bounded fixture connection.
    for name in ['NSCoreDataDATriggerInsertUpdatedAffectedObjectValue', 'NSCoreDataDATriggerUpdatedAffectedObjectValue']:
        c.create_function(name, 5, lambda *args: 0)
    try:
        rows = c.execute('SELECT ZID,ZSOURCEID FROM ZMANGA').fetchall()
        require(len(rows) == 5 and {row['ZID'] for row in rows} == {'first-chapter','guide-find','guide-connect','guide-read','guide-japanese'} and all(row['ZSOURCEID'] == 'honbako.tutorial' for row in rows), 'Fresh app must contain exactly the five bundled original guides before fixture seeding')
        require(c.execute('SELECT count(*) FROM ZLIBRARYMANGA').fetchone()[0] == 5, 'Unexpected existing library data')
        require(c.execute('SELECT count(*) FROM ZCHAPTER').fetchone()[0] == 20, 'Bundled guide language chapters are not ready')
        with sqlite3.connect(backup) as target:
            c.backup(target)
        entities = {r['Z_NAME']: (r['Z_ENT'], r['Z_MAX'] or 0) for r in c.execute('SELECT * FROM Z_PRIMARYKEY')}
        expected_columns = {'ZMANGA': {'Z_PK','Z_ENT','Z_OPT','ZCHAPTERCOUNT','ZCHAPTERFLAGS','ZEDITEDKEYS','ZNEVERUPDATE','ZNSFW','ZSTATUS','ZVIEWER','ZLIBRARYOBJECT','ZAUTHOR','ZCOVER','ZDESC','ZID','ZLANGFILTER','ZSOURCEID','ZTITLE','ZTAGS'}, 'ZCHAPTER': {'Z_PK','Z_ENT','Z_OPT','ZLOCKED','ZSOURCEORDER','ZMANGA','ZCHAPTER','ZID','ZLANG','ZMANGAID','ZSOURCEID','ZTITLE'}, 'ZLIBRARYMANGA': {'Z_PK','Z_ENT','Z_OPT','ZMANGA','ZDATEADDED','ZLASTCHAPTER','ZLASTUPDATED','ZLASTUPDATEDCHAPTERS'}}
        for table, columns in expected_columns.items():
            require(columns <= {r[1] for r in c.execute(f'PRAGMA table_info({table})')}, f'Unsupported capture schema: {table}')
        empty_tags = c.execute("SELECT ZTAGS FROM ZMANGA WHERE ZSOURCEID='honbako.tutorial'").fetchone()[0]
        counters = {name: max(entities[name][1], c.execute(f'SELECT coalesce(max(Z_PK),0) FROM {table}').fetchone()[0]) for name, table in [('Manga','ZMANGA'),('Chapter','ZCHAPTER'),('LibraryManga','ZLIBRARYMANGA')]}
        now = time.time() - EPOCH
        c.execute('BEGIN IMMEDIATE')
        for index in range(50):
            spec = specs[index % len(specs)]
            volume = index // len(specs) + 1
            key = f'{index+1:08x}-0000-4000-8000-000000000000'
            chapter_key = str(uuid.uuid5(uuid.NAMESPACE_URL, 'honbako-original-cover-gallery/chapter/' + key))
            for name in counters: counters[name] += 1
            manga, chapter, library = counters['Manga'], counters['Chapter'], counters['LibraryManga']
            title = spec['title'].title() + ' — Art Collection ' + str(volume)
            c.execute('INSERT INTO ZMANGA (Z_PK,Z_ENT,Z_OPT,ZCHAPTERCOUNT,ZCHAPTERFLAGS,ZEDITEDKEYS,ZNEVERUPDATE,ZNSFW,ZSTATUS,ZVIEWER,ZLIBRARYOBJECT,ZAUTHOR,ZCOVER,ZDESC,ZID,ZLANGFILTER,ZSOURCEID,ZTITLE,ZTAGS) VALUES (?,?,1,1,0,0,1,0,2,2,?,?,?,?,?,\'en\',\'honbako.mangadex\',?,?)', (manga,entities['Manga'][0],library,'Honbako Originals',(covers/spec['file']).as_uri(),'An original one-page cover-art portfolio, not a full narrative manga.',key,title,empty_tags))
            c.execute('INSERT INTO ZCHAPTER (Z_PK,Z_ENT,Z_OPT,ZLOCKED,ZSOURCEORDER,ZMANGA,ZCHAPTER,ZID,ZLANG,ZMANGAID,ZSOURCEID,ZTITLE) VALUES (?,?,1,0,0,?,1,?,\'en\',?,\'honbako.mangadex\',\'Original Cover Art\')', (chapter,entities['Chapter'][0],manga,chapter_key,key))
            added = now - index - 1
            c.execute('INSERT INTO ZLIBRARYMANGA (Z_PK,Z_ENT,Z_OPT,ZMANGA,ZDATEADDED,ZLASTCHAPTER,ZLASTUPDATED,ZLASTUPDATEDCHAPTERS) VALUES (?,?,1,?,?,?,?,?)', (library,entities['LibraryManga'][0],manga,added,added,added,added))
        for name, maximum in counters.items(): c.execute('UPDATE Z_PRIMARYKEY SET Z_MAX=? WHERE Z_NAME=?', (maximum,name))
        require(c.execute('PRAGMA quick_check').fetchone()[0] == 'ok', 'Seed database validation failed')
        require(c.execute('SELECT count(*) FROM ZMANGA').fetchone()[0] == 55, 'Expected exactly 50 portfolios plus five original guides')
        require(c.execute('SELECT count(*) FROM ZLIBRARYMANGA').fetchone()[0] == 55, 'Missing library links')
        require(c.execute("SELECT count(*) FROM ZMANGA WHERE ZAUTHOR='Honbako Originals' AND ZCHAPTERCOUNT=1").fetchone()[0] == 50, 'Native derived chapter counts differ from the 50 real chapters')
        c.commit()
        c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    except Exception:
        c.rollback()
        raise
    finally:
        c.close()
    conversion = subprocess.run([sys.executable, str(CONVERTER), '--app-stopped', str(container), str(ASSETS)], check=True, capture_output=True, text=True)
    result = json.loads(conversion.stdout)
    require(result['readable_art_collection_books'] == 50 and result['tutorial_unchanged'], 'Native local gallery conversion failed')
    # Match the app's native portable image scheme. XCTest may relocate the
    # data container when it updates the installed target before a test run.
    with sqlite3.connect(store) as c:
        for name in ['NSCoreDataDATriggerInsertUpdatedAffectedObjectValue', 'NSCoreDataDATriggerUpdatedAffectedObjectValue']:
            c.create_function(name,5,lambda *args:0)
        rows=c.execute("SELECT Z_PK,ZCOVER FROM ZMANGA WHERE ZSOURCEID='local' AND ZAUTHOR='Honbako Originals'").fetchall()
        require(len(rows)==50,'Expected only the50 original portfolio covers')
        for pk,url in rows:
            absolute=Path(unquote(urlparse(url).path))
            relative=absolute.relative_to(container/'Documents')
            require(absolute.is_file(),'Original cover file is missing before portable conversion')
            c.execute('UPDATE ZMANGA SET ZCOVER=?,Z_OPT=Z_OPT+1 WHERE Z_PK=?',('aidoku-image:///'+quote(relative.as_posix()),pk))
        c.commit()
        c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        result['portable_cover_paths']=True
        require(c.execute("SELECT count(*) FROM ZMANGA WHERE ZSOURCEID='local' AND ZAUTHOR='Honbako Originals' AND ZFILEINFO IS NOT NULL").fetchone()[0] == 50, 'Not all gallery records are genuine local books')
        require(c.execute("SELECT count(*) FROM ZMANGA WHERE ZSOURCEID='honbako.mangadex'").fetchone()[0] == 0, 'Staging source records remain')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device', choices=DEVICES)
    parser.add_argument('locale', choices=LOCALES)
    parser.add_argument('--build', required=True)
    parser.add_argument('--app', type=Path, default=Path.home()/'Library/Developer/Xcode/DerivedData/Aidoku-Codex/Build/Products/Debug-iphonesimulator/Sumi.app')
    parser.add_argument('--replace-disposable-app', action='store_true', required=True)
    args = parser.parse_args()
    info = plistlib.loads((args.app/'Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == BUNDLE and str(info.get('CFBundleVersion')) == args.build, 'Built simulator app does not match requested build')
    require(info.get('HonbakoPersonalFeatures') == 'NO' and info.get('HonbakoImportEnglish50') == 'NO' and info.get('HonbakoExternalSources') == 'NO', 'Public flags must remain external/personal/bulk-import NO/NO/NO')
    udid = DEVICES[args.device]
    all_devices = json.loads(run('list','devices','available','--json').stdout)['devices']
    matching = [d for devices in all_devices.values() for d in devices if d['udid'] == udid]
    require(len(matching)==1 and matching[0]['name']==DEVICE_NAMES[args.device], 'Expected only the allowlisted disposable capture simulator')
    run('boot',udid,check=False); run('bootstatus',udid,'-b')
    run('terminate',udid,BUNDLE,check=False)
    run('uninstall',udid,BUNDLE,check=False)
    run('install',udid,args.app)
    run('ui',udid,'appearance','dark')
    require(run('ui',udid,'appearance').stdout.strip().lower()=='dark','Native appearance must be Dark')
    run('status_bar',udid,'override','--time','9:41','--dataNetwork','wifi','--wifiMode','active','--wifiBars','3','--batteryState','charged','--batteryLevel','100')
    language,region=LOCALES[args.locale]
    launch=['-AppleLanguages','('+language+')','-AppleLocale',region,'-Honbako.Welcome.CompletedVersion','2','-General.icloudSync','NO','-Honbako.Reader.ShowCoverDisplay','NO']
    run('launch',udid,BUNDLE,*launch)
    container=Path(run('get_app_container',udid,BUNDLE,'data').stdout.strip())
    store=container/'Library/Application Support/Aidoku.sqlite'
    deadline=time.monotonic()+45
    while time.monotonic()<deadline:
        if store.exists() and (store.parent/'Local.sqlite').exists():
            try:
                with sqlite3.connect(f'file:{store}?mode=ro',uri=True,timeout=1) as db:
                    ready=db.execute("SELECT count(*) FROM ZMANGA WHERE ZSOURCEID='honbako.tutorial'").fetchone()[0]==5 and db.execute("SELECT count(*) FROM ZCHAPTER WHERE ZSOURCEID='honbako.tutorial'").fetchone()[0]==20
                if ready: break
            except sqlite3.Error: pass
        time.sleep(.1)
    else: raise RuntimeError('Bundled original guide initialization timed out')
    run('terminate',udid,BUNDLE)
    gallery=seed_staging_rows(container)
    record={'device':args.device,'deviceName':matching[0]['name'],'udid':udid,'locale':args.locale,'build':args.build,'configuration':'Debug simulator','publicFlags':{'HONBAKO_EXTERNAL_SOURCES':'NO','HONBAKO_PERSONAL_FEATURES':'NO','HONBAKO_IMPORT_ENGLISH_50':'NO'},'appearance':'Dark','appInfoPlistSha256':sha256(args.app/'Info.plist'),'launchArguments':launch,'gallery':gallery,'bundledOriginalGuides':5,'preparedAt':time.time()}
    out=REPO/'AppStore/screenshot-captures'/('build'+args.build+'-dark')/args.locale/args.device
    out.mkdir(parents=True,exist_ok=True)
    (out/'preparation.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps({'prepared':True,'device':args.device,'locale':args.locale,'build':args.build,'portfolioCount':50,'originalGuides':5,'marker':str(out/'preparation.json')},indent=2))

if __name__=='__main__':
    try: main()
    except Exception as error:
        print('Screenshot preparation failed: '+str(error),file=sys.stderr)
        raise SystemExit(1)
