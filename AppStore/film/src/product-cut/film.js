// Honbako — "Your manga. Your AI." A 45-second film drawn on one canvas.
//
// window.renderFrame(t) draws the frame at t seconds. It reads no clock and no unseeded
// randomness, so a given t always produces the same pixels; tools/render.mjs steps t at 60 fps.
// ?format=landscape (1920 × 1080) or ?format=portrait (1080 × 1920) recomposes the same timeline.
//
// Every screen inside the device is a genuine capture or screen recording of Honbako running
// in the iPhone Duo simulator (see README.md). The AI chat text in act 3 is written for the film
// and is labelled "Illustrative demonstration"; the annotation on the page is real app output.

const FORMAT = new URLSearchParams(location.search).get('format') === 'portrait' ? 'portrait' : 'landscape';
const PORTRAIT = FORMAT === 'portrait';
const W = PORTRAIT ? 1080 : 1920;
const H = PORTRAIT ? 1920 : 1080;
const canvas = document.getElementById('film');
canvas.width = W;
canvas.height = H;
const ctx = canvas.getContext('2d');

const C = {
  paper: '#F5F0E6', ink: '#211E19', accent: '#806344', card: '#FFFCF5',
  muted: '#5F574C', faint: '#978D80', glass: '#0F0F10'
};
const SANS = '"SFP", "Hiragino Sans", sans-serif';
const MINCHO = '"Hiragino Mincho ProN", "Hiragino Mincho Pro", serif';

// iPhone Duo, from Apple's published specs: open 164.6 × 117.8 mm, closed 84.1 × 117.8 mm.
// Inner 7.6" panel (2670 × 1878 px, rendered at 2853 × 2007), outer 5.4" panel (1398 × 2034 px).
const MM = {
  openW: 164.6, openH: 117.8, halfW: 82.3,
  innerW: 157.9, innerH: 111.1, outerW: 77.7, outerH: 113.0,
  bodyR: 10, innerR: 6.5, outerR: 7.5
};
const K = 960 / MM.openW; // px per mm; the open device is 960 px wide in both formats

const LAYOUT = PORTRAIT ? {
  device: { x: 540, y: 1112 },
  col: { x: 90, w: 900 },
  kickerY: 196, headY: 250, head: 78, sub: 34, foot: 23,
  chat: { x: 90, w: 900, top: 168, bottom: 720, size: 31 },
  footY: 1560, creditY: 1868
} : {
  device: { x: 1300, y: 548 },
  col: { x: 128, w: 610 },
  kickerY: 352, headY: 400, head: 68, sub: 29, foot: 21,
  chat: { x: 128, w: 610, top: 300, bottom: 930, size: 28 },
  footY: 930, creditY: 1040
};

// ---------- math ----------
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, u) => a + (b - a) * u;
const prog = (t, a, b) => clamp((t - a) / (b - a));
const ease = {
  inOut: u => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2),
  out: u => 1 - Math.pow(1 - u, 3),
  in: u => u * u * u,
  sine: u => -(Math.cos(Math.PI * u) - 1) / 2
};
/** Visible between a and b, fading in over fi and out over fo. */
const win = (t, a, b, fi = 0.45, fo = 0.4) => Math.min(ease.out(prog(t, a, a + fi)), 1 - ease.in(prog(t, b - fo, b)));

// ---------- assets ----------
const A = {};
const loadImage = src => new Promise((resolve, reject) => {
  const img = new Image();
  img.onload = () => img.decode().then(() => resolve(img), () => resolve(img));
  img.onerror = () => reject(new Error(`missing ${src}`));
  img.src = src;
});
const frameCache = new Map();
async function clipFrame(clip, index) {
  const key = `${clip}/${index}`;
  if (!frameCache.has(key)) {
    frameCache.set(key, await loadImage(`../assets/video/${clip}/${String(index).padStart(4, '0')}.jpg`));
    if (frameCache.size > 12) frameCache.delete(frameCache.keys().next().value);
  }
  return frameCache.get(key);
}

async function load() {
  const weights = { 400: 'Regular', 500: 'Medium', 600: 'Semibold', 700: 'Bold' };
  await Promise.all(Object.entries(weights).map(async ([weight, name]) => {
    const face = new FontFace('SFP', `url(/fonts/SF-Pro-Display-${name}.otf)`, { weight });
    document.fonts.add(await face.load());
  }));
  const stills = ['library', 'personal-server', 'extensions', 'reader-en', 'reader-en-annotated',
    'reader-ja', 'reader-ja-romaji', 'reader-ja-phrase', 'outer-cover'];
  await Promise.all(stills.map(async name => { A[name] = await loadImage(`../assets/captures/${name}.jpg`); }));
  A.widget = await loadImage('../assets/captures/widget-resume.png');
  A.icon = await loadImage('../assets/captures/icon.png');
  // Fonts must be ready before the first measured line; draw once off-canvas to warm them.
  ctx.font = `600 20px ${SANS}`;
  ctx.fillText('本箱 Honbako', -100, -100);
  ctx.font = `600 20px ${MINCHO}`;
  ctx.fillText('本箱', -100, -100);
  A.grain = makeGrain();
}

