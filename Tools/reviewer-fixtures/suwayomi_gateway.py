#!/usr/bin/env python3
"""Read-only review gateway in front of the real isolated Suwayomi backend.

The caller's GraphQL text is NEVER forwarded. Only exact app query templates
select trusted server-generated operations with bounded fixture IDs/variables.
Upstream administrator credentials/tokens never leave this process.
"""
import argparse
import base64
import hashlib
import http.server
import json
from pathlib import Path
import re
import secrets
import socketserver
import textwrap
import threading
import time
import urllib.parse
from support import ROOT, RUNTIME, CREDENTIALS, suwayomi, suwayomi_http

REPO = ROOT.parents[1]
STATE = json.loads((RUNTIME/'suwayomi-fixture.json').read_text())
ALLOWED = {'SearchManga','GetMangaUpdate','GetPages','GetCategories','GetMangaTags'}

def canonical(query):
    return re.sub(r'\s+', '', query)

def app_queries():
    source=(REPO/'Aidoku/Core/Sources/BuiltIn/Suwayomi/SuwayomiSource.swift').read_text()
    result={}
    for match in re.finditer(r'let query = """\n(.*?)\n\s*"""', source, re.S):
        query=textwrap.dedent(match.group(1))
        operation=re.match(r'\s*(?:query|mutation)\s+(\w+)', query)
        if operation and operation[1] in ALLOWED:
            result[canonical(query)]=(operation[1],query)
    if len(result)!=len(ALLOWED):raise RuntimeError('App query templates changed; review gateway requires revalidation')
    return result

QUERIES=app_queries()
CRED=CREDENTIALS['suwayomi']['reviewer']
EXPECTED='Basic '+base64.b64encode((CRED['username']+':'+CRED['password']).encode()).decode()
PAGES=set(STATE['pages'])
THUMB='/api/v1/manga/'+str(STATE['manga_id'])+'/thumbnail'
WINDOW=[]
LOCK=threading.Lock()


def bounded_filter(value, depth=0):
    if depth>6:raise ValueError('Filter too deep')
    if value is None or type(value) in {bool,int}:return value
    if isinstance(value,str) and len(value)<=200:return value
    if isinstance(value,list) and len(value)<=8:return [bounded_filter(v,depth+1) for v in value]
    keys={'and','or','categoryId','title','url','artist','author','description','genre','status','equalTo','isNull','includesInsensitive','notIncludesInsensitive','in','notEqualToAny'}
    if isinstance(value,dict) and len(value)<=12 and set(value)<=keys:return {k:bounded_filter(v,depth+1) for k,v in value.items()}
    raise ValueError('Unsupported filter')


def validated(operation, variables):
    if not isinstance(variables,dict):raise ValueError('Expected variables object')
    if operation=='GetMangaUpdate':
        if set(variables)!={'mangaId'} or type(variables['mangaId']) is not int or variables['mangaId']!=STATE['manga_id']:raise ValueError('Unknown manga')
        return variables
    if operation=='GetPages':
        if set(variables)!={'chapterId'} or type(variables['chapterId']) is not int or variables['chapterId'] not in STATE['chapters']:raise ValueError('Unknown chapter')
        return variables
    if operation=='SearchManga':
        if set(variables)-{'filter','orderBy','orderByType'}:raise ValueError('Unsupported variable')
        if variables.get('orderBy') not in {None,'ID','TITLE','IN_LIBRARY_AT','LAST_FETCHED_AT'}:raise ValueError('Unsupported sort')
        if variables.get('orderByType') not in {None,'ASC','DESC'}:raise ValueError('Unsupported direction')
        result=dict(variables)
        if 'filter' in result:result['filter']=bounded_filter(result['filter'])
        return result
    if operation=='GetCategories':
        if set(variables)-{'orderBy','orderByType'} or variables.get('orderBy') not in {None,'ORDER'} or variables.get('orderByType') not in {None,'ASC','DESC'}:raise ValueError('Unsupported category sort')
        return variables
    if variables:raise ValueError('Unexpected variables')
    return {}


def scrub_paths(value):
    if isinstance(value,list):return [scrub_paths(v) for v in value]
    if isinstance(value,dict):return {k:(None if k=='realUrl' and isinstance(v,str) and v.startswith('file:') else scrub_paths(v)) for k,v in value.items()}
    return value


