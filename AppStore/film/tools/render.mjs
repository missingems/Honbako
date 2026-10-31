// Renders the film by stepping window.renderFrame(t) in headless Chromium and piping JPEG
// frames into ffmpeg with the score.
//
//   node tools/render.mjs --format landscape|portrait     full 45 s MP4 in renders/
//   node tools/render.mjs --stills [--format …]            PNG stills at cuts and midpoints in review/
//   node tools/render.mjs --stills --at 12.5,20.1          specific times
//   … --out review/storyboard                               another folder for the stills
//
// CHROMIUM may point at any Chromium/Chrome binary; it defaults to Playwright's cached build.
// The device is drawn by tools/duo-render (Swift, RealityKit) from Apple's iPhone Duo model in
// Xcode 27.1; build it first with `npm run duo`. DUO_FINISH picks the model's colour (Dark/Light).
import { createServer } from 'node:http';
import { createInterface } from 'node:readline';
import { readFile, mkdir, writeFile, rm } from 'node:fs/promises';
import { existsSync, readdirSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { join, dirname, extname, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { chromium } from 'playwright-core';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const flag = name => args.includes(name);
const value = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const FPS = 60, DURATION = 45;

const formats = value('--format') ? [value('--format')] : (flag('--stills') ? ['landscape', 'portrait'] : ['landscape']);

function findChromium() {
  if (process.env.CHROMIUM) return process.env.CHROMIUM;
  const cache = join(homedir(), 'Library/Caches/ms-playwright');
  const builds = existsSync(cache) ? readdirSync(cache).filter(d => /^chromium-\d+$/.test(d)).sort().reverse() : [];
  for (const b of builds) {
    const app = join(cache, b, 'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing');
    if (existsSync(app)) return app;
  }
  throw new Error('No Chromium found. Set CHROMIUM=/path/to/chrome or run `npx playwright install chromium`.');
}

// Serves the project at / and the system SF Pro fonts at /fonts (they can't ship in the repo).
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.jpg': 'image/jpeg', '.png': 'image/png', '.otf': 'font/otf', '.json': 'application/json' };
function serve() {
  const server = createServer(async (req, res) => {
    const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    const file = path.startsWith('/fonts/') ? join('/Library/Fonts', normalize(path.slice(7))) : join(root, normalize(path));
    try {
      const body = await readFile(file);
      res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' });
      res.end(body);
    } catch {
      res.writeHead(404);
      res.end();
    }
  });
  return new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const DEVELOPER_DIR = process.env.DEVELOPER_DIR ?? '/Applications/Xcode 27.1.app/Contents/Developer';

/** Starts duo-render; returns render(request) → Promise that resolves when the PNG is written. */
async function startDuo() {
  const bin = join(root, 'tools/duo-render/.build/release/duo-render');
  if (!existsSync(bin)) throw new Error('duo-render is not built: run `npm run duo`.');
  const proc = spawn(bin, [], { env: { ...process.env, DEVELOPER_DIR, DUO_FINISH: process.env.DUO_FINISH ?? 'Dark' }, stdio: ['pipe', 'pipe', 'inherit'] });
  const lines = createInterface({ input: proc.stdout });
  const waiting = [];
  let ready;
  const isReady = new Promise(r => { ready = r; });
  lines.on('line', line => {
    if (line === 'ready') return ready();
    const next = waiting.shift();
    if (!next) return console.error('duo-render:', line);
    line.startsWith('ok') ? next.resolve() : next.reject(new Error(`duo-render: ${line}`));
  });
  proc.on('exit', code => { for (const w of waiting) w.reject(new Error(`duo-render exited ${code}`)); });
  await isReady;
  return {
    render: request => new Promise((resolve, reject) => {
      waiting.push({ resolve, reject });
      proc.stdin.write(JSON.stringify(request) + '\n');
    }),
    stop: () => proc.stdin.end()
  };
}

// Cuts, act midpoints and the key beats inside acts.
const STILL_TIMES = [0.4, 2.2, 3.1, 4.0, 5.1, 6.1, 6.9, 7.6, 8.4, 10.0, 12.0, 13.6, 15.9, 17.6, 20.0, 20.9, 23.6,
  25.8, 27.0, 28.4, 30.2, 32.4, 34.0, 36.2, 36.9, 39.2, 40.9, 42.5, 44.6];

async function main() {
  const server = await serve();
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ executablePath: findChromium(), args: ['--force-color-profile=srgb', '--disable-gpu-vsync'] });
  try {
    for (const format of formats) {
      const portrait = format === 'portrait';
      const page = await browser.newPage({ viewport: portrait ? { width: 1080, height: 1920 } : { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
      page.on('pageerror', e => console.error('page error:', e.message));
      await page.goto(`${base}/src/index.html?format=${format}`);
      const info = await page.evaluate(() => window.filmReady);
      const duo = await startDuo();
      const work = join(root, 'work', format);
      await rm(work, { recursive: true, force: true });
      await mkdir(work, { recursive: true });
      let texture = 0, count = 0, innerPath = null;
      const covers = { asleep: 'asleep', 'outer-cover': join(root, 'assets/captures/outer-cover.jpg') };
      // One frame: the page paints the screens, duo-render draws the device, the page composites.
      const frame = async (t, type, quality) => {
        const { device, inner } = await page.evaluate(t => window.prepareFrame(t), t);
        let layerURL = null;
        if (device) {
          if (inner) {
            const previous = innerPath;
            innerPath = join(work, `inner-${++texture}.jpg`);
            await writeFile(innerPath, Buffer.from(inner.split(',')[1], 'base64'));
            if (previous) rm(previous, { force: true });
          }
          const out = join(work, 'layer.png');
          await duo.render({ out, w: info.width, h: info.height, k: info.k, cam: device.cam, hinge: device.hinge, yaw: device.yaw, pitch: device.pitch, explode: device.explode, inner: innerPath, cover: covers[device.cover] });
          layerURL = `/work/${format}/layer.png?n=${++count}`;
        }
        return page.evaluate(async ([t, layerURL, type, quality]) => {
          await window.renderFrame(t, layerURL);
          return document.getElementById('film').toDataURL(type, quality);
        }, [t, layerURL, type, quality]);
      };

      if (flag('--stills')) {
        const times = value('--at') ? value('--at').split(',').map(Number) : STILL_TIMES;
        const dir = value('--out') ? join(root, value('--out'), format) : join(root, 'review', format);
        await mkdir(dir, { recursive: true });
        for (const t of times) {
          const url = await frame(t, 'image/png');
          await writeFile(join(dir, `t${t.toFixed(2).padStart(5, '0')}.png`), Buffer.from(url.split(',')[1], 'base64'));
        }
        console.log(format, times.length, 'stills →', dir);
        duo.stop();
        continue;
      }

      await mkdir(join(root, 'renders'), { recursive: true });
      const out = join(root, 'renders', `honbako-film-${portrait ? '1080x1920' : '1920x1080'}.mp4`);
      const ff = spawn('ffmpeg', ['-v', 'error', '-y',
        '-f', 'image2pipe', '-c:v', 'mjpeg', '-framerate', String(FPS), '-i', '-',
        '-i', join(root, 'assets/audio/score.wav'),
        '-map', '0:v', '-map', '1:a',
        '-c:v', 'libx264', '-preset', 'slow', '-crf', '14', '-pix_fmt', 'yuv420p',
        '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
        '-c:a', 'aac', '-b:a', '256k', '-t', String(DURATION), '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
      const done = new Promise((resolve, reject) => ff.on('close', code => (code === 0 ? resolve() : reject(new Error(`ffmpeg exited ${code}`)))));
      const total = FPS * DURATION;
      const started = Date.now();
      for (let i = 0; i < total; i++) {
        const url = await frame(i / FPS, 'image/jpeg', 0.97);
        if (!ff.stdin.write(Buffer.from(url.split(',')[1], 'base64'))) await new Promise(r => ff.stdin.once('drain', r));
        if (i % 300 === 0) console.log(format, `${(i / FPS).toFixed(1)}s`, `${((Date.now() - started) / 1000).toFixed(0)}s elapsed`);
      }
      ff.stdin.end();
      await done;
      console.log('wrote', out);
      duo.stop();
      await page.close();
    }
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch(e => { console.error(e); process.exit(1); });