// Paper grain from a seeded generator (mulberry32), made once.
function makeGrain() {
  let seed = 0x5eed810;
  const rand = () => {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let r = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
  const g = document.createElement('canvas');
  g.width = 512; g.height = 512;
  const c = g.getContext('2d');
  const data = c.createImageData(512, 512);
  for (let i = 0; i < data.data.length; i += 4) {
    const v = 128 + (rand() - 0.5) * 60;
    data.data[i] = v; data.data[i + 1] = v * 0.97; data.data[i + 2] = v * 0.9; data.data[i + 3] = 14;
  }
  c.putImageData(data, 0, 0);
  return g;
}

// ---------- drawing primitives ----------
function rr(c, x, y, w, h, r) { c.beginPath(); c.roundRect(x, y, w, h, r); }

function wrap(c, str, maxW) {
  const out = [];
  for (const para of str.split('\n')) {
    const words = para.split(' ');
    let line = '';
    for (const word of words) {
      const next = line ? `${line} ${word}` : word;
      if (c.measureText(next).width > maxW && line) { out.push(line); line = word; } else line = next;
    }
    out.push(line);
  }
  return out;
}

/** Draws wrapped text with its top at y; returns the block height. */
function text(c, str, x, y, o) {
  const { size, weight = 600, color = C.ink, alpha = 1, maxW = 10000, lh = 1.16, align = 'left', family = SANS, tracking = 0, chars = Infinity } = o;
  c.save();
  c.globalAlpha *= alpha;
  c.font = `${weight} ${size}px ${family}`;
  c.letterSpacing = `${tracking}px`;
  c.fillStyle = color;
  c.textAlign = align;
  c.textBaseline = 'alphabetic';
  const lines = wrap(c, str, maxW);
  let shown = 0;
  lines.forEach((line, i) => {
    let part = line;
    if (chars !== Infinity) {
      part = line.slice(0, Math.max(0, chars - shown));
      shown += line.length + 1;
    }
    if (part) c.fillText(part, x, y + size * 0.92 + i * size * lh);
  });
  c.restore();
  return lines.length * size * lh;
}

function proTag(c, x, y, alpha, scale = 1) {
  if (alpha <= 0) return;
  c.save();
  c.globalAlpha *= alpha;
  c.font = `600 ${Math.round(17 * scale)}px ${SANS}`;
  c.letterSpacing = `${1.2 * scale}px`;
  const label = 'HONBAKO PRO';
  const w = c.measureText(label).width + 28 * scale, h = 32 * scale;
  rr(c, x, y, w, h, h / 2);
  c.fillStyle = C.accent;
  c.fill();
  c.fillStyle = C.card;
  c.textBaseline = 'middle';
  c.fillText(label, x + 14 * scale, y + h / 2 + 1);
  c.restore();
}

// ---------- the device ----------
// The device itself is Apple's iPhone Duo model, rendered by tools/duo-render (RealityKit) from
// the pose, turn and camera that deviceState(t) gives. This page paints its screens and the rest.
const INNER_PX = { w: 2853, h: 2007 };

/** The inner display's rectangle in device px (zoom 1), centred on the open device. */
function screenRect() {
  const w = MM.innerW * K, h = MM.innerH * K;
  return { x: -w / 2, y: -h / 2, w, h };
}

// ---------- scene state ----------
const READER_FOCUS = { x: 0.86, y: 0.46 };   // vertical dialogue on the right page of Vol. 7
const WORD = { x: 0.912, y: 0.47 };          // 実験台じゃない, the phrase tapped in the capture
const POPUP = { x: 0.705, y: 0.56 };         // centre of the "Read This Phrase" panel
const ANNOTATION = { x: 0.15, y: 0.48, w: 0.25, h: 0.177 }; // honbako_annotate_page box, in screen units

function screenPoint(n) {
  const s = screenRect();
  return { x: s.x + n.x * s.w, y: s.y + n.y * s.h };
}

const PERM_TOGGLE = { x: 0.775, y: 0.53 };    // "Read Reading History and Progress" switch in the recording

function camera(t) {
  const D = LAYOUT.device;
  const base = { x: D.x, y: D.y, zoom: 1, fx: 0, fy: 0 };
  const on = (zoom, n, o = {}) => { const p = screenPoint(n); return { x: D.x, y: D.y, ...o, zoom, fx: o.fx ?? p.x, fy: p.y }; };
  const half = MM.openW * K / 2;
  // The Japanese push-in keeps the device's right edge on the frame edge, so the page fills it.
  const pushZoom = PORTRAIT ? 2.6 : 2.8;
  const push = on(pushZoom, READER_FOCUS, { x: W / 2, y: PORTRAIT ? 1000 : H / 2, fx: half - (W / 2) / pushZoom });
  const popup = PORTRAIT ? on(2.3, POPUP, { x: W / 2, y: 990 }) : on(2.0, POPUP, { x: W / 2, y: H / 2 - 6, fx: 0 });
  const keys = [
    [0, { ...base, zoom: 1.05 }], [2.7, base],
    [5.0, base], [12.7, on(1.1, { x: 0.5, y: 0.42 })], [13.3, base],
    [19.85, base], [20.55, on(PORTRAIT ? 1.25 : 1.3, { x: 0.3, y: 0.52 })], [21.55, on(PORTRAIT ? 1.25 : 1.3, { x: 0.3, y: 0.52 })],
    [22.1, on(PORTRAIT ? 1.08 : 1.15, { x: 0.55, y: 0.6 })], [24.7, on(PORTRAIT ? 1.08 : 1.15, { x: 0.55, y: 0.6 })], [25.25, base],
    [26.3, base], [28.1, push], [28.95, push], [29.65, popup], [31.8, popup], [32.7, base],
    [37.6, base], [38.4, { ...base, zoom: 0.86 }]
  ];
  let i = keys.findIndex(k => k[0] > t);
  if (i === -1) return keys[keys.length - 1][1];
  if (i === 0) return keys[0][1];
  const [t0, a] = keys[i - 1], [t1, b] = keys[i];
  const u = ease.inOut(prog(t, t0, t1));
  return { x: lerp(a.x, b.x, u), y: lerp(a.y, b.y, u), zoom: lerp(a.zoom, b.zoom, u), fx: lerp(a.fx, b.fx, u), fy: lerp(a.fy, b.fy, u) };
}

/**
 * What the inner display shows at t: { key, paint(c, w, h) }. Equal keys paint equal pixels, so
 * the renderer only receives a new texture when the key changes.
 */
function innerScreen(t, frames) {
  const S = (key, paint) => ({ key, paint });
  const draw = (img, name) => S(name, (c, w, h) => c.drawImage(img, 0, 0, w, h));
  // A short navigation push between Settings screens, like the app's own.
  const push = ([from, a], [to, b], t0) => {
    const u = ease.inOut(prog(t, t0, t0 + 0.42));
    return S(`${a}>${b}:${u.toFixed(4)}`, (c, w, h) => {
      c.drawImage(from, -u * w * 0.3, 0, w, h);
      c.fillStyle = `rgba(0,0,0,${0.12 * u})`;
      c.fillRect(0, 0, w, h);
      c.drawImage(to, (1 - u) * w, 0, w, h);
    });
  };
  const fade = ([from, a], [to, b], t0, d = 0.35) => {
    const u = ease.sine(prog(t, t0, t0 + d));
    return S(`${a}~${b}:${u.toFixed(4)}`, (c, w, h) => {
      c.drawImage(from, 0, 0, w, h);
      c.globalAlpha = u;
      c.drawImage(to, 0, 0, w, h);
      c.globalAlpha = 1;
    });
  };
  const img = name => [A[name], name];
  const perm = () => [frames.perm, `perm${permIndex(t)}`];
  if (t < 7.6) return draw(A.library, 'library');
  if (t < 10.0) return push(img('library'), img('personal-server'), 7.6);
  if (t < 13.0) return push(img('personal-server'), img('extensions'), 10.0);
  if (t < 13.35) return fade(img('extensions'), img('reader-en'), 13.0);
  if (t < 21.8) return fade(img('reader-en'), img('reader-en-annotated'), 19.95, 0.45);
  if (t < 25.0) return fade(img('reader-en-annotated'), perm(), 21.8, 0.3);
  if (t < 28.7) {
    // Romaji appear with a wipe that follows the right-to-left reading direction.
    const base = t < 25.35 ? fade(perm(), img('reader-ja'), 25.0) : draw(A['reader-ja'], 'reader-ja');
    const u = ease.inOut(prog(t, 25.7, 26.9));
    return S(`${base.key}|wipe:${u.toFixed(4)}`, (c, w, h) => {
      base.paint(c, w, h);
      if (u <= 0) return;
      const edge = w * (1 - u);
      c.save();
      c.beginPath();
      c.rect(edge, 0, w * u, h);
      c.clip();
      c.drawImage(A['reader-ja-romaji'], 0, 0, w, h);
      c.restore();
      if (u < 1) {
        c.fillStyle = 'rgba(128,99,68,0.55)';
        c.fillRect(edge - 4, 0, 8, h);
      }
    });
  }
  if (t < 33.0) return fade(img('reader-ja-romaji'), img('reader-ja-phrase'), 28.7, 0.3);
  if (t < 33.3) {
    const u = 1 - ease.sine(prog(t, 33.0, 33.3));
    return S(`curl${curlIndex(t)}~phrase:${u.toFixed(4)}`, (c, w, h) => {
      c.drawImage(frames.curl, 0, 0, w, h);
      c.globalAlpha = u;
      c.drawImage(A['reader-ja-phrase'], 0, 0, w, h);
      c.globalAlpha = 1;
    });
  }
  return draw(frames.curl, `curl${curlIndex(t)}`);
}

/** Moments drawn onto the screen itself: the annotation pulse and the two taps. */
function screenOverlays(t) {
  const marks = [];
  if (t > 20.1 && t < 21.6) {
    const u = prog(t, 20.1, 21.4);
    marks.push((c, w, h) => {
      const sx = w / screenRect().w, grow = ease.out(u) * 18 * sx;
      c.strokeStyle = `rgba(232,184,40,${0.7 * (1 - u)})`;
      c.lineWidth = 3 * sx;
      rr(c, ANNOTATION.x * w - grow, ANNOTATION.y * h - grow, ANNOTATION.w * w + grow * 2, ANNOTATION.h * h + grow * 2, 6 * sx + grow);
      c.stroke();
    });
  }
  // The permission switch flips at 23.2 s in the clip; the phrase panel appears at 28.7 s.
  for (const [t0, n] of [[23.0, PERM_TOGGLE], [28.4, WORD]]) {
    if (t <= t0 || t >= t0 + 0.7) continue;
    const u = prog(t, t0, t0 + 0.65);
    marks.push((c, w, h) => {
      const sx = w / screenRect().w;
      c.fillStyle = `rgba(128,99,68,${0.38 * (1 - u)})`;
      c.beginPath();
      c.arc(n.x * w, n.y * h, (9 + 22 * ease.out(u)) * sx, 0, Math.PI * 2);
      c.fill();
    });
  }
  return marks;
}

function curlIndex(t) { return 1 + Math.round(clamp((t - 33.3) / 2.0) * 150); }
function permIndex(t) { return 30 + Math.round(clamp((t - 22.0) / 2.6) * 190); }

// ---------- copy ----------
const RECAP = 'Saito, a new intern from Eiroku University, has taken a night shift at Seido Hospital to make ends meet. Tonight it’s just him and Mr. Ushida, and the ambulances keep coming.';
const ANSWER = 'That’s Mr. Ushida, the other doctor on tonight’s shift. I’ve marked him on your page.';
const CREDIT = 'Manga: ブラックジャックによろしく / 佐藤秀峰  ·  Give My Regards to Black Jack / Shuho Sato';

function headline(c, t, str, a, b, o = {}) {
  const alpha = win(t, a, b, 0.5, 0.4);
  if (alpha <= 0) return 0;
  const rise = (1 - ease.out(prog(t, a, a + 0.6))) * 14;
  return text(c, str, LAYOUT.col.x, (o.y ?? LAYOUT.headY) + rise, {
    size: o.size ?? LAYOUT.head, weight: 600, alpha, maxW: LAYOUT.col.w, lh: 1.08, tracking: -0.6
  });
}

function sub(c, t, str, a, b, y, o = {}) {
  const alpha = win(t, a, b, 0.5, 0.35);
  if (alpha <= 0) return 0;
  const rise = (1 - ease.out(prog(t, a, a + 0.6))) * 10;
  return text(c, str, LAYOUT.col.x, y + rise, { size: o.size ?? LAYOUT.sub, weight: 400, color: C.muted, alpha, maxW: LAYOUT.col.w, lh: 1.32 });
}

function footnote(c, t, str, a, b, o = {}) {
  const alpha = win(t, a, b, 0.5, 0.35);
  if (alpha <= 0) return;
  text(c, str, LAYOUT.col.x, o.y ?? LAYOUT.footY, { size: LAYOUT.foot, weight: 400, color: C.faint, alpha, maxW: o.maxW ?? LAYOUT.col.w, lh: 1.35 });
}

function kicker(c, t, str, a, b, y = LAYOUT.kickerY) {
  const alpha = win(t, a, b, 0.4, 0.35);
  if (alpha <= 0) return;
  text(c, str, LAYOUT.col.x, y, { size: PORTRAIT ? 21 : 18, weight: 600, color: C.accent, alpha, tracking: 2.4 });
}

function lowerThird(c, t, str, a, b, place = 'center') {
  const alpha = win(t, a, b, 0.4, 0.35);
  if (alpha <= 0) return;
  c.save();
  c.globalAlpha = alpha;
  c.font = `500 ${PORTRAIT ? 32 : 28}px ${SANS}`;
  const w = c.measureText(str).width + 56, h = PORTRAIT ? 72 : 64;
  const x = place === 'left' ? 64 : W / 2 - w / 2, y = PORTRAIT ? 1610 : H - 128 + (1 - ease.out(prog(t, a, a + 0.5))) * 10;
  c.shadowColor = 'rgba(40,30,15,0.18)';
  c.shadowBlur = 30;
  c.shadowOffsetY = 8;
  rr(c, x, y, w, h, h / 2);
  c.fillStyle = 'rgba(255,252,245,0.96)';
  c.fill();
  c.shadowColor = 'transparent';
  c.fillStyle = C.ink;
  c.textBaseline = 'middle';
  c.fillText(str, x + 28, y + h / 2 + 1);
  c.restore();
}

function credit(c, t) {
  const alpha = win(t, 5.4, 39.8, 0.6, 0.5) * 0.85;
  if (alpha <= 0) return;
  text(c, CREDIT, PORTRAIT ? W / 2 : W - 56, LAYOUT.creditY - 20, {
    size: PORTRAIT ? 19 : 17, weight: 400, color: C.faint, alpha, align: PORTRAIT ? 'center' : 'right'
  });
}

// ---------- act 3: the reader's own AI app ----------
function chatBubble(c, msg, x, y, w, alpha, t) {
  const size = LAYOUT.chat.size;
  c.save();
  c.globalAlpha *= alpha;
  if (msg.who === 'user') {
    c.font = `500 ${size}px ${SANS}`;
    const lines = wrap(c, msg.text, w * 0.78 - 44);
    const bw = Math.max(...lines.map(l => c.measureText(l).width)) + 44, bh = lines.length * size * 1.25 + 30;
    rr(c, x + w - bw, y, bw, bh, 24);
    c.fillStyle = C.accent;
    c.fill();
    text(c, msg.text, x + w - bw + 22, y + 13, { size, weight: 500, color: C.card, maxW: w * 0.78 - 44, lh: 1.25 });
    c.restore();
    return bh;
  }
  if (msg.who === 'typing') {
    rr(c, x, y, 110, 58, 24);
    c.fillStyle = C.card;
    c.fill();
    for (let i = 0; i < 3; i++) {
      const pulse = 0.35 + 0.65 * Math.max(0, Math.sin((t * 5.5 - i * 0.7)));
      c.fillStyle = `rgba(95,87,76,${pulse})`;
      c.beginPath();
      c.arc(x + 32 + i * 23, y + 29, 6, 0, Math.PI * 2);
      c.fill();
    }
    c.restore();
    return 58;
  }
  // The AI's reply: a card, streamed in at a steady pace.
  const pad = 26, inner = w - pad * 2;
  c.font = `400 ${size}px ${SANS}`;
  const lines = wrap(c, msg.text, inner);
  const head = 40, tagH = msg.tag ? 46 : 0;
  const bh = pad + head + lines.length * size * 1.3 + tagH + pad - 6;
  c.shadowColor = 'rgba(60,45,25,0.13)';
  c.shadowBlur = 36;
  c.shadowOffsetY = 10;
  rr(c, x, y, w, bh, 24);
  c.fillStyle = C.card;
  c.fill();
  c.shadowColor = 'transparent';
  c.strokeStyle = 'rgba(33,30,25,0.07)';
  c.lineWidth = 1;
  c.stroke();
  // Header: a neutral mark, deliberately not any provider's logo.
  const hx = x + pad, hy = y + pad;
  c.strokeStyle = C.accent;
  c.lineWidth = 2;
  c.beginPath();
  c.arc(hx + 13, hy + 13, 13, 0, Math.PI * 2);
  c.stroke();
  c.fillStyle = C.accent;
  c.beginPath();
  for (let i = 0; i < 4; i++) {
    const a = i * Math.PI / 2;
    c.lineTo(hx + 13 + Math.cos(a) * 7, hy + 13 + Math.sin(a) * 7);
    c.lineTo(hx + 13 + Math.cos(a + Math.PI / 4) * 2.2, hy + 13 + Math.sin(a + Math.PI / 4) * 2.2);
  }
  c.fill();
  text(c, 'Your AI', hx + 38, hy + 1, { size: size * 0.78, weight: 600, color: C.muted });
  const chars = Math.floor(clamp((t - msg.t + 0.05) * 120, 0, 9999));
  text(c, msg.text, hx, hy + head, { size, weight: 400, color: C.ink, maxW: inner, lh: 1.3, chars });
  if (msg.tag) {
    const tagAlpha = clamp((t - msg.t - 0.3) / 0.4);
    c.globalAlpha *= tagAlpha;
    c.font = `600 ${Math.round(size * 0.6)}px ${SANS}`;
    c.letterSpacing = '1.2px';
    const label = msg.tag.toUpperCase();
    const tw = c.measureText(label).width + 24, ty = y + bh - pad - 30;
    rr(c, hx, ty, tw, 30, 15);
    c.strokeStyle = 'rgba(128,99,68,0.6)';
    c.lineWidth = 1.2;
    c.stroke();
    c.fillStyle = C.accent;
    c.textBaseline = 'middle';
    c.fillText(label, hx + 12, ty + 16);
  }
  c.restore();
  return bh;
}

function chat(c, t) {
  if (t < 13.0 || t > 22.2) return;
  const { x, w, top } = LAYOUT.chat;
  const fadeAll = 1 - ease.in(prog(t, 21.5, 22.0));
  const msgs = [
    { who: 'user', text: 'Remind me where I left off.', t: 13.35, group: 0 },
    { who: 'typing', t: 14.1, end: 14.75, group: 0 },
    { who: 'ai', text: RECAP, t: 14.75, tag: 'Illustrative demonstration', group: 0 },
    { who: 'user', text: 'Who’s the doctor in the middle panel?', t: 18.75, group: 1 },
    { who: 'typing', t: 19.25, end: 19.7, group: 1 },
    { who: 'ai', text: ANSWER, t: 19.7, tag: 'Illustrative demonstration', group: 1 }
  ];
  kicker(c, t, 'IN YOUR AI APP', 13.1, 22.0, top);
  // Group 0 slides up and away when the second question arrives.
  const leave = ease.inOut(prog(t, 18.45, 18.95));
  let y = top + (PORTRAIT ? 52 : 50);
  let y1 = y;
  for (const m of msgs) {
    if (t < m.t) continue;
    if (m.who === 'typing' && t >= m.end) continue;
    const appear = ease.out(prog(t, m.t, m.t + 0.35));
    let alpha = appear * fadeAll, dy = (1 - appear) * 18;
    let yy;
    if (m.group === 0) {
      alpha *= 1 - leave;
      yy = y - leave * 120;
    } else {
      yy = y1;
    }
    const h = chatBubble(c, m, x, yy + dy, w, alpha, t);
    if (m.group === 0) y += h + 18; else y1 += h + 18;
    if (m.who === 'typing') { if (m.group === 0) y -= h + 18; else y1 -= h + 18; }
  }
}

// ---------- frame ----------
function background(c, t) {
  c.fillStyle = C.paper;
  c.fillRect(0, 0, W, H);
  const pat = c.createPattern(A.grain, 'repeat');
  c.fillStyle = pat;
  c.fillRect(0, 0, W, H);
  const v = c.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.35, W / 2, H / 2, Math.max(W, H) * 0.75);
  v.addColorStop(0, 'rgba(120,90,50,0)');
  v.addColorStop(1, 'rgba(120,90,50,0.10)');
  c.fillStyle = v;
  c.fillRect(0, 0, W, H);
  void t;
}

