// A short, silent, looping iPhone Duo demo for the website: the real device model with a genuine
// screen recording of Honbako's native page turn on its inner display, centred on the app's paper.
//
//   node tools/website-demo.mjs      → exports/website/honbako-duo-page-turn.{mp4,webm} and poster
//
// The recording is assets/source/recordings/sample-curl.mov: the original Honbako sample story
// 星を待つ駅 (character art by Wataobi) in the Xcode 27.1 iPhone Duo simulator, read right to left.
// The clip starts and ends on the same still spread (one turn forward, one back), so it loops.
// Build tools/duo-render first (`npm run duo`).
import { execFileSync, spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { mkdirSync, readdirSync, rmSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const source = join(root, 'assets/source/recordings/sample-curl.mov');
const START = 14.0, DURATION = 7.95, FPS = 60;
const W = 1600, H = 1200;           // 4:3, the device centred with room around it
const DEVICE_W = 1180;              // the open device's width in px; never scaled per axis
const PAPER = '#F5F0E6';            // HonbakoPaper (light)

const out = join(root, 'exports/website');
const work = join(root, 'work/website');
const ff = (...args) => execFileSync('ffmpeg', ['-v', 'error', '-y', ...args], { stdio: 'inherit' });

rmSync(work, { recursive: true, force: true });
mkdirSync(join(work, 'screen'), { recursive: true });
mkdirSync(join(work, 'layer'), { recursive: true });
mkdirSync(out, { recursive: true });

// 1. The recording, resampled to constant 60 fps. ffmpeg applies the .mov's rotation, giving the
//    inner display's own 2852 × 2006; clean-fold removes the simulator's fold shading.
ff('-ss', String(START), '-t', String(DURATION), '-i', source, '-vf', `fps=${FPS}`, '-q:v', '2', join(work, 'screen/%04d.jpg'));
const screens = readdirSync(join(work, 'screen')).sort().map(f => join(work, 'screen', f));
execFileSync('python3', [join(root, 'tools/clean-fold.py'), ...screens], { stdio: 'ignore' });

// 2. The device, one layer per frame, straight on and flat, with the screen flush in the body.
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
for (let i = 0; i < screens.length; i++) {
  await render({
    out: join(work, 'layer', `${String(i + 1).padStart(4, '0')}.png`), w: W, h: H, k,
    cam: { x: W / 2, y: H / 2 - 20, zoom: 1, fx: 0, fy: 0 },
    hinge: 180, yaw: 0, pitch: 0, explode: 0, inner: screens[i], cover: 'asleep'
  });
}
proc.stdin.end();
console.log(screens.length, 'frames');

// 3. A soft shadow from the device's silhouette (the device doesn't move, so one is enough).
const shadow = join(work, 'shadow.png');
execFileSync('python3', ['-c', `
from PIL import Image, ImageFilter
a = Image.open('${join(work, 'layer/0001.png')}').getchannel('A')
s = Image.new('L', a.size, 0); s.paste(a, (0, 26))
s = s.filter(ImageFilter.GaussianBlur(34)).point(lambda v: int(v * 0.30))
out = Image.new('RGBA', a.size, (60, 45, 25, 0)); out.putalpha(s); out.save('${shadow}')
`]);

// 4. Composite on paper and encode: H.264 MP4 for Safari, VP9 WebM, and a poster.
const graph = `color=c=${PAPER}:s=${W}x${H}:r=${FPS}[bg];[bg][1]overlay=0:0[s];[s][0]overlay=0:0:format=auto,format=yuv420p`;
const layers = ['-framerate', String(FPS), '-i', join(work, 'layer/%04d.png'), '-i', shadow];
const mp4 = join(out, 'honbako-duo-page-turn.mp4');
ff(...layers, '-filter_complex', graph, '-frames:v', String(screens.length), '-an',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p',
  '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', '-movflags', '+faststart', mp4);
ff('-i', mp4, '-an', '-c:v', 'libvpx-vp9', '-b:v', '0', '-crf', '34', '-row-mt', '1', join(out, 'honbako-duo-page-turn.webm'));
ff(...layers, '-filter_complex', graph.replace(',format=yuv420p', ''), '-frames:v', '1', join(out, 'honbako-duo-page-turn-poster.png'));
ff('-i', join(out, 'honbako-duo-page-turn-poster.png'), '-q:v', '3', join(out, 'honbako-duo-page-turn-poster.jpg'));
rmSync(work, { recursive: true, force: true });
console.log('wrote', out);
