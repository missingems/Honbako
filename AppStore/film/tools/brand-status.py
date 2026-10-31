"""Writes exports/website/film-brand-aligned.json: what the film took from the app's branding, the
state of its renders (read from the files themselves) and the conflicts that remain.

usage: python3 tools/brand-status.py
"""
import hashlib
import json
import subprocess
from datetime import date
from pathlib import Path

root = Path(__file__).resolve().parent.parent
repo = root.parent.parent


def probe(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-count_frames', '-show_entries',
                          'stream=codec_type,codec_name,width,height,avg_frame_rate,nb_read_frames:format=duration',
                          '-of', 'json', str(path)], capture_output=True, text=True, check=True)
    info = json.loads(out.stdout)
    video = next(s for s in info['streams'] if s['codec_type'] == 'video')
    audio = next((s for s in info['streams'] if s['codec_type'] == 'audio'), None)
    return {
        'file': str(path.relative_to(root)),
        'bytes': path.stat().st_size,
        'size': [video['width'], video['height']],
        'fps': video['avg_frame_rate'],
        'frames': int(video['nb_read_frames']),
        'duration_s': round(float(info['format']['duration']), 3),
        'video': video['codec_name'],
        'audio': audio['codec_name'] if audio else None,
    }


def still(path):
    return {'file': str(path.relative_to(root)), 'bytes': path.stat().st_size}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


renders = root / 'renders'
films = [probe(renders / f'honbako-film-{f}.mp4') for f in ('1920x1080', '1080x1920')]
previews = [probe(renders / 'preview' / f'honbako-film-{f}-preview.mp4') for f in ('1920x1080', '1080x1920')]
icon, canonical = root / 'assets/captures/icon.png', repo / 'AppStore/assets/AppIcon-1024.png'
providers = {p: sha(root / f'assets/captures/provider-{p}.png') == sha(repo / f'AppStore/design-assets/provider-icons/{p}.png')
             for p in ('chatgpt', 'claude', 'grok')}

# The paper port: the JS tile must equal the app's Swift tile (checked against a compiled copy of
# ReaderPaperTexture.tileData; that hash is recorded here and recomputed from src/paper.js).
paper_hash = subprocess.run(['node', '-e', "const fs=require('fs');require('vm').runInThisContext(fs.readFileSync(process.argv[1],'utf8'));"
                             "process.stdout.write(require('crypto').createHash('sha256').update(Buffer.from(HonbakoPaper.tileAlpha())).digest('hex'))",
                             str(root / 'src/paper.js')], capture_output=True, text=True, check=True).stdout
SWIFT_TILE_SHA256 = 'c606b11fa9c4ebbf401edefbddec2e96aca555172b1328d39bd65a784b89af1f'