/**
 * The device's pose at t, or null when it is off screen: hinge angle (0 closed, 180 flat), turn
 * about the vertical axis (180 shows the back), the film camera, opacity and the cover display.
 */
function deviceState(t) {
  if (t >= 40.6) return null;
  const alpha = 1 - ease.inOut(prog(t, 37.6, 38.3));
  if (alpha <= 0) return null;
  const cam = camera(t);
  // Act 1: the hinge opens from closed to flat. Closed, the device is half as wide and stands on
  // the right-hand (camera) leaf, so the camera follows it to keep it in the same place.
  const open = ease.inOut(prog(t, 2.7, 4.3));
  cam.fx += (1 - open) * MM.halfW * K / 2;
  // Act 5b: the open device turns around to show the cover on its outer display.
  const turn = ease.inOut(prog(t, 35.6, 36.7));
  return {
    alpha,
    hinge: open * 180,
    yaw: turn * 180,
    cam,
    // The outer display shows the cover only in cover mode, while reading with the device open.
    cover: t >= 35.0 ? 'outer-cover' : 'asleep'
  };
}

function widgetScene(c, t) {
  const alpha = win(t, 37.9, 40.4, 0.5, 0.45);
  if (alpha <= 0) return;
  const D = LAYOUT.device;
  const scale = PORTRAIT ? 1.2 : 1.12;
  const w = A.widget.width * scale, h = A.widget.height * scale;
  const rise = (1 - ease.out(prog(t, 37.9, 38.6))) * 30;
  c.save();
  c.globalAlpha = alpha;
  c.translate(D.x - w / 2, D.y - h / 2 + rise - (PORTRAIT ? 40 : 30));
  c.shadowColor = 'rgba(60,45,25,0.22)';
  c.shadowBlur = 60;
  c.shadowOffsetY = 20;
  rr(c, 0, 0, w, h, 56 * scale);
  c.fillStyle = '#fff';
  c.fill();
  c.shadowColor = 'transparent';
  c.save();
  rr(c, 0, 0, w, h, 56 * scale);
  c.clip();
  c.drawImage(A.widget, 0, 0, w, h);
  c.restore();
  // iCloud line under the widget.
  const ly = h + 46;
  const cloudA = clamp((t - 38.5) / 0.5);
  c.globalAlpha = alpha * cloudA;
  c.strokeStyle = C.accent;
  c.lineWidth = 3;
  c.beginPath();
  const cx = 34, cy = ly + 16;
  c.arc(cx - 10, cy + 3, 9, Math.PI * 0.5, Math.PI * 1.5);
  c.arc(cx + 2, cy - 4, 12, Math.PI * 1.1, Math.PI * 1.95);
  c.arc(cx + 14, cy + 3, 9, Math.PI * 1.5, Math.PI * 0.5);
  c.closePath();
  c.stroke();
  text(c, 'Your place syncs with iCloud', 68, ly, { size: PORTRAIT ? 30 : 26, weight: 500, color: C.muted });
  c.restore();
}

