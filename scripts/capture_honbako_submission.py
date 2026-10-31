#!/usr/bin/env python3
"""Capture 24 native UI states and render 36 required/optional listing images.

Run only after the release coordinator has finished all shared DerivedData builds.
This runner never builds, archives, uploads or changes a physical device. Preparation
replaces only the two explicitly allowlisted disposable simulator installations.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
DEVICES = {'iphone': '5BA61F93-11A7-4F62-9E6A-0A513C557E08', 'ipad': '2894F317-56AD-47E0-965E-62D57B74D995'}
METHODS = {'en-US': 'testEnglish', 'ja': 'testJapanese', 'zh-Hans': 'testSimplifiedChinese', 'zh-Hant': 'testTraditionalChinese'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', required=True)
    parser.add_argument('--xctestrun', type=Path, required=True, help='Exact existing public-build UI-test manifest')
    parser.add_argument('--app', type=Path, default=Path.home()/'Library/Developer/Xcode/DerivedData/Aidoku-Codex/Build/Products/Debug-iphonesimulator/Sumi.app')
    parser.add_argument('--run-id', required=True, help='Unique result directory label, e.g. native-20261031-0015')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9._-]{1,80}', args.run_id): parser.error('Use a short filesystem-safe run ID')
    if not args.xctestrun.is_file(): parser.error('Existing UI-test manifest is required; this runner never builds')
    manifest = plistlib.loads(args.xctestrun.read_bytes())
    targets = []
    for configuration in manifest.get('TestConfigurations', [manifest]):
        values = configuration.get('TestTargets')
        if values is None:
            values = [value for key, value in configuration.items() if not key.startswith('__') and isinstance(value, dict)]
        targets.extend(values)
    candidates = [target for target in targets if target.get('BlueprintName') == 'SumiUITests']
    assert candidates, 'Select the native SumiUITests manifest'
    for target in candidates:
        actual = Path(target['UITargetAppPath'].replace('__TESTROOT__', str(args.xctestrun.resolve().parent))).resolve()
        assert actual == args.app.resolve(), 'The test manifest must install the exact public app being prepared'
    info = plistlib.loads((args.app/'Info.plist').read_bytes())
    assert info.get('CFBundleIdentifier') == 'com.missingems.honbaku'
    assert str(info.get('CFBundleVersion')) == args.build
    assert info.get('CFBundleShortVersionString') == '0.1.0', 'Capture the public App Store version'
    assert all(info.get(key) == 'NO' for key in ['HonbakoExternalSources', 'HonbakoPersonalFeatures', 'HonbakoImportEnglish50']), 'Capture only the normal public build'
    results = ROOT/'AppStore/review'/('build'+args.build)/args.run_id
    results.mkdir(parents=True, exist_ok=False)
    env = {**os.environ, 'DEVELOPER_DIR': '/Applications/Xcode 27.1 Public.app/Contents/Developer'}
    completed = []
    for device, udid in DEVICES.items():
        for locale, method in METHODS.items():
            subprocess.run([sys.executable, str(ROOT/'scripts/prepare_honbako_screenshot_library.py'), device, locale,
                '--build', args.build, '--app', str(args.app), '--replace-disposable-app'], cwd=ROOT, env=env, check=True)
            result = results/(device+'-'+locale+'.xcresult')
            log = results/(device+'-'+locale+'.log')
            command = ['/usr/bin/xcrun', 'xcodebuild', 'test-without-building', '-xctestrun', str(args.xctestrun.resolve()),
                '-destination', 'platform=iOS Simulator,id='+udid, '-parallel-testing-enabled', 'NO',
                '-only-testing:SumiUITests/HonbakoSubmissionScreenshotTests/'+method,
                '-collect-test-diagnostics', 'never', '-resultBundlePath', str(result)]
            with log.open('w') as output:
                run = subprocess.run(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT)
            if run.returncode:
                print(log.read_text()[-6000:], file=sys.stderr)
                raise RuntimeError('Native capture failed; inspect '+str(log))
            subprocess.run([sys.executable, str(ROOT/'scripts/collect_honbako_screenshots.py'), '--result', str(result),
                '--device', device, '--locale', locale, '--build', args.build], cwd=ROOT, env=env, check=True)
            completed.append({'device': device, 'locale': locale, 'test': method, 'result': str(result.relative_to(ROOT))})
            (results/'runs.json').write_text(json.dumps(completed, indent=2)+'\n')
    subprocess.run([sys.executable, str(ROOT/'scripts/design_honbako_store_screenshots.py'), '--build', args.build], cwd=ROOT, env=env, check=True)
    print(json.dumps({'nativeTestsPassed':len(completed), 'listingImages':36, 'build':args.build,
        'iPhoneNativePixels':[1320,2868], 'requiredMediumCanvasPixels':[1206,2622], 'iPadPixels':[2064,2752], 'uploaded':False,
        'nextStep':'Visually inspect both contact sheets and verify hashes before App Store upload.'}, indent=2))

if __name__ == '__main__':
    try: main()
    except Exception as error:
        print('Submission capture stopped: '+str(error), file=sys.stderr)
        raise SystemExit(1)
