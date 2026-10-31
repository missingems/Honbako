// A short, silent, looping iPhone Duo demo of the book-fold pose and the outer-display cover, for the
// website: Apple's Duo model, part-folded like a book, swings round far enough to show Honbako's manga
// cover on its outer display, then swings back to the reading spread.
//
//   node tools/cover-demo.mjs                 → exports/website/honbako-duo-cover-mode.{mp4,webm}, poster, JSON
//   node tools/cover-demo.mjs --probe 0,90,150 → review/cover-probe/yaw-*.png, one still per yaw
//
// Inner display: the clean spread from assets/source/recordings/sample-curl.mov at 14.0 s (the
// original sample story 星を待つ駅, character art by Wataobi), the same frame the page-turn loop starts on.
// Outer display: assets/source/cover-showcase/outer-cover-display.png, drawn from the sample's own
// cover file with HonbakoCoverDisplayView's treatment (see the provenance JSON). Build duo-render first.
import { execFileSync, spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { mkdirSync, rmSync, existsSync, writeFileSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const W = 1600, H = 1200, FPS = 60;
export const POSE = {
  hinge: 118,              // degrees between the halves: a book held part-open
  yawFrom: 40,             // the reading spread, both pages in view
  yawTo: 245,              // round until the outer display faces the camera
  pitch: 8,                // a little from above, so the fold reads
  holdCover: 2.8,          // seconds held on the cover; the loop opens here
  holdSpread: 1.0,         // seconds held on the reading spread
  swing: 2.4,              // seconds for each swing
};
const DURATION = POSE.holdCover + POSE.holdSpread + 2 * POSE.swing;   // 8.6 s
const DEVICE_W = 1060;     // px for the device's 164.6 mm open width; never scaled per axis
const PAPER = '#F5F0E6';

const out = join(root, 'exports/website');
const work = join(root, 'review/cover-work');  // not work/: npm render cleanup removes that
const ff = (...args) => execFileSync('ffmpeg', ['-v', 'error', '-y', ...args], { stdio: 'inherit' });
const probe = process.argv.includes('--probe') ? process.argv[process.argv.indexOf('--probe') + 1].split(',').map(Number) : null;

rmSync(work, { recursive: true, force: true });
mkdirSync(join(work, 'layer'), { recursive: true });

// The inner spread: one genuine frame of the recording, with the simulator's fold shading removed.
const inner = join(work, 'inner.jpg');
ff('-ss', '14.0', '-i', join(root, 'assets/source/recordings/sample-curl.mov'), '-frames:v', '1', '-q:v', '2', inner);
execFileSync('python3', [join(root, 'tools/clean-fold.py'), inner], { stdio: 'ignore' });
const cover = join(root, 'assets/source/cover-showcase/outer-cover-display.png');

const bin = join(root, 'tools/duo-render/.build/release/duo-render');
if (!existsSync(bin)) throw new Error('duo-render is not built: run `npm run duo`.');
const DEVELOPER_DIR = process.env.DEVELOPER_DIR ?? '/Applications/Xcode 27.1.app/Contents/Developer';
const proc = spawn(bin, [], { env: { ...process.env, DEVELOPER_DIR, DUO_FINISH: process.env.DUO_FINISH ?? 'Dark' }, stdio: ['pipe', 'pipe', 'inherit'] });
const lines = createInterface({ input: proc.stdout });
const waiting = [];
let ready;
const isReady = new Promise(r => { ready = r; });
lines.on('line', line => {
  if (line === 'ready') return ready();
  const next = waiting.shift();
  line.startsWith('ok') ? next.resolve() : next.reject(new Error(line));
});
await isReady;
const render = request => new Promise((resolve, reject) => { waiting.push({ resolve, reject }); proc.stdin.write(JSON.stringify(request) + '\n'); });
const k = DEVICE_W / 164.6;
const pose = yaw => ({ w: W, h: H, k, cam: { x: W / 2, y: H / 2 - 10, zoom: 1, fx: 0, fy: 0 },
  hinge: POSE.hinge, yaw, pitch: POSE.pitch, explode: 0, inner, cover });

// Shadow and composite on the app's paper (flat #F5F0E6, like the page-turn loop).
const shadowed = (layer, dest) => execFileSync('python3', ['-c', `
from PIL import Image, ImageFilter
l = Image.open('${layer}').convert('RGBA'); a = l.getchannel('A')
s = Image.new('L', a.size, 0); s.paste(a, (0, 24))
s = s.filter(ImageFilter.GaussianBlur(30)).point(lambda v: int(v * 0.28))
bg = Image.new('RGBA', a.size, '${PAPER}')
sh = Image.new('RGBA', a.size, (60, 45, 25, 0)); sh.putalpha(s)
bg.alpha_composite(sh); bg.alpha_composite(l); bg.convert('RGB').save('${dest}')
`]);

if (probe) {
  const dir = join(root, 'review/cover-probe');
  mkdirSync(dir, { recursive: true });
  for (const yaw of probe) {
    const layer = join(work, `probe-${yaw}.png`);
    await render({ ...pose(yaw), out: layer });
    shadowed(layer, join(dir, `yaw-${yaw}.png`));
  }
  proc.stdin.end();
  rmSync(work, { recursive: true, force: true });
  console.log('probe stills →', dir);
  process.exit(0);
}

// The loop: hold on the cover, swing to the reading side, hold, swing back. It opens on the cover so
// the section shows cover mode at once. Eased, so frame 0 and the last frame meet without a jump.
const ease = u => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2);
const yawAt = t => {
  const { holdCover, holdSpread, swing, yawFrom, yawTo } = POSE;
  if (t < holdCover) return yawTo;
  if (t < holdCover + swing) return yawTo + (yawFrom - yawTo) * ease((t - holdCover) / swing);
  if (t < holdCover + swing + holdSpread) return yawFrom;
  return yawFrom + (yawTo - yawFrom) * ease((t - holdCover - swing - holdSpread) / swing);
};
const frames = Math.round(DURATION * FPS);
for (let i = 0; i < frames; i++) {
  await render({ ...pose(yawAt(i / FPS)), out: join(work, 'layer', `${String(i + 1).padStart(4, '0')}.png`) });
}
proc.stdin.end();

// The shadow moves with the device here, so composite per frame with ffmpeg's alpha from each layer.
const graph = `color=c=${PAPER}:s=${W}x${H}:r=${FPS}[bg];` +
  `[0]split[d][a];[a]alphaextract,pad=${W}:${H + 24}:0:24,crop=${W}:${H}:0:0,gblur=sigma=30,lutyuv=y=val*0.28[m];` +
  `color=c=0x3C2D19:s=${W}x${H}:r=${FPS}[sc];[sc][m]alphamerge[sh];[bg][sh]overlay=0:0[b2];[b2][d]overlay=0:0:format=auto,format=yuv420p`;
const layers = ['-framerate', String(FPS), '-i', join(work, 'layer/%04d.png')];
mkdirSync(out, { recursive: true });
const mp4 = join(out, 'honbako-duo-cover-mode.mp4');
ff(...layers, '-filter_complex', graph, '-frames:v', String(frames), '-an',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p',
  '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', '-movflags', '+faststart', mp4);
ff('-i', mp4, '-an', '-c:v', 'libvpx-vp9', '-b:v', '0', '-crf', '34', '-row-mt', '1', join(out, 'honbako-duo-cover-mode.webm'));
// Poster: the first frame, so the poster hands over to playback without a jump.
const posterFrame = 1;
shadowed(join(work, 'layer', `${String(posterFrame).padStart(4, '0')}.png`), join(out, 'honbako-duo-cover-mode-poster.png'));
ff('-i', join(out, 'honbako-duo-cover-mode-poster.png'), '-q:v', '3', join(out, 'honbako-duo-cover-mode-poster.jpg'));
rmSync(work, { recursive: true, force: true });
console.log('wrote', mp4, frames, 'frames', DURATION, 's');
