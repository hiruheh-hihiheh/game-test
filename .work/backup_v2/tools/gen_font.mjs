// Builds the game's own techno typeface as real TrueType files, with no dependencies.
// Run: node tools/gen_font.mjs
import fs from "node:fs";
import path from "node:path";

const OUT = path.resolve("assets/fonts");
fs.mkdirSync(OUT, { recursive: true });

const O = [[.8, 0], [3.2, 0], [4, .8], [4, 5.2], [3.2, 6], [.8, 6], [0, 5.2], [0, .8], [.8, 0]];
const P_BOWL = [[0, 0], [0, 6], [3.2, 6], [4, 5.2], [4, 3.4], [3.2, 2.6], [0, 2.6]];
const dot = (x, y) => [[x, y], [x, y + .35]];

// Glyphs are polylines on a 4x6 grid (y up). w = visual width in grid units.
const G = {
  A: { s: [[[0, 0], [0, 5.2], [.8, 6], [3.2, 6], [4, 5.2], [4, 0]], [[0, 2.5], [4, 2.5]]] },
  B: { s: [[[0, 0], [0, 6], [3.2, 6], [4, 5.2], [4, 3.9], [3.2, 3.1], [0, 3.1]], [[3.2, 3.1], [4, 2.3], [4, .8], [3.2, 0], [0, 0]]] },
  C: { s: [[[4, 6], [.8, 6], [0, 5.2], [0, .8], [.8, 0], [4, 0]]] },
  D: { s: [[[0, 0], [0, 6], [3.2, 6], [4, 5.2], [4, .8], [3.2, 0], [0, 0]]] },
  E: { s: [[[4, 6], [0, 6], [0, 0], [4, 0]], [[0, 3.1], [3.1, 3.1]]] },
  F: { s: [[[4, 6], [0, 6], [0, 0]], [[0, 3.1], [3.1, 3.1]]] },
  G: { s: [[[4, 6], [.8, 6], [0, 5.2], [0, .8], [.8, 0], [3.2, 0], [4, .8], [4, 2.8], [2.2, 2.8]]] },
  H: { s: [[[0, 0], [0, 6]], [[4, 0], [4, 6]], [[0, 3.1], [4, 3.1]]] },
  I: { w: 0, s: [[[0, 0], [0, 6]]] },
  J: { s: [[[4, 6], [4, .8], [3.2, 0], [.8, 0], [0, .8], [0, 1.6]]] },
  K: { s: [[[0, 0], [0, 6]], [[0, 2.9], [1.2, 2.9], [4, 6]], [[1.2, 2.9], [4, 0]]] },
  L: { s: [[[0, 6], [0, 0], [4, 0]]] },
  M: { w: 5, s: [[[0, 0], [0, 6], [2.5, 2.4], [5, 6], [5, 0]]] },
  N: { s: [[[0, 0], [0, 6], [4, 0], [4, 6]]] },
  O: { s: [O] },
  P: { s: [P_BOWL] },
  Q: { s: [O, [[2.4, 1.5], [4, 0]]] },
  R: { s: [P_BOWL, [[1.9, 2.6], [4, 0]]] },
  S: { s: [[[4, 6], [.8, 6], [0, 5.2], [0, 3.9], [.8, 3.1], [3.2, 3.1], [4, 2.3], [4, .8], [3.2, 0], [0, 0]]] },
  T: { s: [[[0, 6], [4, 6]], [[2, 6], [2, 0]]] },
  U: { s: [[[0, 6], [0, .8], [.8, 0], [3.2, 0], [4, .8], [4, 6]]] },
  V: { s: [[[0, 6], [2, 0], [4, 6]]] },
  W: { w: 5.4, s: [[[0, 6], [1.35, 0], [2.7, 4.4], [4.05, 0], [5.4, 6]]] },
  X: { s: [[[0, 0], [4, 6]], [[0, 6], [4, 0]]] },
  Y: { s: [[[0, 6], [2, 3], [4, 6]], [[2, 3], [2, 0]]] },
  Z: { s: [[[0, 6], [4, 6], [0, 0], [4, 0]]] },
  0: { s: [O, [[2, 2.3], [2, 3.7]]] },
  1: { s: [[[.8, 4.7], [2.2, 6], [2.2, 0]]] },
  2: { s: [[[0, 6], [3.2, 6], [4, 5.2], [4, 3.9], [3.2, 3.1], [.8, 3.1], [0, 2.3], [0, 0], [4, 0]]] },
  3: { s: [[[0, 6], [3.2, 6], [4, 5.2], [4, 3.9], [3.2, 3.1], [1, 3.1]], [[3.2, 3.1], [4, 2.3], [4, .8], [3.2, 0], [0, 0]]] },
  4: { s: [[[0, 6], [0, 2.8], [4, 2.8]], [[3.2, 6], [3.2, 0]]] },
  5: { s: [[[4, 6], [0, 6], [0, 3.1], [3.2, 3.1], [4, 2.3], [4, .8], [3.2, 0], [0, 0]]] },
  6: { s: [[[4, 6], [.8, 6], [0, 5.2], [0, .8], [.8, 0], [3.2, 0], [4, .8], [4, 2.3], [3.2, 3.1], [0, 3.1]]] },
  7: { s: [[[0, 6], [4, 6], [1.4, 0]]] },
  8: { s: [O, [[0, 3.1], [4, 3.1]]] },
  9: { s: [[[0, 0], [3.2, 0], [4, .8], [4, 5.2], [3.2, 6], [.8, 6], [0, 5.2], [0, 3.8], [.8, 3], [4, 3]]] },
  ".": { w: 0, s: [dot(0, 0)] },
  ",": { w: .6, s: [[[.6, .5], [0, -.8]]] },
  ":": { w: 0, s: [dot(0, 1), dot(0, 4.2)] },
  "!": { w: 0, s: [[[0, 6], [0, 1.9]], dot(0, 0)] },
  "?": { s: [[[0, 4.9], [0, 5.2], [.8, 6], [3.2, 6], [4, 5.2], [4, 3.9], [3.2, 3.1], [2, 3.1], [2, 1.9]], dot(2, 0)] },
  "/": { w: 3, s: [[[0, 0], [3, 6]]] },
  "-": { w: 2.4, s: [[[0, 3], [2.4, 3]]] },
  "+": { w: 3.2, s: [[[0, 3], [3.2, 3]], [[1.6, 1.4], [1.6, 4.6]]] },
  "=": { w: 3.2, s: [[[0, 2.2], [3.2, 2.2]], [[0, 3.9], [3.2, 3.9]]] },
  "%": { w: 4.4, s: [[[0, 0], [4.4, 6]], [[0, 4.2], [1.3, 4.2], [1.3, 6], [0, 6], [0, 4.2]], [[3.1, 0], [4.4, 0], [4.4, 1.8], [3.1, 1.8], [3.1, 0]]] },
  "'": { w: 0, s: [[[0, 6], [0, 4.5]]] },
  "(": { w: 1.6, s: [[[1.6, 6], [.8, 6], [0, 5.2], [0, .8], [.8, 0], [1.6, 0]]] },
  ")": { w: 1.6, s: [[[0, 6], [.8, 6], [1.6, 5.2], [1.6, .8], [.8, 0], [0, 0]]] },
  "<": { w: 3, s: [[[3, 5.2], [0, 3], [3, .8]]] },
  ">": { w: 3, s: [[[0, 5.2], [3, 3], [0, .8]]] },
  "_": { s: [[[0, 0], [4, 0]]] },
  "#": { s: [[[1.3, 0], [1.3, 6]], [[2.7, 0], [2.7, 6]], [[0, 2], [4, 2]], [[0, 4], [4, 4]]] },
  "*": { w: 3, s: [[[.2, 1.8], [2.8, 4.4]], [[.2, 4.4], [2.8, 1.8]]] },
  "×": { w: 3, s: [[[.2, 1.6], [2.8, 4.2]], [[.2, 4.2], [2.8, 1.6]]] },
  "·": { w: 0, s: [dot(0, 2.9)] },
  "•": { w: .8, s: [[[0, 2.6], [.8, 2.6], [.8, 3.4], [0, 3.4], [0, 2.6]]] },
};