class Gateway(http.server.BaseHTTPRequestHandler):
    server_version='HonbakoOriginalReview/1'
    def log_message(self,*args):pass
    def send(self,status,body=b'',content_type='application/json'):
        self.send_response(status)
        self.send_header('Content-Type',content_type)
        self.send_header('Cache-Control','private, no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Content-Security-Policy',"default-src 'none'")
        if status==401:self.send_header('WWW-Authenticate','Basic realm="Honbako Original Review"')
        self.send_header('Content-Length',str(len(body)));self.end_headers()
        if self.command!='HEAD':self.wfile.write(body)
    def authorized(self):
        if not secrets.compare_digest(self.headers.get('Authorization',''),EXPECTED):self.send(401,b'{"error":"reviewer authentication required"}');return False
        with LOCK:
            now=time.monotonic();WINDOW[:]=[v for v in WINDOW if v>now-60]
            if len(WINDOW)>=120:self.send(429,b'{"error":"retry later"}');return False
            WINDOW.append(now)
        return True
    def do_HEAD(self):self.do_GET()
    def do_GET(self):
        if not self.authorized():return
        if self.path=='/':
            self.send(200,b'{"provider":"Suwayomi","review_gateway":true,"scope":"original sample only"}');return
        if self.path not in PAGES and self.path!=THUMB:self.send(404);return
        try:
            status,content_type,body=suwayomi_http(self.path)
            if status!=200 or content_type.split(';')[0] not in {'image/png','image/jpeg','image/webp'}:raise RuntimeError('Image unavailable')
            self.send(200,body,content_type)
        except Exception:self.send(502,b'{"error":"original sample temporarily unavailable"}')
    def do_POST(self):
        if not self.authorized():return
        if self.path!='/api/graphql':self.send(404);return
        try:
            length=int(self.headers.get('Content-Length','0'))
            if not 0<length<=32768 or self.headers.get('Transfer-Encoding'):raise ValueError('Invalid request size')
            payload=json.loads(self.rfile.read(length))
            if not isinstance(payload,dict) or set(payload)-{'query','variables','operationName'}:raise ValueError('Unsupported request')
            query=payload.get('query')
            if not isinstance(query,str) or len(query)>16000:raise ValueError('Invalid query')
            approved=QUERIES.get(canonical(query))
            if not approved:raise ValueError('Operation not allowed')
            operation,trusted_query=approved
            if payload.get('operationName') not in {None,operation}:raise ValueError('Wrong operation')
            variables=validated(operation,payload.get('variables') or {})
            # Restrict catalog/tags to the one original sample even if an admin
            # later adds something else to this otherwise isolated backend.
            if operation in {'SearchManga','GetMangaTags'}:
                trusted_query=trusted_query.replace('condition: {inLibrary: true}', 'condition: {inLibrary: true, id: '+str(STATE['manga_id'])+'}')
            data=suwayomi(trusted_query,variables)
            if operation=='GetPages' and set(data.get('fetchChapterPages',{}).get('pages',[]))-PAGES:raise RuntimeError('Unexpected page route')
            self.send(200,json.dumps({'data':scrub_paths(data)},separators=(',',':')).encode())
        except (ValueError,TypeError,json.JSONDecodeError):self.send(403,b'{"error":"operation outside original review fixture"}')
        except Exception:self.send(502,b'{"error":"original sample temporarily unavailable"}')
    def do_PUT(self):self.send(405)
    def do_DELETE(self):self.send(405)
    def do_PATCH(self):self.send(405)

class Server(socketserver.ThreadingMixIn,http.server.HTTPServer):
    daemon_threads=True
    request_queue_size=8
    slots=threading.BoundedSemaphore(8)
    def process_request(self,request,address):
        if not self.slots.acquire(blocking=False):
            self.close_request(request)
            return
        try:super().process_request(request,address)
        except Exception:
            self.slots.release()
            raise
    def process_request_thread(self,request,address):
        try:super().process_request_thread(request,address)
        finally:self.slots.release()

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--runtime',required=True);args=parser.parse_args()
    if Path(args.runtime).resolve()!=RUNTIME:raise SystemExit('Wrong fixture runtime')
    Server(('127.0.0.1',39104),Gateway).serve_forever()
