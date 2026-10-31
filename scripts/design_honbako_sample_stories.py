from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageOps,ImageEnhance,ImageFilter
import math,json,random,hashlib
ROOT=Path(__file__).resolve().parent.parent/'AppStore/design-assets/licensed-manga'
OUT=ROOT/'sample';OUT.mkdir(exist_ok=True)
JP='/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc';MIN='/System/Library/Fonts/ヒラギノ明朝 ProN.ttc';EN='/System/Library/Fonts/Supplemental/Arial.ttf';BOLD='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
def font(s,serif=False,en=False,bold=False):return ImageFont.truetype((BOLD if bold else EN) if en else (MIN if serif else JP),s)
def text(d,xy,s,size=30,fill='#19212c',serif=False,en=False,bold=False):d.text(xy,s,font=font(size,serif,en,bold),fill=fill)
def line(d,coords,fill='#19212c',width=2):d.line(coords,fill=fill,width=width)
def character(key,expression=0,mono=False):
 im=Image.open(ROOT/f'{key}-{expression}.png').convert('RGBA')
 box=im.getchannel('A').getbbox();im=im.crop(box)
 if mono:
  a=im.getchannel('A');g=ImageOps.grayscale(im);g=ImageEnhance.Contrast(g).enhance(1.55);g=ImageOps.autocontrast(g,cutoff=1)
  im=Image.merge('RGBA',(g,g,g,a))
 return im

def paste_char(c,key,rect,head_fraction=0.64,expression=0,mono=False,mirror=False):
 # Crop a naturally proportioned bust from the licensed full-height drawing.
 im=character(key,expression,mono);im=im.crop((0,0,im.width,int(im.height*head_fraction)))
 if mirror:im=ImageOps.mirror(im)
 x,y,w,h=rect;im=ImageOps.fit(im,(w,h),centering=(.5,.1));c.alpha_composite(im,(x,y))