function endCard(c, t) {
  const a = ease.out(prog(t, 40.2, 40.9));
  if (a <= 0) return;
  const cx = W / 2, top = PORTRAIT ? 620 : 210;
  const icon = PORTRAIT ? 250 : 210;
  c.save();
  c.globalAlpha = a;
  const s = lerp(0.92, 1, a);
  c.translate(cx, top + icon / 2);
  c.scale(s, s);
  c.shadowColor = 'rgba(60,45,25,0.25)';
  c.shadowBlur = 50;
  c.shadowOffsetY = 18;
  rr(c, -icon / 2, -icon / 2, icon, icon, icon * 0.225);
  c.fillStyle = C.card;
  c.fill();
  c.shadowColor = 'transparent';
  rr(c, -icon / 2, -icon / 2, icon, icon, icon * 0.225);
  c.clip();
  c.drawImage(A.icon, -icon / 2, -icon / 2, icon, icon);
  c.restore();

  const wa = ease.out(prog(t, 40.6, 41.3));
  const wy = top + icon + (PORTRAIT ? 70 : 52);
  c.save();
  c.globalAlpha = wa;
  c.font = `700 ${PORTRAIT ? 92 : 84}px ${SANS}`;
  c.letterSpacing = '-1.5px';
  const w1 = c.measureText('Honbako').width;
  c.font = `600 ${PORTRAIT ? 80 : 72}px ${MINCHO}`;
  c.letterSpacing = '4px';
  const w2 = c.measureText('本箱').width;
  const gap = 30, x0 = cx - (w1 + gap + w2) / 2, base = wy + (PORTRAIT ? 84 : 76);
  c.fillStyle = C.ink;
  c.font = `700 ${PORTRAIT ? 92 : 84}px ${SANS}`;
  c.letterSpacing = '-1.5px';
  c.fillText('Honbako', x0, base);
  c.fillStyle = C.accent;
  c.font = `600 ${PORTRAIT ? 80 : 72}px ${MINCHO}`;
  c.letterSpacing = '4px';
  c.fillText('本箱', x0 + w1 + gap, base - 2);
  c.restore();

  const ta = ease.out(prog(t, 41.1, 41.8));
  text(c, 'Your manga. Your AI.', cx, wy + (PORTRAIT ? 130 : 116) + (1 - ta) * 10, {
    size: PORTRAIT ? 52 : 46, weight: 500, color: C.muted, alpha: ta, align: 'center'
  });
  const la = ease.out(prog(t, 41.8, 42.4));
  const legalY = PORTRAIT ? 1640 : 900;
  text(c, 'Some features require Honbako Pro. Compatible AI-provider account required.', cx, legalY, {
    size: PORTRAIT ? 26 : 24, weight: 400, color: C.faint, alpha: la, align: 'center', maxW: PORTRAIT ? 860 : 1400, lh: 1.35
  });
  text(c, CREDIT, cx, legalY + (PORTRAIT ? 80 : 40), {
    size: PORTRAIT ? 22 : 19, weight: 400, color: C.faint, alpha: la * 0.9, align: 'center', maxW: PORTRAIT ? 900 : 1600, lh: 1.35
  });
}

