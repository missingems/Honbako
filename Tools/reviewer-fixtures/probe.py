#!/usr/bin/env python3
"""Real provider protocol probes; only original fixture libraries and private accounts."""
import hashlib
import json
import os
from pathlib import Path
import re
import textwrap
from support import ROOT, RUNTIME, CREDENTIALS, http, decode, basic

REPO=ROOT.parents[1]

def image(result):
    status,mime,data=result
    assert status==200 and mime.split(';')[0] in {'image/png','image/jpeg','image/webp'}
    assert data.startswith((b'\x89PNG\r\n\x1a\n',b'\xff\xd8',b'RIFF'))
    return {'status':status,'mime':mime,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}

def komga():
    h=basic('komga')
    me=decode(http(39101,'/api/v2/users/me',headers=h));assert 'ADMIN' not in me['roles']
    series=decode(http(39101,'/api/v1/series/list',{},h))['content']
    assert {s['metadata']['title'] for s in series}=={'Your Collections','The Bookshop Between Pages'}
    books=[]
    for s in series:
        chapters=decode(http(39101,'/api/v1/series/'+s['id']+'/books?unpaged=true',headers=h))['content'];assert len(chapters)==1
        chapter=chapters[0];pages=decode(http(39101,'/api/v1/books/'+chapter['id']+'/pages',headers=h))
        checks=[image(http(39101,'/api/v1/books/'+chapter['id']+'/pages/'+str(i+1),headers=h)) for i in range(len(pages))]
        books.append({'title':s['metadata']['title'],'chapters':len(chapters),'page_images':checks})
    denied=http(39101,'/api/v1/libraries',{'name':'forbidden','root':'/not-a-fixture'},h)[0]
    assert denied in {401,403}
    return {'real_provider':True,'reader_roles':me['roles'],'books':books,'admin_operation_denied':denied}

def kavita():
    reviewer=CREDENTIALS['kavita']['reviewer']
    user=decode(http(39102,'/api/Account/login',{'username':reviewer['username'],'password':reviewer['password'],'apiKey':''}))
    assert 'Admin' not in user['roles'];h={'Authorization':'Bearer '+user['token']}
    series=decode(http(39102,'/api/Series/v2',{},h));assert len(series)==1 and series[0]['name']=='Read Your Way'
    volumes=decode(http(39102,'/api/Series/volumes?seriesId='+str(series[0]['id']),headers=h))
    chapters=[chapter for volume in volumes for chapter in volume['chapters']];assert len(chapters)==1
    chapter=chapters[0];api_key=next((v['key'] for v in user.get('authKeys',[]) if v['name']=='opds'),user.get('apiKey',''))
    checks=[image(http(39102,'/api/Reader/image?chapterId='+str(chapter['id'])+'&page='+str(page)+'&apiKey='+api_key+'&extractPdf=true',headers=h)) for page in range(chapter['pages'])]
    denied=http(39102,'/api/Library/list',headers=h)[0];assert denied in {401,403}
    return {'real_provider':True,'reader_roles':user['roles'],'title':series[0]['name'],'chapters':len(chapters),'page_images':checks,'admin_operation_denied':denied}

def queries():
    source=(REPO/'Aidoku/Core/Sources/BuiltIn/Suwayomi/SuwayomiSource.swift').read_text();result={}
    for m in re.finditer(r'let query = """\n(.*?)\n\s*"""',source,re.S):
        query=textwrap.dedent(m[1]);name=re.match(r'\s*(?:query|mutation)\s+(\w+)',query)
        if name:result[name[1]]=query
    return result

def suwayomi():
    h=basic('suwayomi');templates=queries();fixture=json.loads((RUNTIME/'suwayomi-fixture.json').read_text())
    def gql(name,variables=None,query=None):return http(39104,'/api/graphql',{'query':query or templates[name],'variables':variables or {}},h)
    assert http(39104,'/')[0]==401 and http(39104,'/',headers=h)[0]==200
    listing=decode(gql('SearchManga',{'orderBy':'TITLE','orderByType':'ASC'}))
    assert not listing.get('errors');nodes=listing['data']['mangas']['nodes'];assert len(nodes)==1 and nodes[0]['title']=='Search & Delete'
    details=decode(gql('GetMangaUpdate',{'mangaId':fixture['manga_id']}));assert not details.get('errors')
    chapters=details['data']['chapters']['nodes'];assert len(chapters)==1
    pages=decode(gql('GetPages',{'chapterId':chapters[0]['id']}))['data']['fetchChapterPages']['pages']
    checks=[image(http(39104,path,headers=h)) for path in pages]
    for name,variables in [('GetCategories',{'orderBy':'ORDER','orderByType':'ASC'}),('GetMangaTags',{})]:
        assert 'data' in decode(gql(name,variables))
    denied={
        'forged_named_admin_mutation':gql('GetPages',{'chapterId':1},'mutation GetPages { setSettings(input:{settings:{authMode:NONE}}){__typename} }')[0],
        'unknown_chapter':gql('GetPages',{'chapterId':999999})[0],
        'unknown_manga':gql('GetMangaUpdate',{'mangaId':999999})[0],
        'introspection':gql('GetPages',{},'{__schema{types{name}}}')[0],
        'unexpected_second_operation':gql('GetPages',{'chapterId':1},templates['GetPages']+' query Sneak { settings { authPassword } }')[0],
        'arbitrary_filesystem_route':http(39104,'/api/v1/file/read?path=/etc/passwd',headers=h)[0],
        'upstream_settings_route':http(39104,'/api/v1/settings',headers=h)[0],
        'unknown_image':http(39104,'/api/v1/manga/999/chapter/999/page/0',headers=h)[0]
    }
    assert all(code in {403,404} for code in denied.values()),denied
    return {'real_provider':True,'restricted_gateway':True,'upstream_admin_credentials_exposed':False,'title':nodes[0]['title'],'chapters':len(chapters),'page_images':checks,'negative_scope_checks':denied,'native_app_query_templates_tested':5}

if __name__=='__main__':
    report={'public_deployment':False,'providers':{}}
    for name,probe in [('komga',komga),('kavita',kavita),('suwayomi',suwayomi)]:
        try:
            result=probe();report['providers'][name]={'passed':True,**result};print(json.dumps({'provider':name,'passed':True}),flush=True)
        except Exception as error:
            report['providers'][name]={'passed':False,'error_type':type(error).__name__,'message':str(error)[:180]};print(json.dumps({'provider':name,'passed':False,'error_type':type(error).__name__}),flush=True)
    out=Path(os.environ.get('HONBAKO_REVIEW_PROBE_OUTPUT', str(REPO/'AppStore/review/build73/reviewer-provider-probes.json'))).resolve();out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2)+'\n')
    if not all(p['passed'] for p in report['providers'].values()):raise SystemExit(1)
