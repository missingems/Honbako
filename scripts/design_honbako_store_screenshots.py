#!/usr/bin/env python3
"""Typeset native dark-mode Honbako captures inside licensed, unmodified Apple bezels."""
from pathlib import Path
import hashlib,json,shutil,sys
from PIL import Image,ImageDraw,ImageFont
ROOT=Path('/Users/jun/Documents/Codex/Honbako/AppStore')
SOURCE_CAPTURE_BUILD=28
SOURCE_CAPTURE_CONFIGURATION='Debug simulator'
SOURCE_CAPTURE_APPEARANCE='Dark'
SOURCE_CAPTURE_FLAGS={'HONBAKO_PERSONAL_FEATURES':'NO','HONBAKO_IMPORT_ENGLISH_50':'NO'}
RAW=ROOT/'screenshot-captures/build28-dark'
RAW_PROVENANCE=RAW/'capture-manifest.json'
CANVAS_COLOR='#050506';HEADLINE_COLOR='#F5F5F7';SUBTITLE_COLOR='#A8A8AE'
OUT=ROOT/'screenshots'
FRAMES=Path('/Users/jun/Documents/Codex/2026-10-24/help-me-clone-x20/work/honbako/apple-frames')
PREVIEW=Path('/Users/jun/Documents/ChatGPT/Aidoku/output/honbako-review')
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
'iphone':Path('/Volumes/Bezel-iPhone-18/PNG/iPhone 18 Pro/iPhone 18 Pro - Silver - Portrait.png'),
'ipad-portrait':Path('/Volumes/Bezel-iPad-Pro-(M5)/PNG/iPad Pro (M5) 13" - Silver - Portrait.png'),
'ipad-landscape':Path('/Volumes/Bezel-iPad-Pro-(M5)/PNG/iPad Pro (M5) 13" - Silver - Landscape.png')}
BOXES={'iphone':(72,69,1206,2622),'ipad-portrait':(118,124,2064,2752),'ipad-landscape':(124,118,2752,2064)}
FRAMES.mkdir(parents=True,exist_ok=True)
for key,src in FRAME_SOURCES.items():
 dest=FRAMES/(key+'.png')
 if not dest.exists():shutil.copy2(src,dest)
license_dest=FRAMES/'Apple Design Resources License.rtf'
if not license_dest.exists():shutil.copy2('/Volumes/Bezel-iPhone-18/Apple Design Resources License.rtf',license_dest)
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
requested=sys.argv[1:] or list(COPY)
entries=[v for v in json.loads((OUT/'capture-provenance.json').read_text()).get('captures',[]) if v['file'].split('/')[1] not in requested]
for locale in requested:
 for device in ['iphone','ipad']:
  W,H=(1206,2622) if device=='iphone' else (2064,2752)
  for idx,name in enumerate(['01-library.jpg','02-reader.jpg','03-chapters.jpg']):
   raw=RAW/locale/device/name;im=Image.open(raw).convert('RGB')
   key='iphone' if device=='iphone' else ('ipad-landscape' if im.width>im.height else 'ipad-portrait')
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
   top=round(H*.254 if device=='iphone' else H*.292)
   bottom=round(H*.955)
   available=(round(W*.91),bottom-top)
   scale=min(available[0]/product.width,available[1]/product.height)
   product=product.resize((round(product.width*scale),round(product.height*scale)),Image.Resampling.LANCZOS)
   px=(W-product.width)//2;py=top+(bottom-top-product.height)//2
   c.alpha_composite(product,(px,py))
   dest=OUT/locale/device/name;c.convert('RGB').save(dest,quality=97,subsampling=0)
   entries.append({'file':str(dest.relative_to(ROOT)),'raw_capture':str(raw.relative_to(ROOT)),'raw_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),'apple_bezel':key,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'width':W,'height':H})
manifest={'design':'Near-black canvas with high-contrast centered headlines and enlarged subtitles, no marketing brand label, complete licensed silver Apple product bezels; unchanged native dark-mode app screenshot content','image_generation_used_for_this_redesign':False,'ui_fabricated':False,'source_capture_build':SOURCE_CAPTURE_BUILD,'source_capture_configuration':SOURCE_CAPTURE_CONFIGURATION,'source_capture_appearance':SOURCE_CAPTURE_APPEARANCE,'source_capture_flags':SOURCE_CAPTURE_FLAGS,'source_capture_provenance':str(RAW_PROVENANCE.relative_to(ROOT)),'apple_design_resource_license':'Owner explicitly accepted 2026-10-28','apple_bezel_sources':['https://developer.apple.com/design/resources/','https://devimages-cdn.apple.com/design/resources/download/Bezel-iPhone-18.dmg','https://devimages-cdn.apple.com/design/resources/download/Bezel-iPad-Pro-%28M5%29.dmg'],'captures':entries,'uploadedToAppStoreConnect':False}
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
print('24 designs rendered with exact Apple bezels and preserved source captures')
