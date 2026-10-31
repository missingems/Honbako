// Honbako — a 45-second film drawn on one canvas, in the app's paper, ink and dune brown: a title
// page with the app icon, four sections with labelled features, and an end card.
//
// window.renderFrame(t) draws the frame at t seconds. It reads no clock and no unseeded
// randomness, so a given t always produces the same pixels; tools/render.mjs steps t at 60 fps.
// ?format=landscape (1920 × 1080) or ?format=portrait (1080 × 1920) recomposes the same timeline.
//
// Every screen inside the device is a genuine capture or screen recording of Honbako running
// in the iPhone Duo simulator (see README.md). The AI chat text in section 02 is written for the film
// and is labelled "Illustrative demonstration"; the annotation on the page is real app output.
// The previous, product-style cut is kept in src/product-cut/.

const FORMAT = new URLSearchParams(location.search).get('format') === 'portrait' ? 'portrait' : 'landscape';
const PORTRAIT = FORMAT === 'portrait';
const W = PORTRAIT ? 1080 : 1920;
const H = PORTRAIT ? 1920 : 1080;
const canvas = document.getElementById('film');
canvas.width = W;
canvas.height = H;
const ctx = canvas.getContext('2d');

// The app's own colours: HonbakoPaper, card and ink, with dune brown (#806344) as the one accent,
// for labels, Pro tags, taps and the place the AI marks on the page. The vermilion is kept only
// for the small 本箱 seal on the title page, a secondary editorial mark; the app icon leads.
const C = {
  paper: '#F5F0E6', ink: '#15140F', muted: '#45423B', faint: '#78746B', card: '#FFFCF6',
  dune: '#806344', seal: '#C23B22'
};
const SHADOW = 'rgba(60,45,25,';
// AI apps the app's own MCP client guide covers. Remote MCP, which cloud AI apps need, is Honbako Pro.
const PROVIDERS = [{ id: 'chatgpt', name: 'ChatGPT' }, { id: 'claude', name: 'Claude' }, { id: 'grok', name: 'Grok' }];
const SERIF = '"Baskerville", "Big Caslon", "Hiragino Mincho ProN", serif';
const MONO = '"Courier New", "PT Mono", monospace';
const MINCHO = '"Hiragino Mincho ProN", "Hiragino Mincho Pro", serif';

// iPhone Duo, from Apple's published specs: open 164.6 × 117.8 mm, closed 84.1 × 117.8 mm.
// Inner 7.6" panel (2670 × 1878 px, rendered at 2853 × 2007), outer 5.4" panel (1398 × 2034 px).
const MM = {
  openW: 164.6, openH: 117.8, halfW: 82.3, closedW: 84.1,
  innerW: 157.9, innerH: 111.1, thick: 5.2
};
const K = 960 / MM.openW; // px per mm; the open device is 960 px wide in both formats
const DISTANCE = 620;     // mm, duo-render's camera distance

