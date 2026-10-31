#!/usr/bin/env python3
"""Typeset native dark-mode Honbako captures inside licensed, unmodified Apple bezels."""
from pathlib import Path
import argparse,hashlib,json,shutil,sys
from PIL import Image,ImageDraw,ImageFont,ImageOps
ROOT=Path(__file__).resolve().parent.parent/'AppStore'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('locales',nargs='*',metavar='LOCALE')
parser.add_argument('--build',type=int,required=True)
parser.add_argument('--raw',type=Path)
parser.add_argument('--manifest',type=Path,help='Verified mixed-build native capture manifest')
parser.add_argument('--only-ipad-library',action='store_true',help='Replace only the four upright iPad library images')
parser.add_argument('--output',type=Path,default=ROOT/'screenshots')
parser.add_argument('--frames',type=Path,default=Path('/Users/jun/Documents/Codex/2026-10-24/help-me-clone-x20/work/honbako/apple-frames'))
parser.add_argument('--preview',type=Path)
args=parser.parse_args()
SOURCE_CAPTURE_BUILD=args.build
SOURCE_CAPTURE_CONFIGURATION='Debug simulator'
SOURCE_CAPTURE_APPEARANCE='Dark'
SOURCE_CAPTURE_FLAGS={'HONBAKO_EXTERNAL_SOURCES':'NO','HONBAKO_PERSONAL_FEATURES':'NO','HONBAKO_IMPORT_ENGLISH_50':'NO'}
RAW=args.raw or ROOT/'screenshot-captures'/f'build{args.build}-dark'
RAW_PROVENANCE=args.manifest or RAW/'capture-manifest.json'
CANVAS_COLOR='#050506';HEADLINE_COLOR='#F5F5F7';SUBTITLE_COLOR='#A8A8AE'
OUT=args.output
FRAMES=args.frames
PREVIEW=args.preview or ROOT/'review'/f'build{args.build}'/'screenshot-proofs'
SF='/Library/Fonts/SF-Pro-Display-Bold.otf';REG='/Library/Fonts/SF-Pro-Display-Regular.otf'
JP=next(Path('/System/Library/Fonts').glob('* W6.ttc'));CJK='/System/Library/Fonts/Hiragino Sans GB.ttc'
COPY={
'en-US':[
('Your manga.\nAll together.','Your files. Your server. Your library.'),
('Get lost\nin the story.','A quiet space for every page.'),
('Pick up\nwhere you left off.','Your chapter. Your progress. Saved.')],
'ja':[
('好きなマンガを、\nひとつの本棚に。','自分のファイルも、自分のサーバーも。'),
('物語に、\nもっと集中。','ページを楽しむ、静かな読書空間。'),
('続きは、\nここから。','チャプターも、読書の進み具合も保存。')],
'zh-Hans':[
('你的漫画，\n都在这里。','自己的文件、服务器与专属书架。'),
('沉浸故事，\n静心阅读。','每一页，都值得用心。'),
('打开书架，\n接着读。','保存章节与进度，随时继续。')],
'zh-Hant':[
('你的漫畫，\n都在這裡。','自己的檔案、伺服器與專屬書架。'),
('沉浸故事，\n靜心閱讀。','每一頁，都值得用心。'),
('打開書架，\n接著讀。','儲存章節與進度，隨時繼續。')]}
FRAME_SOURCES={
'iphone-large':Path('/Volumes/Bezel-iPhone-18/PNG/iPhone 18 Pro Max/iPhone 18 Pro Max - Silver - Portrait.png'),
'ipad-portrait':Path('/Volumes/Bezel-iPad-Pro-(M5)/PNG/iPad Pro (M5) 13" - Silver - Portrait.png'),
'ipad-landscape':Path('/Volumes/Bezel-iPad-Pro-(M5)/PNG/iPad Pro (M5) 13" - Silver - Landscape.png')}
BOXES={'iphone-large':(75,66,1320,2868),'ipad-portrait':(118,124,2064,2752),'ipad-landscape':(124,118,2752,2064)}
# Verify the complete current capture set before touching any final listing file.
source_manifest=json.loads(RAW_PROVENANCE.read_text())
assert source_manifest['status']=='verified'
if not args.manifest: assert str(source_manifest['build'])==str(args.build)
assert source_manifest['nativeCaptureCount']==24 and source_manifest['publicFlags']==SOURCE_CAPTURE_FLAGS
source_rows={(v['locale'],v['device'],v['state']):v for v in source_manifest['captures']}
source_builds=sorted({int(v['build']) for v in source_manifest['captures']})
for locale in COPY:
 for device in ['iphone','ipad']:
  for name in ['01-library.jpg','02-reader.jpg','03-chapters.jpg']:
   record=source_rows[(locale,device,name.removesuffix('.jpg'))]
   raw=ROOT/record['file']
   assert hashlib.sha256(raw.read_bytes()).hexdigest()==record['sha256'],f'Unverified source {raw}'
   with Image.open(raw) as source:
    assert source.size==(record['width'],record['height'])
    normalized=ImageOps.exif_transpose(source)
    assert normalized.size==(record['width'],record['height']),f'Unnormalized native orientation {raw}'