function copy(c, t) {
  const col = LAYOUT.col;
  // Act 1
  headline(c, t, 'Every story deserves a little company.', 0.5, 4.75);

  // Act 2: three phrases that build.
  const lines = [['Your files.', 5.2], ['Your server.', 7.75], ['Your manga.', 10.15]];
  const size = LAYOUT.head, lh = size * 1.08;
  const actAlpha = win(t, 5.2, 12.85, 0.5, 0.4);
  lines.forEach(([str, at], i) => {
    if (t < at) return;
    const active = i === lines.length - 1 ? 1 : 1 - ease.inOut(prog(t, lines[i + 1][1], lines[i + 1][1] + 0.5));
    const a = ease.out(prog(t, at, at + 0.5)) * actAlpha;
    const rise = (1 - ease.out(prog(t, at, at + 0.6))) * 12;
    const top = LAYOUT.headY - (PORTRAIT ? 30 : 70) + i * lh;
    text(c, str, col.x, top + rise, { size, weight: 600, alpha: a, color: active > 0.5 ? C.ink : C.ink, tracking: -0.6 });
    if (active < 1) text(c, str, col.x, top + rise, { size, weight: 600, alpha: a * (1 - active) * 0.62, color: C.paper, tracking: -0.6 });
  });
  const subY = LAYOUT.headY - (PORTRAIT ? 30 : 70) + 3 * lh + 22;
  sub(c, t, 'Import CBZ files and folders from Files.', 5.5, 7.75, subY);
  sub(c, t, 'Or connect your Komga, Kavita or Suwayomi library.', 8.0, 10.15, subY);
  sub(c, t, 'Or add sources with extensions you choose.', 10.4, 12.85, subY);
  footnote(c, t, 'Honbako doesn’t provide manga. Sources and their content are your responsibility.', 10.6, 12.85);

  // Act 3d
  const h3 = headline(c, t, 'Bring your own AI.', 21.95, 24.95);
  sub(c, t, 'Connect the AI app you already use through Honbako’s MCP server.', 22.15, 24.95, LAYOUT.headY + Math.max(h3, size * 1.08) + 18);
  if (t > 22.5 && t < 24.95) {
    const a = win(t, 22.6, 24.95, 0.5, 0.35);
    text(c, 'You choose what it can see.', col.x, LAYOUT.headY + size * 1.08 + 18 + (PORTRAIT ? 96 : 84), { size: LAYOUT.sub, weight: 600, color: C.accent, alpha: a, maxW: col.w });
  }
  footnote(c, t, 'Your AI provider account is separate from Honbako. Requests sync while Honbako is open; adding books and changing sources need your approval.', 22.4, 24.95);

  // Act 4
  const japaneseA = win(t, 25.05, 26.45, 0.5, 0.4);
  if (japaneseA > 0) {
    const h4 = text(c, 'A little Japanese. Every page.', col.x, LAYOUT.headY, { size, weight: 600, alpha: japaneseA, maxW: col.w, lh: 1.08, tracking: -0.6 });
    proTag(c, col.x, LAYOUT.headY + h4 + 22, japaneseA, PORTRAIT ? 1.15 : 1);
    text(c, 'Romaji aligned to each character, in the page’s own ink.', col.x, LAYOUT.headY + h4 + 80, { size: LAYOUT.sub, weight: 400, color: C.muted, alpha: japaneseA, maxW: col.w, lh: 1.32 });
  }
  lowerThird(c, t, 'Romaji aligned to each character', 26.9, 28.6);
  lowerThird(c, t, 'Tap a phrase for its reading and pronunciation', 29.3, 31.75, PORTRAIT ? 'center' : 'left');

  // Act 5
  headline(c, t, 'Turn the page.', 33.15, 35.45);
  sub(c, t, 'Paper-like page turns, one spread at a time.', 33.4, 35.45, LAYOUT.headY + size * 1.08 + 18);
  const coverA = win(t, 35.7, 37.65, 0.5, 0.35);
  if (coverA > 0) {
    const h5 = text(c, 'Your cover, on the outside.', col.x, LAYOUT.headY, { size, weight: 600, alpha: coverA, maxW: col.w, lh: 1.08, tracking: -0.6 });
    proTag(c, col.x, LAYOUT.headY + h5 + 22, coverA, PORTRAIT ? 1.15 : 1);
    text(c, 'While you read on iPhone Duo, the outer display shows the cover.', col.x, LAYOUT.headY + h5 + 80, { size: LAYOUT.sub, weight: 400, color: C.muted, alpha: coverA, maxW: col.w, lh: 1.32 });
  }
  footnote(c, t, 'Cover display uses the camera while you read. No photos or video are recorded or saved.', 36.0, 37.65);
  headline(c, t, 'Pick up where you left off.', 37.85, 39.95);
  sub(c, t, 'The Resume widget opens your book at your page.', 38.1, 39.95, LAYOUT.headY + size * 2 * 1.08 + 18);
}