def tone(c,rect,color='#83919c',gap=14,radius=1):
 d=ImageDraw.Draw(c);x,y,w,h=rect
 for yy in range(y,y+h,gap):
  for xx in range(x+(gap//2 if (yy//gap)%2 else 0),x+w,gap):d.ellipse((xx,yy,xx+radius*2,yy+radius*2),fill=color)

def city(d,rect,ink='#9fabae',fill=None):
 x,y,w,h=rect;r=random.Random(103);cur=x
 while cur<x+w:
  bw=r.randint(55,120);bh=r.randint(int(h*.3),int(h*.95));d.rectangle((cur,y+h-bh,cur+bw,y+h),outline=ink,fill=fill,width=2)
  for wy in range(y+h-bh+18,y+h-10,30):
   for wx in range(cur+12,cur+bw-10,24):d.rectangle((wx,wy,wx+8,wy+13),outline=ink,width=1)
  cur+=bw+12

def branches(d,x,y,ink='#9fabae'):
 for i in range(7):
  tx=x+(i-3)*90;ty=y-250-i%3*40;line(d,[(x,y),(tx,ty)],ink,3)
  for j in range(5):
   px=x+(tx-x)*(j+1)/6;py=y+(ty-y)*(j+1)/6
   d.ellipse((px-16,py-7,px+16,py+7),outline=ink,width=2)

def vertical(d,x,y,s,size=100,fill='#19212c',serif=True,step=None):
 for i,ch in enumerate(s):text(d,(x,y+i*(step or size)),ch,size,fill,serif)

BOOKS=[
 ('akari','星を待つ駅','AFTER THE LAST TRAIN','#e9eee7','#c34a39','station'),
 ('moon','月影の剣','MOONLIT BLADE','#183747','#e7be66','moon'),
 ('winter','雪の庭','WINTER GARDEN','#edf3f3','#315b74','snow'),
 ('summer','夏の約束','OUR LAST SUMMER','#f3e3d8','#ad3b43','summer'),
 ('shade','九番街の影','SHADOWS ON NINTH','#e9e5df','#252b31','city'),
 ('garden','旅する庭師','THE WANDERING GARDEN','#ebede2','#5c6f41','garden'),
 ('spirit','灯りの向こう','BEYOND THE LANTERNS','#203538','#d57b55','lantern'),
 ('ren','雨の日の便り','LETTERS IN THE RAIN','#dae5ec','#335c78','rain'),
]
for i,(key,jtitle,eng,bg,accent,kind) in enumerate(BOOKS):
 c=Image.new('RGBA',(1000,1500),bg);d=ImageDraw.Draw(c);dark=kind in ('moon','lantern');ink='#f6f1e5' if dark else '#20262d'
 text(d,(54,36),'HONBAKO  /  SAMPLE STORIES',21,ink,en=True,bold=True);text(d,(899,26),'01',42,ink,en=True,bold=True)
 line(d,[(54,81),(946,81)],ink,2)
 if kind=='station':
  city(d,(30,220,940,600),ink='#a0aaa1');tone(c,(0,1150,1000,350),color='#b9c1b4',gap=16)
  d.rectangle((60,120,940,1270),outline='#adb9ab',width=2);paste_char(c,key,(165,340,780,1000),.68)
  d=ImageDraw.Draw(c);text(d,(55,130),jtitle,115,accent);text(d,(63,285),'A story between the last train and the first light.',24,ink,en=True)
 elif kind=='moon':
  d.ellipse((80,190,930,1040),fill='#d4dbd8');d.arc((100,220,890,1010),30,325,fill=accent,width=3);tone(c,(0,1050,1000,450),'#51717a',18)
  paste_char(c,key,(25,360,780,1030),.8);d=ImageDraw.Draw(c);vertical(d,800,165,jtitle,127,accent);text(d,(60,170),'月は、道を照らす。',32,'#e6e6da',serif=True)
 elif kind=='snow':
  branches(d,120,750,'#9aacb3');branches(d,930,440,'#acbac0');paste_char(c,key,(80,370,840,990),.64)
  d=ImageDraw.Draw(c);text(d,(55,140),jtitle,139,accent,True)
  for sx,sy in [(65,1000),(870,1100),(880,650),(670,345),(240,1190),(50,470),(750,1250)]:d.ellipse((sx,sy,sx+13,sy+13),fill='white')
 elif kind=='summer':
  d.ellipse((330,230,1090,990),fill='#d5a68c');line(d,[(0,410),(1000,225)],'#805c50',3);line(d,[(0,445),(1000,260)],'#805c50',2)
  paste_char(c,key,(65,290,815,1090),.72);d=ImageDraw.Draw(c);vertical(d,790,165,jtitle,128,accent);text(d,(60,155),'あの夏を、忘れない。',29,ink,True)
 elif kind=='city':
  d.rectangle((0,180,1000,330),fill='#252b31');text(d,(58,195),'九番街',101,'#f0ece4');city(d,(0,280,1000,950),'#8f928f')
  paste_char(c,key,(160,390,800,990),.66,mono=True);d=ImageDraw.Draw(c);text(d,(53,1070),'の影',155,'#ece8e0',True)
 elif kind=='garden':
  d.ellipse((80,200,930,1050),outline='#b4bfaa',width=3);branches(d,140,1100,'#819373');branches(d,930,890,'#819373')
  paste_char(c,key,(220,330,730,1040),.70);d=ImageDraw.Draw(c);vertical(d,60,180,jtitle,120,accent);text(d,(500,160),'どこへでも、花は咲く。',27,accent,True)
 elif kind=='lantern':
  for x,y in [(120,220),(820,320),(460,190)]:
   line(d,[(x,y-70),(x,y+30)],'#9c6a48',3);d.ellipse((x-75,y,x+75,y+180),outline=accent,width=3)
   for xx in range(x-50,x+60,25):line(d,[(xx,y+25),(xx,y+155)],'#7a6652',1)
  paste_char(c,key,(80,490,850,910),.75);d=ImageDraw.Draw(c);text(d,(56,135),jtitle,105,'#e9e0cb',True);text(d,(65,290),'灯りを、ひとつ。',30,accent,True)
 else:
  for j in range(0,1600,36):line(d,[(j-500,280),(j-950,1350)],'#b6c7d1',2)
  d.rectangle((85,340,920,1330),outline='#839aa8',width=3);paste_char(c,key,(50,340,855,1040),.68)
  d=ImageDraw.Draw(c);text(d,(55,135),jtitle,110,accent,True);text(d,(65,282),'きみに届くまで。',30,accent,True)
 d=ImageDraw.Draw(c);d.rectangle((0,1360,1000,1500),fill=bg)
 text(d,(55,1380),eng,28,ink,en=True,bold=True)
 text(d,(55,1435),'HONBAKO SAMPLE STORY · CHARACTER ILLUSTRATION: WATAOBI',17,ink,en=True)
 c.convert('RGB').save(OUT/f'cover-{i+1:02}.jpg',quality=96,subsampling=0)

# Original short comic: unambiguous kana, vertical bubbles and independently
# composed panels. Characters are hand-illustrated by Wataobi, not generated.
def panel(c,rect):
 x,y,w,h=rect;d=ImageDraw.Draw(c);d.rectangle((x,y,x+w,y+h),fill='white',outline='#1b1b1b',width=4)
def bubble(c,rect,columns,size=38):
 x,y,w,h=rect;d=ImageDraw.Draw(c);d.ellipse((x,y,x+w,y+h),fill='white',outline='#222',width=3)
 for j,col in enumerate(columns):vertical(d,x+w-35-size-j*(size+12),y+35,col,size,'#111',False,step=size+5)
def comic(n):
 c=Image.new('RGBA',(1000,1500),'#fff');d=ImageDraw.Draw(c)
 if n==1:
  panel(c,(40,45,920,320));city(d,(45,80,910,280),'#777')
  line(d,[(40,315),(960,315)],'#222',4);line(d,[(40,340),(960,340)],'#222',2)
  d.rectangle((70,70,315,158),fill='white',outline='#222',width=2);text(d,(88,84),'午後十一時四十分',27,'#111')
  panel(c,(40,390,435,480));p=Image.new('RGBA',(435,480),'white');tone(p,(0,0,435,480),'#bbb',11);paste_char(p,'ren',(10,30,425,500),.5,mono=True);c.alpha_composite(p,(40,390))
  panel(c,(500,390,460,480));p=Image.new('RGBA',(452,472),'white');paste_char(p,'akari',(-100,10,550,510),.48,mono=True);c.alpha_composite(p,(504,394))
  bubble(c,(325,425,135,330),['まだ','こないね。'],31);bubble(c,(785,410,155,360),['だいじょうぶ。','すぐくるよ。'],30)
  panel(c,(40,900,920,550));p=Image.new('RGBA',(912,542),'white');tone(p,(0,0,912,542),'#b6b6b6',12);paste_char(p,'akari',(65,-10,740,1050),.62,mono=True);c.alpha_composite(p,(44,904))
  bubble(c,(710,955,210,395),['いっしょに','まっていよう。'],38)
 else:
  panel(c,(40,45,920,500));p=Image.new('RGBA',(912,492),'white');city(ImageDraw.Draw(p),(0,100,912,392),'#777');paste_char(p,'ren',(20,-10,550,900),.58,expression=1,mono=True);c.alpha_composite(p,(44,49));bubble(c,(710,80,205,395),['きょうも','いいひだった。'],38)
  panel(c,(40,575,440,375));p=Image.new('RGBA',(432,367),'white');paste_char(p,'akari',(-50,0,560,800),.55,expression=1,mono=True);c.alpha_composite(p,(44,579));bubble(c,(325,600,120,310),['うん。','またあした。'],29)
  panel(c,(505,575,455,375));d=ImageDraw.Draw(c)
  for x in range(525,940,60):line(d,[(x,610),(x,940)],'#555',2)
  line(d,[(515,790),(948,710)],'#222',5);text(d,(540,650),'終電',63,'#111',True)
  panel(c,(40,980,920,470));city(ImageDraw.Draw(c),(45,1020,910,425),'#555');d=ImageDraw.Draw(c);d.ellipse((660,1020,815,1175),fill='white',outline='#222',width=2)
 d=ImageDraw.Draw(c);text(d,(40,1463),'HONBAKO SAMPLE STORY  /  CHARACTER ILLUSTRATION: WATAOBI',14,'#555',en=True)
 c.convert('RGB').save(OUT/f'page-{n:02}.jpg',quality=97,subsampling=0)
for n in [1,2]:comic(n)
books=[{'key':f'book-{i+1:03}','title':en.title(),'japaneseTitle':jp,'volume':1,'author':'Honbako · Character art by Wataobi','cover':f'cover-{i+1:02}.jpg','pages':['page-01.jpg','page-02.jpg'] if i==0 else [f'cover-{i+1:02}.jpg']} for i,(_,jp,en,*_) in enumerate(BOOKS)]
(OUT/'manifest.json').write_text(json.dumps({'title':'Honbako sample stories','author':'Honbako · Character art by Wataobi','books':books,'usage':'Original marketing sample-story compositions with licensed, hand-drawn Wataobi character illustrations. Not a catalog included with the app.','aiGenerated':False},ensure_ascii=False,indent=2))
sh=Image.new('RGB',(1800,1520),'#f5f5f7');d=ImageDraw.Draw(sh)
for i,b in enumerate(books):
 im=Image.open(OUT/b['cover']);im.thumbnail((270,405));sh.paste(im,(35+(i%4)*295,40+(i//4)*455));text(d,(35+(i%4)*295,450+(i//4)*455),b['title'],13,'#555',en=True)
for n in [1,2]:
 im=Image.open(OUT/f'page-{n:02}.jpg');im.thumbnail((530,795));sh.paste(im,(1230,40+(n-1)*730))
text(d,(35,1010),'Distinct Honbako sample stories.',36,'#1d1d1f',en=True,bold=True)
text(d,(35,1070),'Japanese illustration. Different casts, genres and cover designs.',26,'#6e6e73',en=True)
text(d,(35,1120),'Character illustrations: Wataobi / わたおび',22,'#6e6e73',en=False)
text(d,(35,1170),'No image generation. No manga copied from the reference app.',22,'#6e6e73',en=True)
sh.save(ROOT/'distinct-manga-direction.jpg',quality=96)
print('Rendered eight distinct cover concepts and two original sample comic pages.')
