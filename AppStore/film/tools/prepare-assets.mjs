// Copies the genuine simulator captures and screen recordings into assets/ in the
// sizes the film reads. Sources come from CAPTURE_DIR (PNG screenshots) and
// RECORDING_DIR (simctl recordVideo .mov files); see README.md for how to make them.
import { execFileSync } from 'node:child_process';
import { mkdirSync, rmSync, readdirSync, existsSync, copyFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const captures = process.env.CAPTURE_DIR;
const recordings = process.env.RECORDING_DIR;
if (!captures || !recordings) {
  console.error('Set CAPTURE_DIR and RECORDING_DIR (see README.md).');
  process.exit(1);
}
const out = join(root, 'assets');
const ff = (...args) => execFileSync('ffmpeg', ['-v', 'error', '-y', ...args], { stdio: 'inherit' });

// Inner-display captures are 2853 × 2007 (951 × 669 pt at 3×); outer is 1398 × 2034.
const stills = {
  'library': 'library-bj-inner.png',
  'personal-server': 'personal-server-inner.png',
  'extensions': 'extensions-bj-inner.png',
  'mcp-before': 'mcp-permissions-before-inner.png',
  'mcp-after': 'mcp-permissions-after-inner.png',
  'reader-en': 'en23-plain-inner.png',
  'reader-en-annotated': 'en23-annotated-inner.png',
  'reader-ja': 'ja7-spread-inner.png',
  'reader-ja-romaji': 'ja7-romaji-on-inner.png',
  'reader-ja-phrase': 'ja7-phrase-inner.png',
  'outer-cover': 'cover-en-outer.png'
};
mkdirSync(join(out, 'captures'), { recursive: true });
for (const [name, file] of Object.entries(stills)) {
  ff('-i', join(captures, file), '-q:v', '2', join(out, 'captures', `${name}.jpg`));
}
// The simulator shades the fold in inner-display screenshots; the app doesn't draw it.
const inner = Object.keys(stills).filter(n => n !== 'outer-cover').map(n => join(out, 'captures', `${n}.jpg`));
execFileSync('python3', [join(root, 'tools/clean-fold.py'), ...inner], { stdio: 'inherit' });

// The genuine Resume widget from the build 68 review capture, the app icon and the AI apps' icons.
const repo = join(root, '..', '..');
ff('-i', join(repo, 'AppStore/review/build68/widgets-light.png'), '-vf', 'crop=712:340:48:534', join(out, 'captures', 'widget-resume.png'));
copyFileSync(join(repo, 'AppStore/assets/AppIcon-1024.png'), join(out, 'captures', 'icon.png'));
// The AI apps' own App Store icons (provenance in AppStore/design-assets/provider-icons/sources.json).
for (const id of ['chatgpt', 'claude', 'grok']) {
  copyFileSync(join(repo, `AppStore/design-assets/provider-icons/${id}.png`), join(out, 'captures', `provider-${id}.png`));
}

// Recordings are variable frame rate; resample to constant 60 fps frames.
// The .mov files carry a rotation matrix, which ffmpeg applies automatically.
const clips = [
  { name: 'curl', file: 'curl.mov', start: '38.9', duration: '1.9' },
  { name: 'perm', file: 'permission-toggle.mov' }
];
for (const clip of clips) {
  const dir = join(out, 'video', clip.name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const range = clip.start ? ['-ss', clip.start, '-t', clip.duration] : [];
  ff(...range, '-i', join(recordings, clip.file), '-vf', 'fps=60', '-q:v', '2', join(dir, '%04d.jpg'));
  const frames = readdirSync(dir).map(f => join(dir, f));
  execFileSync('python3', [join(root, 'tools/clean-fold.py'), ...frames], { stdio: 'ignore' });
  console.log(clip.name, frames.length, 'frames');
}
if (!existsSync(join(out, 'audio', 'score.wav'))) console.log('Next: npm run music');