function toGlyph(def, stroke) {
  const unitY = (700 - stroke) / 6;
  const unitX = unitY * 1.08;
  const r = stroke / 2;
  const w = def.w ?? 4;
  const contours = [];
  const addContour = (pts) => {
    let area = 0;
    for (let i = 0; i < pts.length; i++) {
      const [ax, ay] = pts[i], [bx, by] = pts[(i + 1) % pts.length];
      area += ax * by - bx * ay;
    }
    if (area > 0) pts = pts.slice().reverse(); // TrueType fills clockwise contours.
    contours.push(pts.map(([x, y]) => [Math.round(x), Math.round(y)]));
  };
  const X = (x) => r + x * unitX, Y = (y) => r + y * unitY;
  for (const line of def.s) {
    for (let i = 0; i < line.length - 1; i++) {
      const ax = X(line[i][0]), ay = Y(line[i][1]), bx = X(line[i + 1][0]), by = Y(line[i + 1][1]);
      const dx = bx - ax, dy = by - ay, len = Math.hypot(dx, dy) || 1;
      const nx = -dy / len * r, ny = dx / len * r;
      addContour([[ax + nx, ay + ny], [bx + nx, by + ny], [bx - nx, by - ny], [ax - nx, ay - ny]]);
    }
    for (const [px, py] of line) {
      const cx = X(px), cy = Y(py), oct = [];
      const R = r / Math.cos(Math.PI / 8);
      for (let k = 0; k < 8; k++) oct.push([cx + Math.cos(Math.PI / 8 + k * Math.PI / 4) * R, cy + Math.sin(Math.PI / 8 + k * Math.PI / 4) * R]);
      addContour(oct);
    }
  }
  return { contours, adv: Math.round(w * unitX + stroke + Math.max(70, stroke * 1.05)), lsb: 0 };
}

