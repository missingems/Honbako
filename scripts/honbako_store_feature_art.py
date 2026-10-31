from pathlib import Path
from PIL import Image,ImageDraw
import os
ROOT=Path(__file__).resolve().parent.parent
NATIVE=ROOT/'AppStore/screenshot-captures/build77-features'
FRAMES=Path(os.environ.get('HONBAKO_APPLE_FRAMES','/Users/jun/Documents/Codex/2026-10-24/help-me-clone-x20/work/honbako/apple-frames'))
FONT='/Library/Fonts/SF-Pro-Display-'
JP=next(Path('/System/Library/Fonts').glob('* W6.ttc'))
CJK='/System/Library/Fonts/Hiragino Sans GB.ttc'
NAMES=['01-your-ai','02-page-coaching','03-japanese-guide','04-sources','05-icloud-library','06-ai-library-control']
STATES=['reader','coaching','japanese','sources','library','ai-permissions']
APERTURE={}
def framed(im,device):
    key='ipad-portrait' if device=='ipad' else 'iphone-large'
    bezel=Image.open(FRAMES/(key+'.png')).convert('RGBA')
    x,y,w,h=(118,124,2064,2752) if device=='ipad' else (75,66,1320,2868)
    assert im.size==(w,h)
    assert (FRAMES/'Apple Design Resources License.rtf').is_file()
    if key not in APERTURE:
        barrier=bezel.getchannel('A').point(lambda a:255 if a>=254 else 0)
        ImageDraw.floodfill(barrier,(bezel.width//2,bezel.height//2),128,thresh=0)
        APERTURE[key]=barrier.point(lambda a:255 if a==128 else 0)
    screen=Image.new('RGBA',bezel.size)
    screen.alpha_composite(im.convert('RGBA'),(x,y));screen.putalpha(APERTURE[key]);screen.alpha_composite(bezel)
    return screen
