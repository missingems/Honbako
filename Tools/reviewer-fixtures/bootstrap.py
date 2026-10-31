#!/usr/bin/env python3
"""Idempotent original-only fixture setup using real provider administration APIs."""
import json
import urllib.parse
from support import ROOT,RUNTIME,CREDENTIALS,CREDENTIALS_PATH,LIBRARIES,http,decode,basic,suwayomi,suwayomi_http

def save_private(path,value):
    path.write_text(json.dumps(value,indent=2)+'\n');path.chmod(0o600)

def setup_komga():
    claim=decode(http(39101,'/api/v1/claim'))
    if not claim['isClaimed']:
        c=CREDENTIALS['komga']['admin']
        decode(http(39101,'/api/v1/claim',{}, {'X-Komga-Email':c['username'],'X-Komga-Password':c['password']}))
    h=basic('komga','admin');libraries=decode(http(39101,'/api/v1/libraries',headers=h))
    for kind,name in [('komga','Honbako Personal Collection Review'),('mcp','Honbako MCP Original Sample')]:
        library=next((v for v in libraries if v['name']==name),None)
        if library is None:
            library=decode(http(39101,'/api/v1/libraries',{'name':name,'root':str(LIBRARIES/kind),'scanOnStartup':False},h))
        assert http(39101,'/api/v1/libraries/'+library['id']+'/scan',{},h)[0]==202
    users=decode(http(39101,'/api/v2/users',headers=h));reviewer=CREDENTIALS['komga']['reviewer']
    user=next((v for v in users if v['email']==reviewer['username']),None)
    if user is None:
        user=decode(http(39101,'/api/v2/users',{'email':reviewer['username'],'password':reviewer['password'],'roles':['PAGE_STREAMING'],'sharedLibraries':{'all':True,'libraryIds':[]}},h))
    assert 'ADMIN' not in user['roles']
    print(json.dumps({'provider':'komga','configured':True,'restricted_reviewer':True}))

def setup_kavita():
    c=CREDENTIALS['kavita']['admin']
    username='honbako-admin'
    response=http(39102,'/api/Account/login',{'username':username,'password':c['password'],'apiKey':''})
    if response[0]==401:
        response=http(39102,'/api/Account/register',{'username':username,'email':c.get('email',c['username']),'password':c['password']})
    admin=decode(response);c['email']=admin['email'];c['username']=admin['username'];h={'Authorization':'Bearer '+admin['token']}
    libraries=decode(http(39102,'/api/Library/libraries',headers=h));library=next((v for v in libraries if v['name']=='Honbako Original Review'),None)
    if library is None:
        dto={'id':0,'name':'Honbako Original Review','type':0,'folders':[str(LIBRARIES/'kavita')],'folderWatching':False,'includeInDashboard':True,'includeInSearch':True,'manageCollections':False,'manageReadingLists':False,'allowScrobbling':False,'allowMetadataMatching':False,'enableMetadata':False,'removePrefixForSortName':False,'inheritWebLinksFromFirstChapter':False,'defaultLanguage':'en','metadataProvider':3,'fileGroupTypes':[1],'excludePatterns':[]}
        library=decode(http(39102,'/api/Library/create',dto,h))
    assert http(39102,'/api/Library/scan?libraryId='+str(library['id']),{},h)[0]==200
    reviewer=CREDENTIALS['kavita']['reviewer'];username='honbako-reviewer'
    response=http(39102,'/api/Account/login',{'username':username,'password':reviewer['password'],'apiKey':''})
    if response[0]==401:
        email=reviewer.get('email',reviewer['username'])
        invite=decode(http(39102,'/api/Account/invite',{'email':email,'roles':['Login','Read Only'],'libraries':[library['id']],'ageRestriction':{'ageRating':0,'includeUnknowns':True}},h))
        assert not invite['emailSent'],'Fixture must not send email'
        token=urllib.parse.parse_qs(urllib.parse.urlsplit(invite['emailLink']).query)['token'][0]
        response=http(39102,'/api/Account/confirm-email',{'email':email,'username':username,'password':reviewer['password'],'token':token})
    user=decode(response);assert 'Admin' not in user['roles']
    reviewer['email']=user['email'];reviewer['username']=user['username']
    save_private(CREDENTIALS_PATH,CREDENTIALS)
    print(json.dumps({'provider':'kavita','configured':True,'restricted_reviewer':True}))

def setup_suwayomi():
    sources=decode(suwayomi_http('/api/v1/source/list'));assert any(v['id']=='0' for v in sources)
    catalog=decode(suwayomi_http('/api/v1/source/0/popular/1'))['mangaList']
    assert len(catalog)==1 and catalog[0]['title']=='Search & Delete','Only the original sample may be imported'
    identifier=catalog[0]['id']
    suwayomi('mutation($id:Int!){updateManga(input:{id:$id,patch:{inLibrary:true}}){__typename} fetchMangaAndChapters(input:{id:$id,fetchManga:true,fetchChapters:true}){__typename}}',{'id':identifier})
    chapters=suwayomi('query($id:Int!){chapters(condition:{mangaId:$id}){nodes{id}}}',{'id':identifier})['chapters']['nodes']
    assert len(chapters)==1
    state={'manga_id':identifier,'chapters':[],'pages':[]}
    for chapter in chapters:
        pages=suwayomi('mutation($id:Int!){fetchChapterPages(input:{chapterId:$id}){pages}}',{'id':chapter['id']})['fetchChapterPages']['pages']
        assert len(pages)==5 and all(p.startswith('/api/v1/manga/'+str(identifier)+'/chapter/'+str(chapter['id'])+'/page/') for p in pages)
        state['chapters'].append(chapter['id']);state['pages']+=pages
    (RUNTIME/'suwayomi-fixture.json').write_text(json.dumps(state,indent=2)+'\n')
    print(json.dumps({'provider':'suwayomi','configured':True,'restricted_gateway_required':True}))

if __name__=='__main__':
    setup_komga();setup_kavita();setup_suwayomi()