const u16 = (v) => { const b = Buffer.alloc(2); b.writeUInt16BE(v & 0xffff); return b; };
const s16 = (v) => { const b = Buffer.alloc(2); b.writeInt16BE(v); return b; };
const u32 = (v) => { const b = Buffer.alloc(4); b.writeUInt32BE(v >>> 0); return b; };

function encodeGlyph(g) {
  if (!g.contours.length) return Buffer.alloc(0);
  const all = g.contours.flat();
  const xs = all.map((p) => p[0]), ys = all.map((p) => p[1]);
  const parts = [s16(g.contours.length), s16(Math.min(...xs)), s16(Math.min(...ys)), s16(Math.max(...xs)), s16(Math.max(...ys))];
  let n = -1;
  for (const c of g.contours) { n += c.length; parts.push(u16(n)); }
  parts.push(u16(0));
  parts.push(Buffer.alloc(all.length, 1)); // on-curve, 16-bit deltas
  let px = 0, py = 0;
  for (const [x] of all) { parts.push(s16(x - px)); px = x; }
  for (const [, y] of all) { parts.push(s16(y - py)); py = y; }
  let buf = Buffer.concat(parts);
  if (buf.length % 2) buf = Buffer.concat([buf, Buffer.alloc(1)]);
  return buf;
}

