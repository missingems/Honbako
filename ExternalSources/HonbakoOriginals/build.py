#!/usr/bin/env python3
"""Build the original-content-only Aidoku 0.7 source ABI, without changing the app.

Requires Node.js and wabt 1.0.39. Set HONBAKO_WABT_MODULE to a temporary wabt
installation, or install the pinned dev dependency next to compile.mjs.
"""
from pathlib import Path
import hashlib,json,struct,subprocess,zipfile,shutil
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
BASE='https://missingems.github.io/Honbako'
CONTENT=BASE+'/originals/bookshop/'
KEY='en.honbako-originals'
TITLE='The Bookshop Between Pages — Online Edition'
PAGE_TITLES=['An Empty Book','A Key, Not a Book','A Door to Your Books','One Page at a Time','A Place to Return','The Next Morning']
def varint(value):
    out=bytearray()
    while value>127: out.append((value&127)|128); value>>=7
    out.append(value); return bytes(out)
def string(value):
    raw=value.encode(); return varint(len(raw))+raw
def opt(value): return b'\0' if value is None else b'\1'+value
def vector(values): return varint(len(values))+b''.join(values)
chapter=(string('first-chapter')+opt(string('The Bookshop Between Pages'))+opt(struct.pack('<f',1))+b'\0\0\0'+opt(string(CONTENT))+opt(string('en'))+b'\0\0')
manga=(string('bookshop-online')+string(TITLE)+opt(string(CONTENT+'cover.png'))+b'\0'+opt(vector([string('Honbako')]))+opt(string('An original six-page Honbako story about a bookseller, a curious cat, and a place to return. Hosted by the app developer for reading and review testing.'))+opt(string(CONTENT))+b'\0'+bytes([2,1,2,1])+b'\0'+opt(vector([chapter])))
pages=[]
for i,title in enumerate(PAGE_TITLES,1):
    url=CONTENT+f'page-{i}.png'
    pages.append(b'\0'+string(url)+b'\0'+opt(string(url))+b'\0'+opt(string(title)))
results={'catalog':vector([manga])+b'\0','empty':b'\0\0','manga':manga,'pages':vector(pages)}
data=[]; addresses={}; pos=1024
for name,body in results.items():
    blob=struct.pack('<II',len(body)+8,len(body)+8)+body; addresses[name]=pos; data.append((pos,blob)); pos=(pos+len(blob)+7)&~7
for name,text in [('book_key','bookshop-online'),('chapter_key','first-chapter'),('listing_key','originals'),('haystack','the bookshop between pages online edition honbako original story mina nori')]:
    raw=text.encode(); addresses[name]=pos; addresses[name+'_len']=len(raw); data.append((pos,raw)); pos+=len(raw)
