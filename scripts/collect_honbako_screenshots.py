#!/usr/bin/env python3
"""Export actual successful UI-test JPEGs and record verified capture provenance."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent.parent
LOCALES = ['en-US', 'ja', 'zh-Hans', 'zh-Hant']
STATES = ['01-library', '02-reader', '03-chapters']
XCRUN = '/usr/bin/xcrun'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def command(*args):
    value = subprocess.run([XCRUN, 'xcresulttool', *map(str,args)], check=True, capture_output=True, text=True)
    return value.stdout

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--result', type=Path, required=True)
    parser.add_argument('--device', choices=['iphone','ipad'], required=True)
    parser.add_argument('--locale', choices=LOCALES, required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--state', choices=STATES, action='append', help='Collect only the named genuine native state(s)')
    args = parser.parse_args()
    output = ROOT/'AppStore/screenshot-captures'/('build'+args.build+'-dark')
    folder = output/args.locale/args.device
    preparation = json.loads((folder/'preparation.json').read_text())
    assert preparation['build'] == args.build and preparation['locale'] == args.locale and preparation['device'] == args.device
    assert preparation['appearance'] == 'Dark' and preparation['gallery']['readable_art_collection_books'] == 50
    assert preparation['publicFlags'] == {'HONBAKO_EXTERNAL_SOURCES':'NO','HONBAKO_PERSONAL_FEATURES':'NO','HONBAKO_IMPORT_ENGLISH_50':'NO'}
    summary = json.loads(command('get','test-results','summary','--path',args.result))
    assert summary.get('result') == 'Passed' and summary.get('passedTests',0) > 0 and summary.get('failedTests', 0) == 0 and not summary.get('testFailures'), 'Only successful test runs may become submission captures'
    captures = []
    with tempfile.TemporaryDirectory(prefix='honbako-screenshot-export-') as temporary:
        export = Path(temporary)
        command('export','attachments','--path',args.result,'--output-path',export)
        manifest = json.loads((export/'manifest.json').read_text())
        attachments = [a for test in manifest for a in test.get('attachments',[])]
        for state in args.state or STATES:
            matching = [a for a in attachments if a['suggestedHumanReadableName'].startswith(args.locale+'-'+state+'_') and not a.get('isAssociatedWithFailure')]
            assert len(matching) == 1, f'Expected exactly one actual {args.locale}/{state} capture; found {len(matching)}'
            attachment = matching[0]
            source = export/attachment['exportedFileName']
            with Image.open(source) as image:
                expected = (1320,2868) if args.device == 'iphone' else (2064,2752)
                assert image.getexif().get(274, 1) == 1, 'Native capture must have normalized upright pixels'
                assert ImageOps.exif_transpose(image).size == image.size
                assert image.size == expected, f'Native capture dimensions {image.size} do not match {expected}'
                assert image.format == 'JPEG', 'Preserve the genuine test JPEG without resampling'
            destination = folder/(state+'.jpg')
            shutil.copyfile(source,destination)
            captures.append({'file':str(destination.relative_to(ROOT/'AppStore')),'sha256':digest(destination),'width':expected[0],'height':expected[1],'locale':args.locale,'device':args.device,'state':state,'build':args.build,'appearance':'Dark','capturedAt':attachment['timestamp'],'captureMethod':'Native XCUIApplication.screenshot JPEG attachment; unchanged native pixels','resultBundle':args.result.name,'preparation':str((folder/'preparation.json').relative_to(ROOT/'AppStore'))})
    (folder/'capture-provenance.json').write_text(json.dumps({'preparation':preparation,'captures':captures},ensure_ascii=False,indent=2)+'\n')
    all_captures=[]
    for locale in LOCALES:
        for device in ['iphone','ipad']:
            record=output/locale/device/'capture-provenance.json'
            if record.exists():
                values=json.loads(record.read_text())['captures']
                for value in values:
                    path=ROOT/'AppStore'/value['file']
                    assert value['build']==args.build and digest(path)==value['sha256']
                all_captures.extend(values)
    report={'status':'verified' if len(all_captures)==24 else 'partial','build':args.build,'configuration':'Debug simulator','appearance':'Dark','publicFlags':preparation['publicFlags'],'nativeCaptureCount':len(all_captures),'locales':LOCALES,'devices':['iphone','ipad'],'gallery':'50 genuine local one-page original-art portfolios plus five native bundled original guides; not 50 narrative titles','image_generation_used_for_this_refresh':False,'ui_fabricated':False,'captures':all_captures,'verifiedAt':time.time()}
    (output/'capture-manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'collected':len(captures),'total':len(all_captures),'status':report['status'],'folder':str(folder)},indent=2))

if __name__=='__main__': main()