function buildFont(family, style, stroke, file) {
  const chars = Object.keys(G);
  const glyphs = [{ contours: [], adv: 500 }, { contours: [], adv: Math.round(stroke + 240) }]; // .notdef, space
  const map = new Map([[32, 1], [160, 1]]);
  for (const ch of chars) {
    const id = glyphs.length;
    glyphs.push(toGlyph(G[ch], stroke));
    map.set(ch.codePointAt(0), id);
    const lower = ch.toLowerCase();
    if (lower !== ch) map.set(lower.codePointAt(0), id);
  }
  const glyf = [], loca = [0];
  let off = 0;
  for (const g of glyphs) { const b = encodeGlyph(g); glyf.push(b); off += b.length; loca.push(off); }
  const hmtx = Buffer.concat(glyphs.map((g) => {
    const xs = g.contours.flat().map((p) => p[0]);
    return Buffer.concat([u16(g.adv), s16(xs.length ? Math.min(...xs) : 0)]);
  }));
  const maxPts = Math.max(...glyphs.map((g) => g.contours.flat().length));
  const maxCnt = Math.max(...glyphs.map((g) => g.contours.length));
  const all = glyphs.flatMap((g) => g.contours.flat());
  const xMin = Math.min(...all.map((p) => p[0])), xMax = Math.max(...all.map((p) => p[0]));
  const yMin = Math.min(...all.map((p) => p[1])), yMax = Math.max(...all.map((p) => p[1]));
  const head = Buffer.concat([u32(0x00010000), u32(0x00010000), u32(0), u32(0x5f0f3cf5), u16(0x000b), u16(1000),
    Buffer.alloc(16), s16(xMin), s16(yMin), s16(xMax), s16(yMax), u16(0), u16(8), s16(2), s16(1), s16(0)]);
  const hhea = Buffer.concat([u32(0x00010000), s16(880), s16(-220), s16(100), u16(Math.max(...glyphs.map((g) => g.adv))), s16(0), s16(0), s16(xMax), s16(1), s16(0), s16(0), Buffer.alloc(8), s16(0), u16(glyphs.length)]);
  const maxp = Buffer.concat([u32(0x00010000), u16(glyphs.length), u16(maxPts), u16(maxCnt), u16(0), u16(0), u16(2), u16(0), u16(0), u16(0), u16(0), u16(0), u16(0), u16(0), u16(0)]);
  // cmap format 4
  const codes = [...map.keys()].sort((a, b) => a - b);
  const segs = [];
  for (const c of codes) {
    const last = segs[segs.length - 1];
    if (last && c === last.end + 1 && map.get(c) === map.get(last.end) + 1) last.end = c;
    else segs.push({ start: c, end: c });
  }
  segs.push({ start: 0xffff, end: 0xffff });
  const segX2 = segs.length * 2;
  const log = Math.floor(Math.log2(segs.length));
  const sub = Buffer.concat([u16(4), u16(16 + segs.length * 8), u16(0), u16(segX2), u16(2 << log), u16(log), u16(segX2 - (2 << log)),
    ...segs.map((s) => u16(s.end)), u16(0), ...segs.map((s) => u16(s.start)),
    ...segs.map((s) => u16(s.start === 0xffff ? 1 : map.get(s.start) - s.start)), ...segs.map(() => u16(0))]);
  const cmap = Buffer.concat([u16(0), u16(1), u16(3), u16(1), u32(12), sub]);
  // name
  const names = [[1, family], [2, style], [3, `${family} ${style} 1.0`], [4, `${family} ${style}`], [5, "Version 1.0"], [6, `${family}-${style}`.replace(/\s/g, "")]];
  let strOff = 0;
  const recs = [], strs = [];
  for (const [id, text] of names) {
    const raw = Buffer.from(text, "utf16le").swap16();
    recs.push(Buffer.concat([u16(3), u16(1), u16(0x409), u16(id), u16(raw.length), u16(strOff)]));
    strs.push(raw); strOff += raw.length;
  }
  const name = Buffer.concat([u16(0), u16(names.length), u16(6 + 12 * names.length), ...recs, ...strs]);
  const os2 = Buffer.concat([u16(3), s16(600), u16(style === "Bold" ? 700 : 400), u16(5), u16(0), s16(650), s16(600), s16(0), s16(140), s16(650), s16(600), s16(0), s16(480), s16(50), s16(250), s16(0), Buffer.alloc(10), Buffer.alloc(16), Buffer.from("VEYR"), u16(style === "Bold" ? 0x20 : 0x40), u16(32), u16(0xffff), s16(880), s16(-220), s16(100), u16(880), u16(220), u32(1), u32(0), s16(500), s16(700), u16(0), u16(32), u16(0)]);
  const post = Buffer.concat([u32(0x00030000), Buffer.alloc(28)]);
  const pad = (b) => (b.length % 4 ? Buffer.concat([b, Buffer.alloc(4 - (b.length % 4))]) : b);
  const tables = {
    "OS/2": os2, cmap, glyf: Buffer.concat(glyf), head, hhea, hmtx,
    loca: Buffer.concat(loca.map((v) => u32(v))), maxp, name, post,
  };
  const tags = Object.keys(tables).sort();
  const num = tags.length, log2 = Math.floor(Math.log2(num));
  const header = Buffer.concat([u32(0x00010000), u16(num), u16(16 << log2), u16(log2), u16(num * 16 - (16 << log2))]);
  const checksum = (b) => { let s = 0; const p = pad(b); for (let i = 0; i < p.length; i += 4) s = (s + p.readUInt32BE(i)) >>> 0; return s; };
  let cursor = 12 + num * 16;
  const dir = [], body = [];
  for (const t of tags) {
    const data = tables[t];
    dir.push(Buffer.concat([Buffer.from(t.padEnd(4, " ")), u32(checksum(data)), u32(cursor), u32(data.length)]));
    const p = pad(data); body.push(p); cursor += p.length;
  }
  const font = Buffer.concat([header, ...dir, ...body]);
  const headOffset = dir[tags.indexOf("head")].readUInt32BE(8);
  font.writeUInt32BE((0xb1b0afba - checksum(font)) >>> 0, headOffset + 8);
  fs.writeFileSync(path.join(OUT, file), font);
  console.log(file, font.length, "bytes,", glyphs.length, "glyphs");
}

buildFont("Starfall", "Regular", 92, "starfall-regular.ttf");
buildFont("Starfall", "Bold", 148, "starfall-bold.ttf");