let ready = false;
const screen = document.createElement('canvas');
screen.width = INNER_PX.w;
screen.height = INNER_PX.h;
const screenCtx = screen.getContext('2d');
let lastScreenKey = null;
let layer = null;

async function clipFrames(t) {
  const frames = {};
  if (t >= 21.6 && t < 25.5) frames.perm = await clipFrame('perm', permIndex(t));
  if (t >= 32.9) frames.curl = await clipFrame('curl', curlIndex(t));
  return frames;
}

/**
 * Step 1 of a frame: what tools/duo-render needs. `inner` is a JPEG data URL of the inner display,
 * present only when its content changed since the last call.
 */
window.prepareFrame = async function prepareFrame(t) {
  if (!ready) throw new Error('assets not loaded');
  const device = deviceState(t);
  if (!device) return { device: null };
  const s = innerScreen(t, await clipFrames(t));
  const marks = screenOverlays(t);
  const key = marks.length ? `${s.key}|marks@${t.toFixed(4)}` : s.key;
  let inner = null;
  if (key !== lastScreenKey) {
    screenCtx.setTransform(1, 0, 0, 1, 0, 0);
    screenCtx.globalAlpha = 1;
    screenCtx.fillStyle = '#000';
    screenCtx.fillRect(0, 0, screen.width, screen.height);
    s.paint(screenCtx, screen.width, screen.height);
    for (const mark of marks) mark(screenCtx, screen.width, screen.height);
    inner = screen.toDataURL('image/jpeg', 0.94);
    lastScreenKey = key;
  }
  return { device, inner };
};

/** Step 2: draws the frame, with the device layer duo-render wrote at `layerURL` (if any). */
window.renderFrame = async function renderFrame(t, layerURL) {
  if (!ready) throw new Error('assets not loaded');
  layer = layerURL ? await loadImage(layerURL) : null;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.globalAlpha = 1;
  background(ctx, t);
  const device = deviceState(t);
  if (device && layer) {
    // A soft shadow under the device, from the layer's own silhouette.
    ctx.save();
    ctx.globalAlpha = device.alpha;
    ctx.shadowColor = 'rgba(70,52,30,0.32)';
    ctx.shadowBlur = 60;
    ctx.shadowOffsetY = 30;
    ctx.drawImage(layer, 0, 0, W, H);
    ctx.restore();
  }
  copy(ctx, t);
  chat(ctx, t);
  widgetScene(ctx, t);
  credit(ctx, t);
  endCard(ctx, t);
};

window.filmReady = load().then(() => { ready = true; return { width: W, height: H, duration: 45, fps: 60, k: K }; });
