#!/usr/bin/env python3
"""External strict-HTTPS review probe; dedicated VM reader accounts only.

No owner library, administrator account, MCP grant or receipt is read.
"""
import importlib.util
import base64
import json
import os
from pathlib import Path
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT=Path(__file__).resolve().parent
ACCOUNTS=ROOT/'runtime/vm-reader-accounts.json'
FIXTURES=ROOT/'runtime/vm'
raw=json.loads(ACCOUNTS.read_text())
assert set(raw)=={'komga','kavita','suwayomi'}
os.environ['HONBAKO_REVIEW_CREDENTIALS_FILE']=str(ACCOUNTS)
os.environ['HONBAKO_REVIEW_RUNTIME']=str(FIXTURES)
import support
support.CREDENTIALS={name:{'reviewer':data} for name,data in raw.items()}
PORTS={39101:'komga',39102:'kavita',39104:'suwayomi'}
context=ssl.create_default_context()

class SameOriginRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,request,fp,code,msg,headers,newurl):
        old=urllib.parse.urlsplit(request.full_url);new=urllib.parse.urlsplit(newurl)
        if (new.scheme,new.netloc)!=(old.scheme,old.netloc):
            raise RuntimeError('Cross-origin or non-HTTPS redirect rejected')
        return super().redirect_request(request,fp,code,msg,headers,newurl)

opener=urllib.request.build_opener(urllib.request.HTTPSHandler(context=context),SameOriginRedirect())
def https(port,path,body=None,headers=None,method=None):
    if port not in PORTS:raise ValueError('Private admin backend is never an external target')
    if not path.startswith('/') or path.startswith('//'):raise ValueError('Invalid route')
    base=raw[PORTS[port]]['base_url']
    expected='https://'+PORTS[port]+'-review.honbako.xyz'
    assert base==expected
    request=urllib.request.Request(base+path,data=json.dumps(body).encode() if body is not None else None,headers={'Content-Type':'application/json','User-Agent':'HonbakoReviewHTTPSProbe/1',**(headers or {})},method=method)
    try:
        with opener.open(request,timeout=30) as response:
            data=response.read(8*1024*1024+1)
            assert len(data)<=8*1024*1024
            return response.status,response.headers.get('Content-Type',''),data
    except urllib.error.HTTPError as error:
        return error.code,error.headers.get('Content-Type',''),error.read(32*1024)

support.http=https
spec=importlib.util.spec_from_file_location('honbako_vm_https_probes',ROOT/'probe.py')
probe=importlib.util.module_from_spec(spec);spec.loader.exec_module(probe)
report={'strict_tls':True,'public_deployment':True,'credential_values_in_proof':False,'providers':{}}
manifest=json.loads((ROOT.parents[1]/'AppStore/review/build73/reviewer-fixtures.json').read_text())
expected={b['title']:sorted(b['asset_sha256'].values()) for b in manifest['books']}
for name,port,run in [('komga',39101,probe.komga),('kavita',39102,probe.kavita),('suwayomi',39104,probe.suwayomi)]:
    # Unauthenticated callers must not receive the catalog.
    route='/api/v1/series/list' if name=='komga' else '/api/Series/v2' if name=='kavita' else '/api/graphql'
    unauth=https(port,route,{} if name!='suwayomi' else {'query':'{__typename}'},method='POST')[0]
    assert unauth in {401,403},(name,unauth)
    if name=='kavita':
        wrong=https(port,'/api/Account/login',{'username':raw[name]['username'],'password':'incorrect-reviewer-probe-value','apiKey':''})[0]
    else:
        invalid='Basic '+base64.b64encode((raw[name]['username']+':incorrect-reviewer-probe-value').encode()).decode()
        wrong=https(port,'/' if name=='suwayomi' else '/api/v2/users/me',headers={'Authorization':invalid})[0]
    assert wrong in {401,403},(name,wrong)
    result=run()
    books=result['books'] if name=='komga' else [result]
    for book in books:assert sorted(page['sha256'] for page in book['page_images'])==expected[book['title']]
    report['providers'][name]={'passed':True,'unauthenticated_catalog_denied':unauth,'wrong_password_denied':wrong,'exact_original_page_hashes':True,**result}
    print(json.dumps({'provider':name,'strict_https_passed':True,'original_page_hashes_match':True}),flush=True)
out=ROOT.parents[1]/'AppStore/review/build73/reviewer-vm-https-preflight.json'
out.write_text(json.dumps(report,indent=2)+'\n')