for key in BOXES:
 assert (FRAMES/(key+'.png')).is_file(),f'Missing licensed Apple bezel {key}'
assert (FRAMES/'Apple Design Resources License.rtf').is_file()
def font(locale,size,bold=False):
 return ImageFont.truetype((SF if bold else REG) if locale=='en-US' else (str(JP) if locale=='ja' else CJK),round(size),index=2 if locale.startswith('zh') and bold else 0)
def fit(d,lines,locale,size,width,bold):
 while max(d.textlength(line,font=font(locale,size,bold)) for line in lines)>width:size-=1
 return font(locale,size,bold)
APERTURES={}
def framed(img,key):
 bezel=Image.open(FRAMES/(key+'.png')).convert('RGBA')
 x,y,w,h=BOXES[key]
 assert img.size==(w,h),(img.size,(w,h))
 # The frame's own transparent screen aperture supplies the exact rounded shape.
 if key not in APERTURES:
  barrier=bezel.getchannel('A').point(lambda a:255 if a>=254 else 0)
  ImageDraw.floodfill(barrier,(bezel.width//2,bezel.height//2),128,thresh=0)
  APERTURES[key]=barrier.point(lambda a:255 if a==128 else 0)
 aperture=APERTURES[key]
 screen=Image.new('RGBA',bezel.size);screen.alpha_composite(img.convert('RGBA'),(x,y));screen.putalpha(aperture)
 screen.alpha_composite(bezel)
 return screen
requested=args.locales or list(COPY)
assert set(requested)==set(COPY),'A release refresh must render all four locales together'
existing=json.loads((OUT/'capture-provenance.json').read_text()) if (OUT/'capture-provenance.json').exists() else {}
entries=[v for v in existing.get('captures',[]) if (not (v['file'].split('/')[1] in requested and '/ipad/01-library.jpg' in v['file']))] if args.only_ipad_library else [v for v in existing.get('captures',[]) if v['file'].split('/')[1] not in requested]
if args.only_ipad_library: assert len(entries)==32,'Preserve exactly the other 32 verified final images'
OUT.mkdir(parents=True,exist_ok=True)
for locale in requested:
 for device in ['iphone','iphone-medium','ipad']:
  W,H=(1320,2868) if device=='iphone' else ((1206,2622) if device=='iphone-medium' else (2064,2752))
  for idx,name in enumerate(['01-library.jpg','02-reader.jpg','03-chapters.jpg']):
   if args.only_ipad_library and (device!='ipad' or name!='01-library.jpg'):continue
   raw_device='iphone' if device=='iphone-medium' else device
   record=source_rows[(locale,raw_device,name.removesuffix('.jpg'))]
   raw=ROOT/record['file'];im=ImageOps.exif_transpose(Image.open(raw)).convert('RGB')
   key='iphone-large' if device.startswith('iphone') else ('ipad-landscape' if im.width>im.height else 'ipad-portrait')
   c=Image.new('RGBA',(W,H),CANVAS_COLOR);d=ImageDraw.Draw(c)
   unit=W/1206
   head,sub=COPY[locale][idx];lines=head.splitlines()
   hf=fit(d,lines,locale,round((104 if locale=='en-US' else 92)*unit),W*.90,True)
   hy=round(H*.094);line_h=round(hf.size*1.04)
   for j,line in enumerate(lines):d.text(((W-d.textlength(line,font=hf))/2,hy+j*line_h),line,font=hf,fill=HEADLINE_COLOR)
   sf=fit(d,[sub],locale,round(50*unit),W*.88,False)
   sy=hy+len(lines)*line_h+round(40*unit)
   d.text(((W-d.textlength(sub,font=sf))/2,sy),sub,font=sf,fill=SUBTITLE_COLOR)
   product=framed(im,key)
   # Keep the complete Apple product unmodified: no crop, tilt, added shadow or overlap.
   top=round(H*.254 if device.startswith('iphone') else H*.292)
   bottom=round(H*.955)
   available=(round(W*.91),bottom-top)
   scale=min(available[0]/product.width,available[1]/product.height)
   product=product.resize((round(product.width*scale),round(product.height*scale)),Image.Resampling.LANCZOS)
   px=(W-product.width)//2;py=top+(bottom-top-product.height)//2
   c.alpha_composite(product,(px,py))
   dest=OUT/locale/device/name;dest.parent.mkdir(parents=True,exist_ok=True);c.convert('RGB').save(dest,quality=97,subsampling=0)
   entries.append({'file':str(dest.relative_to(ROOT)) if dest.is_relative_to(ROOT) else str(dest),'raw_capture':str(raw.relative_to(ROOT)),'source_capture_build':int(record['build']),'raw_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),'apple_bezel':key,'apple_bezel_sha256':hashlib.sha256((FRAMES/(key+'.png')).read_bytes()).hexdigest(),'native_capture_width':im.width,'native_capture_height':im.height,'canvas_slot':('iPhone Dynamic Island medium (required)' if device=='iphone-medium' else ('iPhone Dynamic Island large (optional)' if device=='iphone' else 'iPad 13-inch (required)')),'composition':'Unchanged native capture placed in its matching complete Apple frame; the whole framed product is uniformly scaled to fit the marketing canvas, with no independent UI crop, stretch or redraw','sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'width':W,'height':H})
manifest={'design':'Near-black canvas with high-contrast centered headlines and enlarged subtitles, no marketing brand label, complete licensed silver Apple product bezels; unchanged native dark-mode app screenshot content','image_generation_used_for_this_redesign':False,'ui_fabricated':False,'source_capture_build':source_builds[0] if len(source_builds)==1 else None,'source_capture_builds':source_builds,'source_capture_configuration':SOURCE_CAPTURE_CONFIGURATION,'source_capture_appearance':SOURCE_CAPTURE_APPEARANCE,'source_capture_flags':SOURCE_CAPTURE_FLAGS,'source_capture_provenance':str(RAW_PROVENANCE.relative_to(ROOT)) if RAW_PROVENANCE.is_relative_to(ROOT) else str(RAW_PROVENANCE),'apple_design_resource_license':'Owner explicitly accepted 2026-10-28','apple_bezel_sources':['https://developer.apple.com/design/resources/','https://devimages-cdn.apple.com/design/resources/download/Bezel-iPhone-18.dmg','https://devimages-cdn.apple.com/design/resources/download/Bezel-iPad-Pro-%28M5%29.dmg'],'native_capture_count':24,'framed_output_count':len(entries),'captures':entries,'uploadedToAppStoreConnect':False}
(OUT/'capture-provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
PREVIEW.mkdir(parents=True,exist_ok=True)
preview=Image.new('RGB',(1160,840),CANVAS_COLOR)
for i,name in enumerate(['01-library.jpg','02-reader.jpg','03-chapters.jpg']):
 im=Image.open(OUT/'en-US/iphone'/name);im.thumbnail((370,804));preview.paste(im,(10+i*385,18))
preview.save(PREVIEW/'store-design-proper-frames.jpg',quality=95)
proof=Image.new('RGB',(1536,1320),CANVAS_COLOR)
for row,locale in enumerate(COPY):
 for col,(device,name) in enumerate([(dev,n) for dev in ['iphone','ipad'] for n in ['01-library.jpg','02-reader.jpg','03-chapters.jpg']]):
  im=Image.open(OUT/locale/device/name);im.thumbnail((240,312));proof.paste(im,(col*256+(256-im.width)//2,row*330+8))
proof.save(PREVIEW/'store-design-all-locales-v2.jpg',quality=95)
required=Image.new('RGB',(1536,1320),CANVAS_COLOR)
all_sizes=Image.new('RGB',(2304,1320),CANVAS_COLOR)
for row,locale in enumerate(COPY):
 for col,(device,name) in enumerate([(dev,n) for dev in ['iphone-medium','ipad'] for n in ['01-library.jpg','02-reader.jpg','03-chapters.jpg']]):
  im=Image.open(OUT/locale/device/name);im.thumbnail((240,312));required.paste(im,(col*256+(256-im.width)//2,row*330+8))
 for col,(device,name) in enumerate([(dev,n) for dev in ['iphone-medium','iphone','ipad'] for n in ['01-library.jpg','02-reader.jpg','03-chapters.jpg']]):
  im=Image.open(OUT/locale/device/name);im.thumbnail((240,312));all_sizes.paste(im,(col*256+(256-im.width)//2,row*330+8))
required.save(PREVIEW/'store-design-required-medium-ipad.jpg',quality=95)
all_sizes.save(PREVIEW/'store-design-all-locales-all-sizes.jpg',quality=95)
medium=Image.new('RGB',(1160,840),CANVAS_COLOR)
for i,name in enumerate(['01-library.jpg','02-reader.jpg','03-chapters.jpg']):
 im=Image.open(OUT/'en-US/iphone-medium'/name);im.thumbnail((370,804));medium.paste(im,(10+i*385,18))
medium.save(PREVIEW/'store-design-medium-proper-frames.jpg',quality=95)
print(f'{len(entries)} designs verified from native dark capture builds{source_builds} with exact Apple bezels; required Medium+iPad and optional Large')
