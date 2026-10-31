// Still renders of the open iPhone Duo with a given inner-display capture, for the website's feature rows.
//
//   node tools/duo-stills.mjs <out-dir> name=/path/to/inner-2853x2007.png [name=…]
//
// Each capture goes through clean-fold.py (the simulator's fold shading only), onto Apple's Duo model
// (duo-render, Dark finish), open flat and facing the camera at its true proportions. Writes
// <name>.png with a transparent background, trimmed to the device plus a soft shadow.
import { execFileSync, spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { copyFileSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const [outDir, ...pairs] = process.argv.slice(2);
if (!outDir || !pairs.length) throw new Error('usage: node tools/duo-stills.mjs <out-dir> name=capture.png …');
const W = 1600, H = 1200, DEVICE_W = 1400;
const work = join(root, 'review/duo-stills-work');
rmSync(work, { recursive: true, force: true });
mkdirSync(work, { recursive: true });
mkdirSync(outDir, { recursive: true });

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

for (const pair of pairs) {
  const [name, capture] = pair.split('=');
  const inner = join(work, `${name}-inner.png`);
  copyFileSync(capture, inner);
  execFileSync('python3', [join(root, 'tools/clean-fold.py'), inner], { stdio: 'ignore' });
  const layer = join(work, `${name}-layer.png`);
  await render({ out: layer, w: W, h: H, k: DEVICE_W / 164.6, cam: { x: W / 2, y: H / 2, zoom: 1, fx: 0, fy: 0 },
    hinge: 180, yaw: 0, pitch: 0, explode: 0, inner, cover: 'asleep' });
  // Trim to the device, then add a soft warm shadow under it on a transparent ground.
  execFileSync('python3', ['-c', `
from PIL import Image, ImageFilter
l = Image.open('${layer}').convert('RGBA'); box = l.getchannel('A').getbbox(); d = l.crop(box)
pad = 70; w, h = d.size
out = Image.new('RGBA', (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
s = Image.new('L', out.size, 0); s.paste(d.getchannel('A'), (pad, pad + 22))
s = s.filter(ImageFilter.GaussianBlur(28)).point(lambda v: int(v * 0.30))
shadow = Image.new('RGBA', out.size, (60, 45, 25, 0)); shadow.putalpha(s)
out.alpha_composite(shadow); out.alpha_composite(d, (pad, pad))
out.save('${join(outDir, name + '.png')}')
print('${name}', out.size)
`], { stdio: 'inherit' });
}
proc.stdin.end();
rmSync(work, { recursive: true, force: true });
