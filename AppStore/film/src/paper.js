// Honbako's paper, ported line for line from the app so the film's paper is the app's paper:
//   ReaderPaperTexture.tileData(strength: .light, seed: 0xA1D02026)  Aidoku/Features/Reader/Page/ReaderPaperTexture.swift
//   SumiPaperSurface.inkTile (alpha remap)                            Aidoku/Features/Bookshelf/SumiPaperSurface.swift
//   HonbakoPaperStock (base colour + grain at 0.6)                    Aidoku/Features/Bookshelf/Services/HonbakoPaperStock.swift
// The tile is 256 px for 128 pt, so one tile pixel per film pixel matches a 2× display.

(function () {
  const TILE = 256;

  /** ReaderPaperTexture.tileData for .light: one alpha byte per pixel of transparent black. */
  function tileAlpha(seed = 0xA1D02026) {
    let state = (seed === 0 ? 1 : seed) >>> 0;
    const random = () => {
      state = (state ^ (state << 13)) >>> 0;
      state = (state ^ (state >>> 17)) >>> 0;
      state = (state ^ (state << 5)) >>> 0;
      return state;
    };
    const broad = Array.from({ length: 256 }, () => random() & 255);
    const grain = Array.from({ length: 4096 }, () => random() & 255);

    const noise = (grid, cell, x, y) => {
      const width = TILE / cell;
      const column = Math.floor(x / cell), row = Math.floor(y / cell);
      const u = (x % cell) / cell, v = (y % cell) / cell;
      const sx = u * u * (3 - 2 * u), sy = v * v * (3 - 2 * v);
      const sample = (dx, dy) => grid[((row + dy) % width) * width + (column + dx) % width];
      const top = sample(0, 0) * (1 - sx) + sample(1, 0) * sx;
      const bottom = sample(0, 1) * (1 - sx) + sample(1, 1) * sx;
      return Math.trunc(top * (1 - sy) + bottom * sy);
    };

    const alpha = new Uint8Array(TILE * TILE);
    for (let y = 0; y < TILE; y++) {
      for (let x = 0; x < TILE; x++) {
        const a = 2 + Math.trunc(noise(broad, 16, x, y) * 10 / 255)
          + Math.trunc(noise(grain, 4, x, y) * 8 / 255) + (random() & 7);
        alpha[y * TILE + x] = a;
      }
    }
    // Swift's rounded() rounds halves away from zero.
    const round = v => Math.sign(v) * Math.round(Math.abs(v));
    for (let index = 0; index < 64; index++) {
      const startX = random() % TILE;
      const startY = random() % TILE;
      const angle = (random() % 6283) / 1000;
      const length = (random() % 19) + 8;
      const strength = index % 3 === 0 ? -8 : 16;
      for (let step = 0; step < length; step++) {
        const x = round(startX + Math.cos(angle) * step);
        const y = round(startY + Math.sin(angle) * step);
        const pixel = ((y + TILE) % TILE) * TILE + (x + TILE) % TILE;
        alpha[pixel] = Math.max(1, Math.min(44, alpha[pixel] + strength));
      }
    }
    // .light skips the contrast pass. SumiPaperSurface then removes the uniform wash.
    for (let i = 0; i < alpha.length; i++) alpha[i] = Math.min(20, Math.trunc(Math.max(0, alpha[i] - 13) * 2 / 3));
    return alpha;
  }

  const BASE = { page: [245, 240, 230], card: [255, 252, 246] }; // 0.961/0.941/0.902 and 1/0.988/0.965

  /** HonbakoPaperStock.tile(dark: false, surface:) as RGBA bytes: the base, then the black grain at 0.6. */
  function stockRGBA(surface = 'page') {
    const alpha = tileAlpha();
    const base = BASE[surface];
    const out = new Uint8ClampedArray(TILE * TILE * 4);
    for (let i = 0; i < alpha.length; i++) {
      const k = 1 - 0.6 * alpha[i] / 255;
      out[i * 4] = Math.round(base[0] * k);
      out[i * 4 + 1] = Math.round(base[1] * k);
      out[i * 4 + 2] = Math.round(base[2] * k);
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  globalThis.HonbakoPaper = { TILE, tileAlpha, stockRGBA };
})();
