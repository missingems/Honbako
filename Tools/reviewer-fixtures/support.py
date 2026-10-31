"""Private local fixture transport. Never prints authentication material."""
import base64
import json
import os
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent
RUNTIME = Path(os.environ.get('HONBAKO_REVIEW_RUNTIME', str(ROOT / 'runtime'))).resolve()
CREDENTIALS_PATH = Path(os.environ.get('HONBAKO_REVIEW_CREDENTIALS_FILE', str(RUNTIME / 'credentials.json'))).resolve()
LIBRARIES = Path(os.environ.get('HONBAKO_REVIEW_LIBRARY_ROOT', str(ROOT / 'generated/libraries'))).resolve()
CREDENTIALS = json.loads(CREDENTIALS_PATH.read_text())
_token = None
_token_until = 0

def http(port, path, body=None, headers=None, method=None):
    if port not in {39101,39102,39103,39104}: raise ValueError('Not a fixture port')
    if not path.startswith('/') or path.startswith('//'): raise ValueError('Not a fixture route')
    req = urllib.request.Request('http://127.0.0.1:'+str(port)+path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Content-Type':'application/json',**(headers or {})}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            raw=response.read(8*1024*1024+1)
            if len(raw)>8*1024*1024: raise RuntimeError('Fixture response too large')
            return response.status, response.headers.get('Content-Type',''), raw
    except urllib.error.HTTPError as error:
        return error.code,error.headers.get('Content-Type',''),error.read(32*1024)

def decode(result):
    status,content_type,raw=result
    if status>=400: raise RuntimeError('Fixture backend HTTP '+str(status))
    return json.loads(raw) if raw else None

def basic(provider, user='reviewer'):
    c=CREDENTIALS[provider][user]
    return {'Authorization':'Basic '+base64.b64encode((c['username']+':'+c['password']).encode()).decode()}

def suwayomi_token():
    global _token,_token_until
    if _token is not None and time.monotonic()<_token_until:return _token
    c=CREDENTIALS['suwayomi']['admin']
    payload={'query':'mutation Login($username:String!,$password:String!){login(input:{username:$username,password:$password}){accessToken}}','variables':c}
    result=decode(http(39103,'/api/graphql',payload))
    _token=result.get('data',{}).get('login',{}).get('accessToken')
    if not _token:raise RuntimeError('Fixture backend authentication failed')
    _token_until=time.monotonic()+240
    return _token

def suwayomi_http(path,body=None):
    return http(39103,path,body,{'Authorization':'Bearer '+suwayomi_token()})

def suwayomi(query,variables=None):
    result=decode(suwayomi_http('/api/graphql',{'query':query,'variables':variables or {}}))
    if result.get('errors'):raise RuntimeError('Fixture GraphQL error: '+str(result['errors'][0].get('message','')).splitlines()[0][:160])
    return result['data']
