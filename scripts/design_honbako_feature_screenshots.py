"""Feature-led 0.2.0 App Store artwork with actual UI and official app icons."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageOps,ImageFilter
from functools import lru_cache
import json,hashlib,argparse
import honbako_store_feature_art as core
HERE=core.ROOT/'AppStore/design-assets'
OUT=core.ROOT/'AppStore'
PROOFS=core.ROOT/'AppStore/review/build77/feature-screenshots'
PROOFS.mkdir(parents=True,exist_ok=True)
INK='#1D1D1F';SECONDARY='#6E6E73';DUNE='#8F7049';BACKGROUND='#F5F5F7'
COPY={
'en-US':[
(['Your manga.','Your AI.'],'Your own companion. Connected through MCP.'),
(['Ask about','any page.'],'Explanations and annotations from your own AI.'),
(['Read Japanese.','Character by character.'],'Romaji, pronunciation and translation. With Pro.'),
(['Your sources.','One library.'],'Komga, Kavita, Suwayomi, files and extensions.'),
(['Your library.','Synced.'],'Free iCloud sync for your library and progress.'),
(['Your AI.',"You’re in control."],'History, books and sources. With your permission.')],
'ja':[
(['あなたのマンガ。','あなたのAI。'],'いつものAIを、MCPで読書の相棒に。'),
(['このページを、','AIと読み解く。'],'場面を解説して、マンガに注釈を。'),
(['一文字ずつ、','日本語を読む。'],'ローマ字・発音・翻訳。Proで使えます。'),
(['自分のソースを、','ひとつの本棚に。'],'個人サーバー、ファイル、拡張機能。'),
(['本棚も、続きも、','いつも一緒に。'],'iCloudで同期。無料で使えます。'),
(['あなたのAI。','決めるのはあなた。'],'読書履歴、本、ソース。許可した範囲だけ。')],
'zh-Hans':[
(['你的漫画。','你的 AI。'],'通过 MCP，让自己的 AI 成为阅读伙伴。'),
(['这一页，','一起看懂。'],'让自己的 AI 解释画面，添加批注。'),
(['一个字符，','读懂日语。'],'罗马字、发音和翻译。Pro 专属。'),
(['你的来源。','一个书架。'],'个人服务器、文件与扩展仓库。'),
(['你的书架。','同步更新。'],'iCloud 同步书库和阅读进度，免费提供。'),
(['你的 AI。','由你掌控。'],'阅读历史、书籍和来源，仅在你的授权下。')],
'zh-Hant':[
(['你的漫畫。','你的 AI。'],'透過 MCP，讓自己的 AI 成為閱讀夥伴。'),
(['這一頁，','一起看懂。'],'讓自己的 AI 解釋畫面，加入註記。'),
(['一個字元，','讀懂日語。'],'羅馬字、發音和翻譯。Pro 專屬。'),
(['你的來源。','一個書架。'],'個人伺服器、檔案與擴充功能儲存庫。'),
(['你的書架。','同步更新。'],'iCloud 同步書庫和閱讀進度，免費提供。'),
(['你的 AI。','由你掌控。'],'閱讀歷史、書籍和來源，僅在你的授權下。')]}
@lru_cache(maxsize=128)
def font(locale,size,bold=False):
    if locale=='en-US':return ImageFont.truetype(core.FONT+('Bold' if bold else 'Regular')+'.otf',round(size))
    return ImageFont.truetype(str(core.JP) if locale=='ja' else core.CJK,round(size),index=2 if locale.startswith('zh') and bold else 0)
def fit(d,lines,locale,size,width,bold):
    while max(d.textlength(t,font=font(locale,size,bold)) for t in lines)>width:size-=1
    return size

def center(d,text,y,locale,size,color=INK,bold=False,width=1206):
    f=font(locale,size,bold);d.text(((width-d.textlength(text,font=f))/2,y),text,font=f,fill=color)
@lru_cache(maxsize=2)
def bg(size):
    # Neutral product-stage gradient. Native app screens retain their real dark appearance.
    w,h=size;g=Image.new('RGB',(1,h))
    for y in range(h):
        t=y/h;delta=round(3*max(0,1-abs(t-.65)/.45));g.putpixel((0,y),(245-delta,245-delta,247-delta))
    return g.resize(size).convert('RGBA')

def providers(c,y,large=False):
    d=ImageDraw.Draw(c);w=c.width
    edge=168 if large else 132;gap=180 if large else 166
    centers=[w/2-gap*1.5,w/2,w/2+gap*1.5]
    for cx,name in zip(centers,['Grok','ChatGPT','Claude']):
        raw=Image.open(HERE/'provider-icons'/(name.lower()+'.png')).convert('RGB')
        icon=raw.resize((edge,edge),Image.Resampling.LANCZOS)
        mask=Image.new('L',icon.size);ImageDraw.Draw(mask).rounded_rectangle((0,0,edge-1,edge-1),radius=round(edge*.225),fill=255)
        x=round(cx-edge/2);c.paste(icon,(x,y),mask)
        f=font('en-US',41 if large else 34);label_width=d.textlength(name,font=f)
        d.text((cx-label_width/2,y+edge+18),name,font=f,fill=SECONDARY)

def shadow(c,box):
    layer=Image.new('RGBA',c.size);d=ImageDraw.Draw(layer);x,y,w,h=box
    d.ellipse((x+w*.04,y+h-16,x+w*.96,y+h+32),fill=(0,0,0,48))
    c.alpha_composite(layer.filter(ImageFilter.GaussianBlur(28)))

def sync_devices(locale,width,height):
    layer=Image.new('RGBA',(width,height))
    pad_path=core.NATIVE/locale/'ipad/library.png'
    phone_path=core.NATIVE/locale/'iphone/library.png'
    pad=core.framed(Image.open(pad_path).convert('RGB'),'ipad')
    phone=core.framed(Image.open(phone_path).convert('RGB'),'iphone')
    # A conventional Apple product-family composition: complete upright frames,
    # a smaller iPhone alongside the iPad, with a little foreground overlap.
    pad_h=height-140
    phone_h=round(pad_h*.62)
    pad_w=round(pad.width*pad_h/pad.height)
    phone_w=round(phone.width*phone_h/phone.height)
    overlap=round(pad_w*.25)
    total=pad_w+phone_w-overlap
    scale=min(1,(width-20)/total)
    pad_h=round(pad_h*scale);phone_h=round(phone_h*scale)
    pad_w=round(pad_w*scale);phone_w=round(phone_w*scale);overlap=round(overlap*scale)
    x=(width-(pad_w+phone_w-overlap))//2
    baseline=height-100
    pad=pad.resize((pad_w,pad_h),Image.Resampling.LANCZOS)
    phone=phone.resize((phone_w,phone_h),Image.Resampling.LANCZOS)
    shadow(layer,(x,baseline-pad_h,pad_w,pad_h))
    layer.alpha_composite(pad,(x,baseline-pad_h))
    shadow(layer,(x+pad_w-overlap,baseline-phone_h,phone_w,phone_h))
    layer.alpha_composite(phone,(x+pad_w-overlap,baseline-phone_h))
    return layer,pad_path,phone_path

def artwork_credit(c,locale):
    d=ImageDraw.Draw(c)
    credit='キャラクターイラスト：わたおび' if locale=='ja' else 'Character illustrations: Wataobi'
    center(d,credit,c.height-67,locale,27 if c.width<1500 else 32,SECONDARY,False,c.width)
    return c

def render(locale,device,index):
    ipad=device=='ipad';W,H=(2064,2752) if ipad else (1206,2622)
    c=bg((W,H)).copy();d=ImageDraw.Draw(c);heads,sub=COPY[locale][index]
    hs=fit(d,heads,locale,146 if ipad else 122,W-(224 if ipad else 140),True)
    top=104 if ipad else 128
    lh=round(hs*1.06)
    for i,s in enumerate(heads):center(d,s,top+i*lh,locale,hs,DUNE if i==1 else INK,True,W)
    sy=top+2*lh+(38 if ipad else 46)
    ss=fit(d,[sub],locale,54 if ipad else 47,W-(220 if ipad else 150),False)
    center(d,sub,sy,locale,ss,SECONDARY,False,W)
    product_top=(830 if index==0 else 680) if ipad else (850 if index==0 else 650)
    bottom=H-105
    detail_info=None
    if index==0:providers(c,570 if ipad else 583,large=ipad)
    if index==2:
        # Keep the complete native reader prominent, with an enlarged crop of
        # actual romaji alongside it. No annotation text is redrawn.
        detail_file=core.NATIVE/locale/'iphone/japanese.png'
        detail_info={'native':str(detail_file),'rect':[350,1080,660,1480]}
    if index==4:
        stage_h=1880 if ipad else 1450
        stage,pp,ip=sync_devices(locale,W-(160 if ipad else 42),stage_h)
        py=655 if ipad else 800
        c.alpha_composite(stage,((W-stage.width)//2,py))
        raw=pp if ipad else ip
        c=artwork_credit(c,locale)
        if device=='iphone':c=c.resize((1320,2868),Image.Resampling.LANCZOS)
        return c.convert('RGB'),{'version':'0.2.0','build':77,'locale':locale,'device':device,'state':'library','native':str(raw),'detail':None,'dimensions':list(c.size),'sourceSHA256':hashlib.sha256(raw.read_bytes()).hexdigest(),'secondaryNative':str(ip if ipad else pp),'secondarySHA256':hashlib.sha256((ip if ipad else pp).read_bytes()).hexdigest(),'composition':'iPhone alongside iPad; matching licensed Japanese manga collection; complete upright licensed product frames with proportional relative scale'}
    raw=core.NATIVE/locale/('ipad' if ipad else 'iphone')/(core.STATES[index]+'.png')
    im=ImageOps.exif_transpose(Image.open(raw)).convert('RGB')
    assert im.size==((2064,2752) if ipad else (1320,2868))
    product=core.framed(im,'ipad' if ipad else 'iphone')
    scale=min((W-220 if ipad else 1030)/product.width,(bottom-product_top)/product.height)
    product=product.resize((round(product.width*scale),round(product.height*scale)),Image.Resampling.LANCZOS)
    x=(W-product.width)//2-(100 if ipad else 75) if index==2 else (W-product.width)//2;y=product_top+(bottom-product_top-product.height)//2
    shadow(c,(x,y,product.width,product.height));c.alpha_composite(product,(x,y))
    if index==2:
        detail=Image.open(detail_info['native']).convert('RGB').crop(tuple(detail_info['rect']))
        dw=510 if ipad else 390;dh=round(dw*400/310)
        detail=detail.resize((dw,dh),Image.Resampling.LANCZOS)
        dx=W-dw-(110 if ipad else 58);dy=1170 if ipad else 1110
        shadow_layer=Image.new('RGBA',c.size)
        ImageDraw.Draw(shadow_layer).rounded_rectangle((dx,dy+14,dx+dw,dy+dh+14),radius=24,fill=(0,0,0,45))
        c.alpha_composite(shadow_layer.filter(ImageFilter.GaussianBlur(22)))
        mask=Image.new('L',detail.size);ImageDraw.Draw(mask).rounded_rectangle((0,0,dw-1,dh-1),radius=24,fill=255)
        c.paste(detail,(dx,dy),mask)
    c=artwork_credit(c,locale)
    if device=='iphone' :c=c.resize((1320,2868),Image.Resampling.LANCZOS)
    return c.convert('RGB'),{'version':'0.2.0','build':77,'locale':locale,'device':device,'state':core.STATES[index],'native':str(raw),'detail':detail_info,'dimensions':list(c.size),'sourceSHA256':hashlib.sha256(raw.read_bytes()).hexdigest()}

def main():
    p=argparse.ArgumentParser();p.add_argument('--locales',nargs='+',default=list(COPY));p.add_argument('--devices',nargs='+',default=['iphone-medium','iphone','ipad']);p.add_argument('--only-ipad-library',action='store_true');p.add_argument('--only-sync',action='store_true');a=p.parse_args();entries=[]
    for loc in a.locales:
        for dev in a.devices:
            for i,name in enumerate(core.NAMES):
                if a.only_ipad_library and (dev!='ipad' or i!=4):continue
                if a.only_sync and i!=4:continue
                im,info=render(loc,dev,i);dest=OUT/'screenshots'/loc/dev/(name+'.jpg');dest.parent.mkdir(parents=True,exist_ok=True);im.save(dest,quality=97,subsampling=0)
                info.update(file=str(dest.relative_to(OUT)),sha256=hashlib.sha256(dest.read_bytes()).hexdigest());entries.append(info)
    if a.only_ipad_library or a.only_sync:
        old=json.loads((OUT/'screenshots/capture-provenance.json').read_text())
        keys={(e['locale'],e['device'],e['state']) for e in entries}
        entries=[e for e in old['captures'] if (e['locale'],e['device'],e['state']) not in keys]+entries
        assert len(entries)==72
    manifest={'version':'0.2.0','build':77,'design':'Neutral light product stage; large centered SF headlines, subtle dune accent, larger complete licensed Apple frames, actual native dark-mode UI, actual provider app icons, no decorative chat bubbles or footer copy','newAIGeneratedArtwork':False,'redrawnAppUI':False,'providerIcons':json.loads((HERE/'provider-icons/sources.json').read_text()),'annotationExample':'Locally supplied illustrative MCP response using Honbako sample-story compositions with commercially licensed Wataobi character illustrations, rendered through the unchanged native annotation pipeline','mangaRights':json.loads((HERE/'licensed-manga/licensed-illustrations.json').read_text()),'copy':COPY,'captures':entries,'status':'READY_FOR_VISUAL_QA','uploadedToAppStoreConnect':False}
    (OUT/'screenshots/capture-provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    for loc in a.locales:
        for dev in a.devices:
            sheet=Image.new('RGB',(1800,1340),BACKGROUND)
            for i,name in enumerate(core.NAMES):
                im=Image.open(OUT/'screenshots'/loc/dev/(name+'.jpg'));im.thumbnail((580,640));sheet.paste(im,((i%3)*600+(600-im.width)//2,(i//3)*670))
            sheet.save(PROOFS/('contact-sheet-'+loc+'-'+dev+'.jpg'),quality=96)
    print(json.dumps({'rendered':len(entries),'output':str(OUT)}))
if __name__=='__main__':main()