status = {
    'owner': 'AppStore/film (Claude session). The website session reads this file and doesn’t edit it.',
    'date': date.today().isoformat(),
    'revision': 'system-font cut, after Jun’s review: “Feels too much labels. Remove resume play. Don’t use serif. '
                'Paper texture like the app dune theme, apple esque, system font.”',
    'summary': 'The 45-second film is now on the app’s own paper grain, in the system font and the app’s dune palette, with the '
               'technical furniture removed. Each moment leads with the genuine app UI on Apple’s Duo model, one headline and a '
               'line or two of copy. The app icon, provider icons, Pro tags, account and manga disclosures and credits stay.',
    'source': {
        'film': 'src/film.js',
        'paper': 'src/paper.js (port of the app’s paper stock)',
        'page': 'src/index.html',
        'shot_list': 'shots.json',
        'readme': 'README.md',
        'score': 'tools/music.py (comments only; the audio is unchanged)',
        'status_file': 'tools/brand-status.py writes this file',
    },
    'applied': {
        'type': {
            'family': 'Apple system font: SF Pro Display for headlines (semibold) and copy (regular), SF Pro Text for small text, '
                      'Hiragino Sans for Japanese. No Baskerville, Mincho or monospaced labels remain.',
        },
        'paper': {
            'source': ['Aidoku/Features/Reader/Page/ReaderPaperTexture.swift (tileData, strength .light, seed 0xA1D02026)',
                       'Aidoku/Features/Bookshelf/SumiPaperSurface.swift (inkTile alpha remap)',
                       'Aidoku/Features/Bookshelf/Services/HonbakoPaperStock.swift (base colour, grain at 0.6)'],
            'port': 'src/paper.js',
            'tile_alpha_sha256': paper_hash,
            'matches_swift': paper_hash == SWIFT_TILE_SHA256,
            'scale': '256 px tile for 128 pt, drawn one tile pixel per film pixel (as on a 2× display).',
            'page': '#F5F0E6 with grain (measured mean about #F4EFE5)',
            'card': '#FFFCF6 card stock, rounded, with a soft warm shadow instead of a rule',
        },
        'palette': {'paper': '#F5F0E6', 'card': '#FFFCF6', 'ink': '#15140F', 'dune': '#806344',
                    'muted': '#5C574E', 'faint': '#78746B',
                    'dune_use': 'Honbako Pro capsules, the reader’s chat bubble (white text), taps, the AI’s mark on the page and its leader.'},
        'removed': ['Frame rules and crop marks', 'Running head (HONBAKO 本箱) and section numbers/names',
                    'Registration crosses', 'Device dimension lines and leaders (84.1 / 117.8 / 164.6 mm, INNER DISPLAY, IPHONE DUO)',
                    'Scale bar', 'Small caps feature labels (LOCAL FILES, MCP SERVER, ROMAJI, …) and IN YOUR AI APP / ANNOTATED BY YOUR AI',
                    'The vermilion 本箱 seal (it was a Mincho editorial mark)', 'The paper vignette'],
        'kept': [
            'Canonical app icon on the title and end cards',
            'ChatGPT, Claude and Grok App Store icons, with “Names and icons belong to their owners. Honbako isn’t affiliated with them.”',
            'Honbako Pro tags: Japanese reading help, Duo cover display, Remote MCP for cloud AI apps',
            'End card: “Some features require Honbako Pro. Compatible AI-provider account required.”',
            'Footnotes: AI-provider account separate and requests sync while open; Honbako doesn’t provide manga; cover display camera use',
            '“Illustrative demonstration” on the AI chat cards',
            'Manga credit on every frame that shows it and on the end card',
            'Genuine captures and recordings on Apple’s Duo model',
        ],
        'icon_matches_canonical': sha(icon) == sha(canonical),
        'provider_icons_match_design_assets': providers,
        'resume_widget': 'The genuine Resume widget capture stays, including its own ▶ Resume button, which is app UI. '
                         'Jun’s “remove resume play” was about the website’s playback button; the film has none.',
    },
    'render': {
        'films': films,
        'previews': previews,
        'posters': [still(renders / 'poster-1920x1080.png'), still(renders / 'poster-1080x1920.png')],
        'storyboard': still(renders / 'storyboard.jpg'),
        'rebuild': 'npm run render && npm run poster && npm run storyboard (previews: ffmpeg at 2.5 Mb/s from the masters)',
    },
    'recoverable': {
        'branded_editorial_cut': 'src/brand-aligned/ (film.js, index.html, shots.json, its film-brand-aligned.json) and renders/brand-aligned/',
        'monochrome_cut': 'src/treatise-mono/ and renders/treatise-mono/',
        'product_cut': 'src/product-cut/ and renders/product-cut/',
        'how': 'Copy a backup’s film.js and index.html over src/ and run npm run render. (The branded cut needs no paper.js.)',
    },
    'remaining_conflicts': [
        {'item': 'AI chat card mark', 'state': 'Neutral “Your AI” mark, not a provider icon.',
         'why': 'The chat text was written for the film; a provider logo would suggest that provider wrote it.'},
        {'item': 'Manga in the film', 'state': 'ブラックジャックによろしく by 佐藤秀峰, credited. Website and shared demos use only the original sample story.',
         'why': 'User decision for the film. Don’t reuse film frames on the website.'},
        {'item': '“Made for iPhone Duo.” wording', 'state': 'Unchanged; “Designed for iPhone Duo.” is still the user’s call.', 'why': 'Copy choice.'},
    ],
    'not_done': [
        'Nothing is committed to git.',
        'No changes to the app, the website or App Store Connect; Apple review stays on hold.',
        'The score was not re-rendered and hasn’t been auditioned by ear.',
    ],
}

out = root / 'exports/website/film-brand-aligned.json'
out.write_text(json.dumps(status, ensure_ascii=False, indent=2) + '\n')
print('wrote', out)