assert pos<32768
wat=f'''(module
  ;; Read input descriptors only. This module has no network, file, cookie,
  ;; JavaScript or credential imports; all content URLs are developer-owned.
  (import "std" "buffer_len" (func $buffer_len (param i32) (result i32)))
  (import "std" "read_buffer" (func $read_buffer (param i32 i32 i32) (result i32)))
  (memory (export "memory") 2 2)
  (func (export "free_result") (param i32)) ;; fixed immutable result buffers
  (func $read (param $descriptor i32) (result i32) (local $len i32)
    (local.set $len (call $buffer_len (local.get $descriptor)))
    (if (i32.gt_u (local.get $len) (i32.const 8192)) (then (return (i32.const -1))))
    (if (i32.ne (call $read_buffer (local.get $descriptor) (i32.const 65536) (local.get $len)) (i32.const 0)) (then (return (i32.const -1))))
    (local.get $len))
  (func $key (param $descriptor i32) (param $key i32) (param $length i32) (result i32)
    (local $len i32) (local $i i32)
    (local.set $len (call $read (local.get $descriptor)))
    (if (i32.lt_s (local.get $len) (i32.add (local.get $length) (i32.const 1))) (then (return (i32.const 0))))
    (if (i32.ne (i32.load8_u (i32.const 65536)) (local.get $length)) (then (return (i32.const 0))))
    (block $done (loop $loop
      (br_if $done (i32.ge_u (local.get $i) (local.get $length)))
      (if (i32.ne (i32.load8_u (i32.add (i32.const 65537) (local.get $i))) (i32.load8_u (i32.add (local.get $key) (local.get $i)))) (then (return (i32.const 0))))
      (local.set $i (i32.add (local.get $i) (i32.const 1))) (br $loop)))
    (i32.const 1))
  (func $lower (param $c i32) (result i32)
    (if (result i32) (i32.and (i32.ge_u (local.get $c) (i32.const 65)) (i32.le_u (local.get $c) (i32.const 90)))
      (then (i32.add (local.get $c) (i32.const 32))) (else (local.get $c))))
  (func $query_matches (param $len i32) (result i32) (local $i i32) (local $j i32)
    (if (i32.eqz (local.get $len)) (then (return (i32.const 1))))
    (if (i32.gt_u (local.get $len) (i32.const {addresses['haystack_len']})) (then (return (i32.const 0))))
    (block $done (loop $outer
      (br_if $done (i32.gt_u (i32.add (local.get $i) (local.get $len)) (i32.const {addresses['haystack_len']})))
      (local.set $j (i32.const 0))
      (block $mismatch (loop $inner
        (if (i32.ge_u (local.get $j) (local.get $len)) (then (return (i32.const 1))))
        (br_if $mismatch (i32.ne
          (call $lower (i32.load8_u (i32.add (i32.const 65536) (local.get $j))))
          (i32.load8_u (i32.add (i32.const {addresses['haystack']}) (i32.add (local.get $i) (local.get $j))))))
        (local.set $j (i32.add (local.get $j) (i32.const 1))) (br $inner)))
      (local.set $i (i32.add (local.get $i) (i32.const 1))) (br $outer)))
    (i32.const 0))
  (func (export "get_search_manga_list") (param $query i32) (param $page i32) (param $filters i32) (result i32) (local $len i32)
    (if (i32.ne (local.get $page) (i32.const 1)) (then (return (i32.const {addresses['empty']}))))
    (local.set $len (call $read (local.get $query)))
    (if (i32.lt_s (local.get $len) (i32.const 0)) (then (return (i32.const -1))))
    (if (result i32) (call $query_matches (local.get $len)) (then (i32.const {addresses['catalog']})) (else (i32.const {addresses['empty']}))))
  (func (export "get_manga_list") (param $listing i32) (param $page i32) (result i32)
    (if (i32.eqz (call $key (local.get $listing) (i32.const {addresses['listing_key']}) (i32.const {addresses['listing_key_len']}))) (then (return (i32.const -1))))
    (if (result i32) (i32.eq (local.get $page) (i32.const 1)) (then (i32.const {addresses['catalog']})) (else (i32.const {addresses['empty']}))))
  (func (export "get_manga_update") (param $manga i32) (param $details i32) (param $chapters i32) (result i32)
    (if (result i32) (call $key (local.get $manga) (i32.const {addresses['book_key']}) (i32.const {addresses['book_key_len']})) (then (i32.const {addresses['manga']})) (else (i32.const -1))))
  (func (export "get_page_list") (param $manga i32) (param $chapter i32) (result i32)
    (if (result i32) (i32.and
      (call $key (local.get $manga) (i32.const {addresses['book_key']}) (i32.const {addresses['book_key_len']}))
      (call $key (local.get $chapter) (i32.const {addresses['chapter_key']}) (i32.const {addresses['chapter_key_len']})))
      (then (i32.const {addresses['pages']})) (else (i32.const -1))))
'''
for address,blob in data: wat+=f'  (data (i32.const {address}) "'+''.join('\\'+format(x,'02x') for x in blob)+'")\n'
wat+=')\n'; (HERE/'source.wat').write_text(wat)
payload=HERE/'Payload'; payload.mkdir(exist_ok=True)
source={'info':{'id':KEY,'name':'Honbako Originals','version':1,'url':BASE+'/originals/','contentRating':0,'languages':['en']},'listings':[{'id':'originals','name':'Original Story'}],'config':{'maximumParallelRequests':2}}
(payload/'source.json').write_text(json.dumps(source,indent=2)+'\n')
subprocess.run(['node',str(HERE/'compile.mjs'),str(HERE/'source.wat'),str(payload/'main.wasm')],check=True)
shutil.copyfile(ROOT/'Aidoku/App/Resources/Assets.xcassets/AppIcon.appiconset/120.png',payload/'icon.png')
output=ROOT/'site/sources/packages/en.honbako-originals-v1.aix'; output.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
    for name in ['source.json','main.wasm','icon.png']:
        entry=zipfile.ZipInfo('Payload/'+name,date_time=(2026,10,28,0,0,0)); entry.compress_type=zipfile.ZIP_DEFLATED; entry.external_attr=0o100644<<16; archive.writestr(entry,(payload/name).read_bytes())
fixture=ROOT/'SumiTests/Fixtures/en.honbako-originals.aix'; fixture.parent.mkdir(exist_ok=True); shutil.copyfile(output,fixture)
icon=ROOT/'site/sources/icons/en.honbako-originals.png'; icon.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(payload/'icon.png',icon)
index={'name':'Honbako Original Sources','feedbackURL':'https://github.com/missingems/Honbako/issues','sources':[{'id':KEY,'name':'Honbako Originals','version':1,'iconURL':'icons/en.honbako-originals.png','downloadURL':'packages/en.honbako-originals-v1.aix','languages':['en'],'contentRating':0,'baseURL':BASE+'/originals/','minAppVersion':'0.9.0'}]}
(ROOT/'site/sources/index.json').write_text(json.dumps(index,indent=2)+'\n')
manifest={'source_id':KEY,'version':1,'story':TITLE,'story_count':1,'chapter_count':1,'page_count':6,'content_origin':'Existing original Honbako tutorial artwork and project text, exported by the app renderer','source_list_url':BASE+'/sources/index.json','package_url':BASE+'/sources/packages/'+output.name,'content_base_url':CONTENT,'compiler':'wabt1.0.39','abi':'AidokuRunner0.7/Postcard','network_imports':False,'package_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'wasm_sha256':hashlib.sha256((payload/'main.wasm').read_bytes()).hexdigest()}
(HERE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n'); print(json.dumps(manifest,indent=2))