const LAYOUT = PORTRAIT ? {
  device: { x: 540, y: 1150 },
  frame: 36,
  col: { x: 92, w: 896 },
  narrY: 128, narr: 50,
  figY: 1590, fig: 34,
  chat: { x: 92, w: 896, top: 392, size: 27 },
  footY: 1748, foot: 19,
  run: 18
} : {
  device: { x: 1300, y: 566 },
  frame: 40,
  col: { x: 128, w: 600 },
  narrY: 138, narr: 44,
  figY: 470, fig: 30,
  chat: { x: 128, w: 600, top: 350, size: 25 },
  footY: 912, foot: 17,
  run: 15
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
const win = (t, a, b, fi = 0.5, fo = 0.4) => Math.min(ease.sine(prog(t, a, a + fi)), 1 - ease.sine(prog(t, b - fo, b)));

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

// A seeded generator (mulberry32), for the paper grain and the seal's ink.
function seeded(seed) {
  return () => {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let r = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

async function load() {
  const stills = ['library', 'personal-server', 'extensions', 'reader-en', 'reader-en-annotated',
    'reader-ja', 'reader-ja-romaji', 'reader-ja-phrase', 'outer-cover'];
  await Promise.all(stills.map(async name => { A[name] = await loadImage(`../assets/captures/${name}.jpg`); }));
  A.widget = await loadImage('../assets/captures/widget-resume.png');
  A.icon = await loadImage('../assets/captures/icon.png');
  // The providers' own App Store icons, shown where the film names them, with no affiliation claim.
  for (const p of PROVIDERS) A[`provider-${p.id}`] = await loadImage(`../assets/captures/provider-${p.id}.png`);
  // Fonts must be ready before the first measured line; draw once off-canvas to warm them.
  for (const f of [`400 20px ${SERIF}`, `italic 400 20px ${SERIF}`, `600 20px ${SERIF}`, `400 20px ${MONO}`, `700 20px ${MONO}`, `600 20px ${MINCHO}`]) {
    ctx.font = f;
    ctx.fillText('本箱 Honbako', -100, -100);
  }
  await document.fonts.ready;
  A.grain = makeGrain();
  A.sealInk = makeSealInk();
}

function makeGrain() {
  const rand = seeded(0x5eed810);
  const g = document.createElement('canvas');
  g.width = 512; g.height = 512;
  const c = g.getContext('2d');
  const data = c.createImageData(512, 512);
  for (let i = 0; i < data.data.length; i += 4) {
    // Centred on the paper's own colour, so the grain adds texture without darkening it.
    const n = (rand() - 0.5) * 70;
    data.data[i] = 245 + n; data.data[i + 1] = 240 + n; data.data[i + 2] = 230 + n; data.data[i + 3] = 16;
  }
  c.putImageData(data, 0, 0);
  return g;
}

/** Speckles the seal is stamped through, so it reads as ink on paper rather than a flat shape. */
function makeSealInk() {
  const rand = seeded(0x0510a);
  const g = document.createElement('canvas');
  g.width = 256; g.height = 256;
  const c = g.getContext('2d');
  for (let i = 0; i < 900; i++) {
    c.fillStyle = `rgba(0,0,0,${0.25 + rand() * 0.6})`;
    c.beginPath();
    c.arc(rand() * 256, rand() * 256, 0.4 + rand() * rand() * 2.4, 0, Math.PI * 2);
    c.fill();
  }
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

/** The height text() would give a block, whether or not it is visible yet. */
function measure(c, str, size, maxW, lh, family = SERIF) {
  c.save();
  c.font = `400 ${size}px ${family}`;
  const n = wrap(c, str, maxW).length;
  c.restore();
  return n * size * lh;
}

/** Draws wrapped text with its top at y; returns the block height. */
function text(c, str, x, y, o) {
  const { size, weight = 400, style = '', color = C.ink, alpha = 1, maxW = 10000, lh = 1.2, align = 'left', family = SERIF, tracking = 0, chars = Infinity } = o;
  if (alpha <= 0) return 0;
  c.save();
  c.globalAlpha *= alpha;
  c.font = `${style} ${weight} ${size}px ${family}`;
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
    if (part) c.fillText(part, x, y + size * 0.86 + i * size * lh);
  });
  c.restore();
  return lines.length * size * lh;
}

function line(c, x1, y1, x2, y2, alpha = 1, width = 1.25, color = C.ink) {
  if (alpha <= 0) return;
  c.save();
  c.globalAlpha *= alpha;
  c.strokeStyle = color;
  c.lineWidth = width;
  c.beginPath();
  c.moveTo(x1, y1);
  c.lineTo(x2, y2);
  c.stroke();
  c.restore();
}

function dot(c, x, y, r, alpha, color = C.ink) {
  if (alpha <= 0) return;
  c.save();
  c.globalAlpha *= alpha;
  c.fillStyle = color;
  c.beginPath();
  c.arc(x, y, r, 0, Math.PI * 2);
  c.fill();
  c.restore();
}

/** "HONBAKO PRO", set as a small boxed label. Returns its width. */
function proTag(c, x, y, alpha, scale = 1) {
  if (alpha <= 0) return 0;
  c.save();
  c.globalAlpha *= alpha;
  c.font = `700 ${Math.round(15 * scale)}px ${MONO}`;
  c.letterSpacing = `${2 * scale}px`;
  const label = 'HONBAKO PRO';
  const w = c.measureText(label).width + 22 * scale, h = 28 * scale;
  c.strokeStyle = C.dune;
  c.lineWidth = 1.25;
  c.strokeRect(x + 0.5, y + 0.5, w, h);
  c.fillStyle = C.dune;
  c.textBaseline = 'middle';
  c.fillText(label, x + 12 * scale, y + h / 2 + 1);
  c.restore();
  return w;
}

/** A dimension line from a to b with end ticks and its measurement written across the middle. */
function dimension(c, a, b, label, alpha, vertical = false) {
  if (alpha <= 0) return;
  c.save();
  c.globalAlpha *= alpha;
  c.strokeStyle = C.ink;
  c.lineWidth = 1.1;
  const tick = 9;
  c.beginPath();
  c.moveTo(a.x, a.y); c.lineTo(b.x, b.y);
  if (vertical) {
    c.moveTo(a.x - tick, a.y); c.lineTo(a.x + tick, a.y);
    c.moveTo(b.x - tick, b.y); c.lineTo(b.x + tick, b.y);
  } else {
    c.moveTo(a.x, a.y - tick); c.lineTo(a.x, a.y + tick);
    c.moveTo(b.x, b.y - tick); c.lineTo(b.x, b.y + tick);
  }
  c.stroke();
  const size = PORTRAIT ? 19 : 17;
  c.font = `400 ${size}px ${MONO}`;
  c.letterSpacing = '0.5px';
  const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
  c.translate(mx, my);
  if (vertical) c.rotate(-Math.PI / 2);
  const w = c.measureText(label).width + 16;
  c.fillStyle = C.paper;
  c.fillRect(-w / 2, -size * 0.7, w, size * 1.4);
  c.fillStyle = C.ink;
  c.textAlign = 'center';
  c.textBaseline = 'middle';
  c.fillText(label, 0, 1);
  c.restore();
}

/** A leader from a point on the device to a two-line label: a dot, a line, a short shoulder, text. */
function leader(c, from, to, title, detail, alpha, side = 'right', mark = C.dune) {
  if (alpha <= 0) return;
  const grow = ease.out(clamp(alpha * 1.6));
  const ex = lerp(from.x, to.x, grow), ey = lerp(from.y, to.y, grow);
  dot(c, from.x, from.y, 4.5, alpha, mark);
  line(c, from.x, from.y, ex, ey, alpha);
  const sh = side === 'right' ? 28 : -28;
  line(c, to.x, to.y, to.x + sh * grow, to.y, alpha);
  const tx = to.x + sh + (side === 'right' ? 10 : -10);
  const align = side === 'right' ? 'left' : 'right';
  const ta = clamp((alpha - 0.4) / 0.6);
  const size = PORTRAIT ? 19 : 17;
  text(c, title, tx, to.y - size * 0.62, { size, family: MONO, weight: 700, tracking: 1.5, align, color: C.dune, alpha: ta });
  if (detail) text(c, detail, tx, to.y + size * 0.72, { size, family: MONO, color: C.muted, align, alpha: ta });
}

// ---------- the device ----------
// The device itself is Apple's iPhone Duo model, rendered by tools/duo-render (RealityKit) from
// the pose, turn, tilt and camera that deviceState(t) gives. This page paints its screens and the rest.
const INNER_PX = { w: 2853, h: 2007 };

/** The inner display's rectangle in device px (zoom 1), centred on the open device. */
function screenRect() {
  const w = MM.innerW * K, h = MM.innerH * K;
  return { x: -w / 2, y: -h / 2, w, h };
}

const READER_FOCUS = { x: 0.86, y: 0.46 };   // vertical dialogue on the right page of Vol. 7
const WORD = { x: 0.912, y: 0.47 };          // 実験台じゃない, the phrase tapped in the capture
const POPUP = { x: 0.705, y: 0.56 };         // centre of the "Read This Phrase" panel
const ANNOTATION = { x: 0.15, y: 0.48, w: 0.25, h: 0.177 }; // honbako_annotate_page box, in screen units
const PERM_TOGGLE = { x: 0.775, y: 0.53 };    // "Read Reading History and Progress" switch in the recording

function screenPoint(n) {
  const s = screenRect();
  return { x: s.x + n.x * s.w, y: s.y + n.y * s.h };
}

/**
 * Where a point on the device lands in the frame, as duo-render draws it: p is in mm from the open
 * device's centre (x right, y out of the inner screen, z down the page), turned by the state's yaw
 * and tilted by its pitch, seen by a perspective camera DISTANCE mm away.
 */
function project(p, st) {
  const { cam } = st;
  const yaw = st.yaw * Math.PI / 180, pitch = st.pitch * Math.PI / 180;
  const x1 = p.x * Math.cos(yaw) - p.y * Math.sin(yaw), y1 = p.x * Math.sin(yaw) + p.y * Math.cos(yaw), z1 = p.z;
  const y2 = y1 * Math.cos(pitch) + z1 * Math.sin(pitch), z2 = -y1 * Math.sin(pitch) + z1 * Math.cos(pitch);
  const ax = (cam.fx + (W / 2 - cam.x) / cam.zoom) / K, az = (cam.fy + (H / 2 - cam.y) / cam.zoom) / K;
  const s = DISTANCE / (DISTANCE - y2) * K * cam.zoom;
  return { x: W / 2 + (x1 - ax) * s, y: H / 2 + (z2 - az) * s };
}
/** A point on the inner screen, given in screen units, lifted by the state's explode. */
const onScreen = (n, st) => {
  const p = screenPoint(n);
  return project({ x: p.x / K, y: MM.thick / 2 + st.explode, z: p.y / K }, st);
};

function camera(t) {
  const D = LAYOUT.device;
  const base = { x: D.x, y: D.y, zoom: 1, fx: 0, fy: 0 };
  const on = (zoom, n, o = {}) => { const p = screenPoint(n); return { x: D.x, y: D.y, ...o, zoom, fx: o.fx ?? p.x, fy: p.y }; };
  const half = MM.openW * K / 2;
  // The Japanese push-in keeps the device's right edge on the frame edge, so the page fills it.
  const pushZoom = PORTRAIT ? 2.6 : 2.8;
  const push = on(pushZoom, READER_FOCUS, { x: W / 2, y: PORTRAIT ? 1000 : H / 2, fx: half - (W / 2) / pushZoom });
  const popup = PORTRAIT ? on(2.3, POPUP, { x: W / 2, y: 990 }) : on(2.0, POPUP, { x: W / 2, y: H / 2 - 6, fx: 0 });
  // The tilted view sits a little lower and smaller, to leave room for its labels.
  const exploded = { ...base, zoom: PORTRAIT ? 0.9 : 0.94, y: D.y + (PORTRAIT ? 40 : 34) };
  const keys = [
    [0, { ...base, zoom: 1.06 }], [2.9, { ...base, zoom: 1.06 }], [4.4, base],
    [6.35, base], [7.2, exploded], [8.05, exploded], [8.75, base],
    [12.7, on(PORTRAIT ? 1.04 : 1.1, { x: 0.5, y: 0.42 })], [13.3, base],
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
  if (t < 9.0) return draw(A.library, 'library');
  if (t < 11.0) return push(img('library'), img('personal-server'), 9.0);
  if (t < 13.0) return push(img('personal-server'), img('extensions'), 11.0);
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
        c.fillStyle = 'rgba(21,20,15,0.55)';
        c.fillRect(edge - 3, 0, 6, h);
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

/** Moments drawn onto the screen itself: the AI's mark and the two taps, in dune brown. */
function screenOverlays(t) {
  const marks = [];
  if (t > 20.1 && t < 21.6) {
    const u = prog(t, 20.1, 21.4);
    marks.push((c, w, h) => {
      const sx = w / screenRect().w, grow = ease.out(u) * 18 * sx;
      c.strokeStyle = `rgba(128,99,68,${0.9 * (1 - u)})`;
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
      c.fillStyle = `rgba(128,99,68,${0.5 * (1 - u)})`;
      c.beginPath();
      c.arc(n.x * w, n.y * h, (9 + 22 * ease.out(u)) * sx, 0, Math.PI * 2);
      c.fill();
    });
  }
  return marks;
}

function curlIndex(t) { return 1 + Math.round(clamp((t - 33.3) / 2.0) * 150); }
function permIndex(t) { return 30 + Math.round(clamp((t - 22.0) / 2.6) * 190); }

/**
 * The device's pose at t, or null when it is off screen: hinge angle (0 closed, 180 flat), turn
 * about the vertical axis (180 shows the back), tilt for the axonometric view, how far the inner
 * screen lifts off the body (mm, always 0 in this cut), the film camera, opacity and the cover display.
 */
function deviceState(t) {
  if (t < 2.9 || t >= 40.6) return null;
  const alpha = ease.sine(prog(t, 2.9, 3.6)) * (1 - ease.inOut(prog(t, 37.6, 38.3)));
  if (alpha <= 0) return null;
  const cam = camera(t);
  // Plate I: the hinge opens from closed to flat. Closed, the device is half as wide and stands on
  // the right-hand (camera) leaf, so the camera follows it to keep it in the same place.
  const open = ease.inOut(prog(t, 4.4, 5.8));
  cam.fx += (1 - open) * MM.halfW * K / 2;
  // Then it tips back into an axonometric view, like a drawing in a technical book, and settles again.
  const axo = ease.inOut(prog(t, 6.35, 7.2)) - ease.inOut(prog(t, 8.05, 8.75));
  // Plate IV: the open device turns around to show the cover on its outer display.
  const turn = ease.inOut(prog(t, 35.6, 36.7));
  return {
    alpha,
    hinge: open * 180,
    yaw: turn * 180 - axo * 16,
    pitch: axo * 50,
    explode: 0,
    cam,
    // The outer display shows the cover only in cover mode, while reading with the device open.
    cover: t >= 35.0 ? 'outer-cover' : 'asleep'
  };
}

// ---------- copy ----------
const RECAP = 'Saito, a new intern from Eiroku University, has taken a night shift at Seido Hospital to make ends meet. Tonight it’s just him and Mr. Ushida, and the ambulances keep coming.';
const ANSWER = 'That’s Mr. Ushida, the other doctor on tonight’s shift. I’ve marked him on your page.';
const CREDIT = 'Manga: ブラックジャックによろしく / 佐藤秀峰 · Give My Regards to Black Jack / Shuho Sato';

const PLATES = [
  { n: '01', name: 'LIBRARY', a: 3.2, b: 13.0 },
  { n: '02', name: 'YOUR AI', a: 13.0, b: 25.0 },
  { n: '03', name: 'JAPANESE', a: 25.0, b: 33.0 },
  { n: '04', name: 'IPHONE DUO', a: 33.0, b: 40.4 }
];
// Each section's headline. `card` sets it on a paper card, for when the page fills the frame.
const NARRATIVE = [
  { text: 'All your manga, in one library.', a: 3.5, b: 12.85 },
  { text: 'Ask your own AI about what you’re reading.', a: 13.15, b: 22.0 },
  { text: 'Help with Japanese, right on the page.', a: 25.2, b: 28.3, card: true, pro: true },
  { text: 'Made for iPhone Duo.', a: 33.2, b: 37.65 },
  { text: 'Back to your page in one tap.', a: 37.85, b: 40.3 }
];

/** The frame: a ruled border with crop marks, the running head, and the credit. */
function plateFrame(c, t) {
  const f = LAYOUT.frame;
  c.save();
  c.globalAlpha = 0.7;
  c.strokeStyle = C.ink;
  c.lineWidth = 1;
  c.strokeRect(f + 0.5, f + 0.5, W - 2 * f - 1, H - 2 * f - 1);
  // Crop marks just outside each corner.
  const m = 14, g = 6;
  c.beginPath();
  for (const [x, y, sx, sy] of [[f, f, -1, -1], [W - f, f, 1, -1], [f, H - f, -1, 1], [W - f, H - f, 1, 1]]) {
    c.moveTo(x + sx * g, y); c.lineTo(x + sx * (g + m), y);
    c.moveTo(x, y + sy * g); c.lineTo(x, y + sy * (g + m));
  }
  c.stroke();
  c.restore();

  // Running head: the app on the left, the section on the right.
  const runA = win(t, 3.2, 40.3, 0.6, 0.5);
  const y = f + (PORTRAIT ? 20 : 18);
  text(c, 'HONBAKO 本箱', f + 24, y, { size: LAYOUT.run, family: MONO, weight: 700, tracking: 2.4, alpha: runA * 0.85 });
  for (const p of PLATES) {
    const pa = win(t, p.a, p.b, 0.45, 0.35) * runA;
    text(c, `${p.n} — ${p.name}`, W - f - 24, y, { size: LAYOUT.run, family: MONO, weight: 700, tracking: 2.4, align: 'right', color: C.dune, alpha: pa });
  }
  // The manga's credit, on every frame it appears in.
  const ca = win(t, 3.4, 40.3, 0.6, 0.5);
  text(c, CREDIT, PORTRAIT ? W / 2 : f + 24, H - f - (PORTRAIT ? 44 : 38), {
    size: PORTRAIT ? 19 : 17, family: MONO, color: C.muted, alpha: ca, align: PORTRAIT ? 'center' : 'left'
  });
}

/** The section's headline. */
function narrative(c, t) {
  const { col } = LAYOUT;
  for (const n of NARRATIVE) {
    const a = win(t, n.a, n.b, 0.7, 0.45);
    if (a <= 0) continue;
    const rise = (1 - ease.out(prog(t, n.a, n.a + 0.8))) * 8;
    const y = LAYOUT.narrY + 20 + rise;
    c.save();
    c.font = `400 ${LAYOUT.narr}px ${SERIF}`;
    const lines = wrap(c, n.text, col.w);
    c.restore();
    const h = lines.length * LAYOUT.narr * 1.2 + (n.pro ? 50 : 0);
    if (n.card) {
      // When the page fills the frame, the line sits on a card of the film's paper.
      c.save();
      c.globalAlpha = a * 0.96;
      c.fillStyle = C.card;
      c.fillRect(col.x - 28, y - 26, col.w + 56, h + 40);
      c.globalAlpha = a * 0.7;
      c.strokeStyle = C.ink;
      c.lineWidth = 1;
      c.strokeRect(col.x - 27.5, y - 25.5, col.w + 55, h + 39);
      c.restore();
    }
    text(c, n.text, col.x, y, { size: LAYOUT.narr, maxW: col.w, lh: 1.2, alpha: a });
    if (n.pro) proTag(c, col.x, y + lines.length * LAYOUT.narr * 1.2 + 16, a, PORTRAIT ? 1.15 : 1);
  }
}

/** A feature caption: a small label, a line in the serif, and an optional line of detail. */
function figure(c, t, label, title, detail, a, b, o = {}) {
  const alpha = win(t, a, b, 0.5, 0.35);
  if (alpha <= 0) return 0;
  const x = o.x ?? LAYOUT.col.x, y = o.y ?? LAYOUT.figY, w = o.w ?? LAYOUT.col.w;
  const rise = (1 - ease.out(prog(t, a, a + 0.6))) * 8;
  const size = LAYOUT.fig;
  let h = 0;
  if (o.card) {
    // On the page: a paper card with a hairline, like a label pasted into a plate.
    c.save();
    c.font = `400 ${size}px ${SERIF}`;
    const tw = Math.max(c.measureText(title).width, detail ? (c.font = `400 ${PORTRAIT ? 20 : 18}px ${MONO}`, c.measureText(detail).width) : 0);
    c.restore();
    const cw = Math.min(w, tw + 56), ch = 40 + size * 1.25 + (detail ? 34 : 0) + 18;
    const cx = o.align === 'right' ? x + w - cw : x;
    c.save();
    c.globalAlpha = alpha * 0.96;
    c.fillStyle = C.card;
    c.fillRect(cx, y + rise - 20, cw, ch);
    c.globalAlpha = alpha * 0.7;
    c.strokeStyle = C.ink;
    c.strokeRect(cx + 0.5, y + rise - 19.5, cw - 1, ch - 1);
    c.restore();
    o = { ...o, x: cx + 28 };
  }
  const tx = o.x ?? x;
  text(c, label, tx, y + rise, { size: PORTRAIT ? 19 : 17, family: MONO, weight: 700, tracking: 2.5, color: C.dune, alpha });
  h += 34;
  h += text(c, title, tx, y + rise + h, { size, maxW: w, lh: 1.15, alpha });
  if (detail) h += 6 + text(c, detail, tx, y + rise + h + 6, { size: PORTRAIT ? 20 : 18, family: MONO, color: C.muted, maxW: w, lh: 1.35, alpha });
  if (o.pro) h += 14 + (proTag(c, tx, y + rise + h + 14, alpha, PORTRAIT ? 1.15 : 1) ? 28 : 0);
  return h;
}

function footnote(c, t, str, a, b, o = {}) {
  const alpha = win(t, a, b, 0.5, 0.35);
  if (alpha <= 0) return;
  text(c, `* ${str}`, o.x ?? LAYOUT.col.x, o.y ?? LAYOUT.footY, { size: LAYOUT.foot, family: MONO, color: C.muted, alpha, maxW: o.maxW ?? LAYOUT.col.w, lh: 1.4 });
}

// ---------- 01 library: dimensions and the exploded view ----------
function plateOne(c, t, st) {
  if (!st || t > 9.2) return;
  const off = PORTRAIT ? 46 : 40;
  // Closed: 84.1 × 117.8 mm, the leaf that stays put runs from the fold (x 0) to the right edge.
  const closedA = win(t, 3.6, 4.45, 0.45, 0.3);
  if (closedA > 0) {
    const l = -0.9, r = MM.closedW - 0.9, top = -MM.openH / 2, bot = MM.openH / 2;
    const p1 = project({ x: l, y: 0, z: bot }, st), p2 = project({ x: r, y: 0, z: bot }, st);
    dimension(c, { x: p1.x, y: p1.y + off }, { x: p2.x, y: p2.y + off }, '84.1 mm', closedA);
    const q1 = project({ x: r, y: 0, z: top }, st), q2 = project({ x: r, y: 0, z: bot }, st);
    dimension(c, { x: q1.x + off, y: q1.y }, { x: q2.x + off, y: q2.y }, '117.8 mm', closedA, true);
  }
  const openA = win(t, 5.75, 6.55, 0.4, 0.3);
  if (openA > 0) {
    const half = MM.openW / 2, bot = MM.openH / 2;
    const p1 = project({ x: -half, y: 0, z: bot }, st), p2 = project({ x: half, y: 0, z: bot }, st);
    dimension(c, { x: p1.x, y: p1.y + off }, { x: p2.x, y: p2.y + off }, '164.6 mm', openA);
  }
  // Tilted: the inner display and the body, each with its label.
  const labelA = win(t, 7.2, 8.05, 0.45, 0.3);
  if (labelA > 0) {
    const scr = onScreen({ x: 0.55, y: 0.03 }, st);
    const body = project({ x: 52, y: -MM.thick / 2, z: MM.openH / 2 }, st);
    leader(c, scr, { x: scr.x - 30, y: scr.y - (PORTRAIT ? 120 : 100) }, 'INNER DISPLAY', '7.6 in', labelA, 'left');
    leader(c, body, { x: body.x - 40, y: body.y + (PORTRAIT ? 48 : 80) }, 'IPHONE DUO', '164.6 × 117.8 mm open', labelA, 'left');
  }
}

// ---------- 02 your AI: the reader's own AI app ----------
function chatBubble(c, msg, x, y, w, alpha, t) {
  const size = LAYOUT.chat.size;
  c.save();
  c.globalAlpha *= alpha;
  if (msg.who === 'user') {
    c.font = `400 ${size}px ${SERIF}`;
    const lines = wrap(c, msg.text, w * 0.78 - 44);
    const bw = Math.max(...lines.map(l => c.measureText(l).width)) + 44, bh = lines.length * size * 1.25 + 30;
    rr(c, x + w - bw, y, bw, bh, 6);
    c.fillStyle = C.ink;
    c.fill();
    text(c, msg.text, x + w - bw + 22, y + 14, { size, color: C.card, maxW: w * 0.78 - 44, lh: 1.25 });
    c.restore();
    return { h: bh };
  }
  if (msg.who === 'typing') {
    c.strokeStyle = C.ink;
    c.lineWidth = 1;
    rr(c, x + 0.5, y + 0.5, 100, 54, 6);
    c.stroke();
    for (let i = 0; i < 3; i++) {
      const pulse = 0.3 + 0.7 * Math.max(0, Math.sin((t * 5.5 - i * 0.7)));
      dot(c, x + 28 + i * 22, y + 27, 5, pulse, C.ink);
    }
    c.restore();
    return { h: 54 };
  }
  // The AI's reply: a paper card with a hairline, streamed in at a steady pace.
  const pad = 24, inner = w - pad * 2;
  c.font = `400 ${size}px ${SERIF}`;
  const lines = wrap(c, msg.text, inner);
  const head = 38, tagH = msg.tag ? 44 : 0;
  const bh = pad + head + lines.length * size * 1.3 + tagH + pad - 6;
  c.fillStyle = C.card;
  c.fillRect(x, y, w, bh);
  c.strokeStyle = C.ink;
  c.lineWidth = 1;
  c.strokeRect(x + 0.5, y + 0.5, w - 1, bh - 1);
  // Header: a neutral mark, deliberately not any provider's logo.
  const hx = x + pad, hy = y + pad;
  c.strokeStyle = C.ink;
  c.lineWidth = 1.5;
  c.beginPath();
  c.arc(hx + 11, hy + 11, 11, 0, Math.PI * 2);
  c.stroke();
  c.fillStyle = C.ink;
  c.beginPath();
  for (let i = 0; i < 4; i++) {
    const a = i * Math.PI / 2;
    c.lineTo(hx + 11 + Math.cos(a) * 6, hy + 11 + Math.sin(a) * 6);
    c.lineTo(hx + 11 + Math.cos(a + Math.PI / 4) * 1.9, hy + 11 + Math.sin(a + Math.PI / 4) * 1.9);
  }
  c.fill();
  text(c, 'YOUR AI', hx + 34, hy + 3, { size: size * 0.66, family: MONO, weight: 700, tracking: 2, color: C.muted });
  const chars = Math.floor(clamp((t - msg.t + 0.05) * 120, 0, 9999));
  text(c, msg.text, hx, hy + head, { size, maxW: inner, lh: 1.3, chars });
  if (msg.tag) {
    const tagAlpha = clamp((t - msg.t - 0.3) / 0.4);
    text(c, `— ${msg.tag.toUpperCase()}`, hx, y + bh - pad - 24, { size: Math.round(size * 0.62), family: MONO, weight: 700, tracking: 1.5, color: C.muted, alpha: tagAlpha });
  }
  c.restore();
  return { h: bh };
}

/** Draws the chat; returns where the second answer's card sits, for the leader to the page. */
function chat(c, t) {
  if (t < 13.0 || t > 22.2) return null;
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
  text(c, 'IN YOUR AI APP', x, top - 6, { size: PORTRAIT ? 19 : 17, family: MONO, weight: 700, tracking: 2.5, color: C.dune, alpha: win(t, 13.1, 22.0, 0.4, 0.35) });
  // Group 0 slides up and away when the second question arrives.
  const leave = ease.inOut(prog(t, 18.45, 18.95));
  let y = top + 34, y1 = y, anchor = null;
  for (const m of msgs) {
    if (t < m.t) continue;
    if (m.who === 'typing' && t >= m.end) continue;
    const appear = ease.out(prog(t, m.t, m.t + 0.35));
    let alpha = appear * fadeAll, dy = (1 - appear) * 14;
    let yy;
    if (m.group === 0) {
      alpha *= 1 - leave;
      yy = y - leave * 100;
    } else {
      yy = y1;
    }
    const { h } = chatBubble(c, m, x, yy + dy, w, alpha, t);
    if (m.group === 1 && m.who === 'ai') anchor = { x, y: yy + dy, w, h };
    if (m.who === 'typing') continue;
    if (m.group === 0) y += h + 16; else y1 += h + 16;
  }
  return anchor;
}

/** Plate II's figure: a leader from the AI's answer to the place it marked on the page. */
function markLeader(c, t, st, card) {
  const a = win(t, 20.25, 21.6, 0.5, 0.3);
  if (!card || !st || a <= 0) return;
  const box = ANNOTATION;
  if (PORTRAIT) {
    const to = onScreen({ x: box.x + box.w / 2, y: box.y }, st);
    const from = { x: card.x + card.w * 0.3, y: card.y + card.h };
    dot(c, to.x, to.y, 6, a, C.dune);
    line(c, from.x, from.y, from.x, lerp(from.y, to.y - 30, ease.out(a)), a);
    line(c, from.x, to.y - 30, to.x, to.y - 30, a * clamp(a * 2 - 1));
    line(c, to.x, to.y - 30, to.x, to.y, a * clamp(a * 2 - 1));
  } else {
    const to = onScreen({ x: box.x, y: box.y + box.h / 2 }, st);
    const from = { x: card.x + card.w, y: card.y + card.h * 0.55 };
    dot(c, from.x, from.y, 3.5, a, C.dune);
    const mid = lerp(from.x, to.x, 0.55);
    line(c, from.x, from.y, lerp(from.x, mid, ease.out(a)), from.y, a);
    line(c, mid, from.y, mid, to.y, a * clamp(a * 2 - 1));
    line(c, mid, to.y, to.x, to.y, a * clamp(a * 2 - 1));
    dot(c, to.x, to.y, 6, a, C.dune);
  }
}

// ---------- 03 Japanese: the scale bar ----------
/** A scale bar that measures 10 mm of the device at the camera's current zoom. */
function scaleBar(c, t, st) {
  const a = win(t, 26.4, 32.5, 0.5, 0.4);
  if (!st || a <= 0) return;
  const len = 10 * K * st.cam.zoom;
  const x = W - LAYOUT.frame - 84 - len, y = PORTRAIT ? H - 330 : H - 128;
  c.save();
  c.globalAlpha = a * 0.96;
  c.fillStyle = C.card;
  c.fillRect(x - 24, y - 22, len + 72, 62);
  c.globalAlpha = a * 0.7;
  c.strokeStyle = C.ink;
  c.strokeRect(x - 23.5, y - 21.5, len + 71, 61);
  c.restore();
  // Alternate black and white fifths, like an engraved scale.
  c.save();
  c.globalAlpha = a;
  for (let i = 0; i < 5; i++) {
    c.fillStyle = i % 2 ? C.card : C.ink;
    c.fillRect(x + i * len / 5, y, len / 5, 8);
  }
  c.strokeStyle = C.ink;
  c.lineWidth = 1;
  c.strokeRect(x + 0.5, y + 0.5, len - 1, 8);
  c.restore();
  const size = PORTRAIT ? 18 : 16;
  text(c, '0', x, y + 14, { size, family: MONO, align: 'center', alpha: a });
  text(c, '10 mm', x + len, y + 14, { size, family: MONO, align: 'center', alpha: a });
}

// ---------- 04 iPhone Duo: the Resume widget ----------
function widgetScene(c, t) {
  const alpha = win(t, 37.9, 40.4, 0.5, 0.45);
  if (alpha <= 0) return;
  const D = LAYOUT.device;
  const scale = PORTRAIT ? 1.15 : 1.0;
  const w = A.widget.width * scale, h = A.widget.height * scale;
  const rise = (1 - ease.out(prog(t, 37.9, 38.6))) * 20;
  const x = PORTRAIT ? D.x - w / 2 : D.x - w / 2 + 40, y = D.y - h / 2 + rise - (PORTRAIT ? 60 : 40);
  c.save();
  c.globalAlpha = alpha;
  c.shadowColor = `${SHADOW}0.22)`;
  c.shadowBlur = 50;
  c.shadowOffsetY = 18;
  rr(c, x, y, w, h, 56 * scale);
  c.fillStyle = '#fff';
  c.fill();
  c.shadowColor = 'transparent';
  rr(c, x, y, w, h, 56 * scale);
  c.clip();
  c.drawImage(A.widget, x, y, w, h);
  c.restore();
}

// ---------- the title page and the colophon ----------
/** An app icon: the image in the iOS corner shape, with a hairline and a soft shadow on the paper. */
function appIcon(c, img, x, y, size, alpha, shadow = true) {
  if (alpha <= 0) return;
  const r = size * 0.2237;
  c.save();
  c.globalAlpha *= alpha;
  if (shadow) {
    c.save();
    c.shadowColor = `${SHADOW}0.22)`;
    c.shadowBlur = size * 0.14;
    c.shadowOffsetY = size * 0.05;
    rr(c, x, y, size, size, r);
    c.fillStyle = C.card;
    c.fill();
    c.restore();
  }
  c.save();
  rr(c, x, y, size, size, r);
  c.clip();
  c.drawImage(img, x, y, size, size);
  c.restore();
  c.strokeStyle = 'rgba(21,20,15,0.14)';
  c.lineWidth = 1;
  rr(c, x + 0.5, y + 0.5, size - 1, size - 1, r);
  c.stroke();
  c.restore();
}

/** The app icon arriving: it settles from slightly large, like the seal used to, without any shake. */
function iconArrive(c, t, at, cx, cy, size) {
  const u = prog(t, at, at + 0.6);
  if (u <= 0) return;
  const s = size * lerp(1.06, 1, ease.out(u));
  appIcon(c, A.icon, cx - s / 2, cy - s / 2, s, ease.sine(clamp(u * 1.8)));
}

/** The seal: 本箱 in two characters, cut into a vermilion square and stamped through the ink speckle. */
function seal(c, cx, cy, size, alpha) {
  if (alpha <= 0) return;
  const s = document.createElement('canvas');
  s.width = s.height = Math.ceil(size);
  const g = s.getContext('2d');
  g.fillStyle = C.seal;
  rr(g, 0, 0, size, size, size * 0.06);
  g.fill();
  g.globalCompositeOperation = 'destination-out';
  g.strokeStyle = '#000';
  g.lineWidth = size * 0.03;
  rr(g, size * 0.09, size * 0.09, size * 0.82, size * 0.82, size * 0.03);
  g.stroke();
  g.font = `700 ${size * 0.36}px ${MINCHO}`;
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillStyle = '#000';
  g.fillText('本', size / 2, size * 0.31);
  g.fillText('箱', size / 2, size * 0.7);
  g.globalAlpha = 0.85;
  g.drawImage(A.sealInk, 0, 0, size, size);
  c.save();
  c.globalAlpha = alpha;
  c.drawImage(s, cx - size / 2, cy - size / 2);
  c.restore();
}

/** A stamp: lands slightly large and settles, without any shake. */
function stamp(c, t, at, cx, cy, size) {
  const u = prog(t, at, at + 0.45);
  if (u <= 0) return;
  const s = lerp(1.12, 1, ease.out(u));
  seal(c, cx, cy, size * s, ease.out(clamp(u * 2.2)));
}

function titlePage(c, t) {
  const a = 1 - ease.sine(prog(t, 2.3, 2.85));
  if (a <= 0) return;
  const cx = W / 2, top = PORTRAIT ? 560 : 200;
  const step = (at) => ease.sine(prog(t, at, at + 0.8)) * a;
  // The app icon is the mark; the name, a dune rule and the line sit under it.
  const icon = PORTRAIT ? 280 : 236;
  c.save();
  c.globalAlpha = a;
  iconArrive(c, t, 0.15, cx, top + icon / 2, icon);
  c.restore();
  const ny = top + icon + (PORTRAIT ? 64 : 52);
  text(c, 'HONBAKO  本箱', cx, ny, { size: PORTRAIT ? 34 : 30, tracking: 14, align: 'center', alpha: step(0.45) });
  const ry = ny + (PORTRAIT ? 86 : 76);
  line(c, cx - 50, ry, cx + 50, ry, step(0.6), 1.25, C.dune);
  text(c, 'The manga reader with MCP built in.', cx, ry + 30, { size: PORTRAIT ? 36 : 32, color: C.muted, align: 'center', alpha: step(0.6) });
  // A small 本箱 seal, the film's editorial mark, stamped under the line. Secondary to the icon.
  c.save();
  c.globalAlpha = a;
  stamp(c, t, 1.45, cx, ry + (PORTRAIT ? 180 : 150), PORTRAIT ? 56 : 48);
  c.restore();
}

function colophon(c, t) {
  const a = ease.sine(prog(t, 40.6, 41.3));
  if (a <= 0) return;
  const cx = W / 2, top = PORTRAIT ? 440 : 132;
  const icon = PORTRAIT ? 220 : 184;
  iconArrive(c, t, 40.7, cx, top + icon / 2, icon);
  const wy = top + icon + (PORTRAIT ? 48 : 40);
  const wa = ease.sine(prog(t, 41.0, 41.7));
  text(c, 'HONBAKO', cx, wy, { size: PORTRAIT ? 64 : 58, tracking: 20, align: 'center', alpha: wa });
  line(c, cx - 50, wy + (PORTRAIT ? 110 : 98), cx + 50, wy + (PORTRAIT ? 110 : 98), wa, 1.25, C.dune);
  const ta = ease.sine(prog(t, 41.4, 42.1));
  text(c, 'Your manga. Your AI.', cx, wy + (PORTRAIT ? 140 : 124), { size: PORTRAIT ? 54 : 48, align: 'center', alpha: ta });
  text(c, 'A little company on every page.', cx, wy + (PORTRAIT ? 212 : 188), { size: PORTRAIT ? 40 : 34, style: 'italic', color: C.muted, align: 'center', alpha: ta });
  const la = ease.sine(prog(t, 42.0, 42.6));
  const legalY = PORTRAIT ? 1560 : 862;
  text(c, 'Some features require Honbako Pro. Compatible AI-provider account required.', cx, legalY, {
    size: PORTRAIT ? 21 : 19, family: MONO, color: C.muted, alpha: la, align: 'center', maxW: PORTRAIT ? 880 : 1500, lh: 1.4
  });
  text(c, CREDIT, cx, legalY + (PORTRAIT ? 70 : 36), {
    size: PORTRAIT ? 19 : 17, family: MONO, color: C.muted, alpha: la, align: 'center', maxW: PORTRAIT ? 990 : 1600, lh: 1.4
  });
}

// ---------- the figures, in order ----------
function figures(c, t) {
  const { col } = LAYOUT;
  // Plate I: what goes in the box.
  figure(c, t, 'LOCAL FILES', 'Import CBZ files and folders from Files.', null, 6.0, 9.0);
  figure(c, t, 'PERSONAL SERVER', 'Connect your Komga, Kavita or Suwayomi library.', null, 9.0, 11.0);
  figure(c, t, 'EXTENSIONS', 'Add sources with extensions you choose.', null, 11.0, 12.9);
  footnote(c, t, 'Honbako doesn’t provide manga. Sources and their content are your responsibility.', 11.2, 12.9);

  // Your AI: the answer is joined to the panel it annotated; then permissions.
  const pa = win(t, 21.95, 24.95, 0.5, 0.4);
  if (pa > 0) {
    const y = PORTRAIT ? 250 : LAYOUT.figY - 150;
    text(c, 'MCP SERVER', col.x, y, { size: PORTRAIT ? 19 : 17, family: MONO, weight: 700, tracking: 2.5, color: C.dune, alpha: pa });
    const h = text(c, 'Bring your own AI.', col.x, y + 34, { size: PORTRAIT ? 58 : 50, maxW: col.w, lh: 1.1, alpha: pa });
    const desc = 'Connect the AI app you already use through Honbako’s MCP server.';
    text(c, desc, col.x, y + 50 + h, { size: LAYOUT.fig, color: C.muted, maxW: col.w, lh: 1.2, alpha: win(t, 22.15, 24.95) });
    const h2 = measure(c, desc, LAYOUT.fig, col.w, 1.2);
    text(c, 'You choose what it can see.', col.x, y + 70 + h + h2, { size: LAYOUT.fig, style: 'italic', maxW: col.w, alpha: win(t, 22.6, 24.95) });
    providerRow(c, t, col.x, y + 70 + h + h2 + LAYOUT.fig * 1.2 + (PORTRAIT ? 36 : 30));
  }
  footnote(c, t, 'Your AI provider account is separate from Honbako. Requests sync while Honbako is open; adding books and changing sources need your approval.', 22.4, 24.95);
  const fig4 = win(t, 20.25, 21.6, 0.5, 0.3);
  text(c, 'ANNOTATED BY YOUR AI', col.x + col.w, LAYOUT.chat.top - 6, { size: PORTRAIT ? 19 : 17, family: MONO, weight: 700, tracking: 2, align: 'right', color: C.dune, alpha: fig4 });

  // Plate III: captions on the page.
  const cardY = PORTRAIT ? 1700 : H - 210;
  figure(c, t, 'ROMAJI', 'Romaji aligned to each character.', null, 26.9, 28.6, { card: true, y: cardY, x: PORTRAIT ? col.x : LAYOUT.frame + 48, w: PORTRAIT ? col.w : 900 });
  figure(c, t, 'READ THIS PHRASE', 'Tap a phrase for its reading and pronunciation.', null, 29.3, 31.75, { card: true, y: cardY, x: PORTRAIT ? col.x : LAYOUT.frame + 48, w: PORTRAIT ? col.w : 900 });

  // Plate IV.
  const y4 = LAYOUT.figY;
  figure(c, t, 'PAGE TURNS', 'Paper-like page turns, one spread at a time.', null, 33.45, 35.45, { y: y4 });
  figure(c, t, 'COVER DISPLAY', 'While you read, the outer display shows the cover.', null, 35.75, 37.65, { y: y4, pro: true });
  footnote(c, t, 'Cover display uses the camera while you read. No photos or video are recorded or saved.', 36.0, 37.65);
  figure(c, t, 'RESUME WIDGET', 'Opens your book at your page.', 'Your place syncs with iCloud.', 38.1, 40.2, { y: y4 });
}

/**
 * The AI apps Honbako's own MCP guide covers, by their App Store icons. Cloud AI apps reach Honbako
 * through the Remote MCP server, a Pro feature, so the row carries the Pro tag and says so.
 */
function providerRow(c, t, x, y) {
  const a = win(t, 22.9, 24.95, 0.5, 0.4);
  if (a <= 0) return;
  const size = PORTRAIT ? 56 : 48, gap = PORTRAIT ? 40 : 32, nameSize = PORTRAIT ? 26 : 23;
  let px = x;
  PROVIDERS.forEach((p, i) => {
    const pa = a * ease.sine(prog(t, 22.9 + i * 0.12, 23.4 + i * 0.12));
    appIcon(c, A[`provider-${p.id}`], px, y, size, pa, false);
    const w = (c.font = `400 ${nameSize}px ${SERIF}`, c.measureText(p.name).width);
    text(c, p.name, px + size + 14, y + (size - nameSize) / 2 - 2, { size: nameSize, alpha: pa });
    px += size + 14 + w + gap;
  });
  // Kept clear of the device, which starts just right of the column in landscape.
  const maxW = PORTRAIT ? LAYOUT.col.w : 540, small = PORTRAIT ? 20 : 17;
  const ny = y + size + (PORTRAIT ? 24 : 20);
  const tw = proTag(c, x, ny, a, PORTRAIT ? 1.15 : 1);
  text(c, 'Remote MCP, for cloud AI apps.', x + tw + 14, ny + (PORTRAIT ? 7 : 6), { size: small, family: MONO, color: C.muted, alpha: a });
  // In portrait the device sits right under the row, so this line joins the footnotes instead.
  text(c, 'Names and icons belong to their owners. Honbako isn’t affiliated with them.', x, PORTRAIT ? LAYOUT.footY - 92 : ny + 46, {
    size: small, family: MONO, color: C.muted, maxW, lh: 1.4, alpha: a
  });
}

// ---------- frame ----------
function background(c) {
  c.fillStyle = C.paper;
  c.fillRect(0, 0, W, H);
  c.fillStyle = c.createPattern(A.grain, 'repeat');
  c.fillRect(0, 0, W, H);
  // Faint registration crosses on a 10 mm grid of the device's own scale.
  const step = 20 * K;
  c.save();
  c.strokeStyle = 'rgba(21,20,15,0.07)';
  c.lineWidth = 1;
  c.beginPath();
  const f = LAYOUT.frame + 20;
  for (let x = f + (W - 2 * f) % step / 2; x <= W - f; x += step) {
    for (let y = f + (H - 2 * f) % step / 2; y <= H - f; y += step) {
      c.moveTo(x - 5, y); c.lineTo(x + 5, y);
      c.moveTo(x, y - 5); c.lineTo(x, y + 5);
    }
  }
  c.stroke();
  c.restore();
  const v = c.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.4, W / 2, H / 2, Math.max(W, H) * 0.78);
  v.addColorStop(0, `${SHADOW}0)`);
  v.addColorStop(1, `${SHADOW}0.05)`);
  c.fillStyle = v;
  c.fillRect(0, 0, W, H);
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
  background(ctx);
  plateFrame(ctx, t);
  titlePage(ctx, t);
  const device = deviceState(t);
  if (device && layer) {
    // A soft shadow under the device, from the layer's own silhouette.
    ctx.save();
    ctx.globalAlpha = device.alpha;
    ctx.shadowColor = `${SHADOW}0.3)`;
    ctx.shadowBlur = 56;
    ctx.shadowOffsetY = 28;
    ctx.drawImage(layer, 0, 0, W, H);
    ctx.restore();
  }
  plateOne(ctx, t, device);
  const card = chat(ctx, t);
  markLeader(ctx, t, device, card);
  widgetScene(ctx, t);
  narrative(ctx, t);
  figures(ctx, t);
  scaleBar(ctx, t, device);
  colophon(ctx, t);
};

window.filmReady = load().then(() => { ready = true; return { width: W, height: H, duration: 45, fps: 60, k: K }; });
