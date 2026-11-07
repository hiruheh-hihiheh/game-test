// Paints one seamless, vertically tiling nebula backdrop per sector.
// Run: node tools/gen_backgrounds.mjs
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const OUT = path.resolve("assets/backgrounds");
fs.mkdirSync(OUT, { recursive: true });
const W = 360, H = 720;

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}
function writePng(file, rgb) {
  const raw = Buffer.alloc((W * 3 + 1) * H);
  for (let y = 0; y < H; y++) {
    const row = y * (W * 3 + 1);
    raw[row] = 0;
    for (let i = 0; i < W * 3; i++) raw[row + 1 + i] = rgb[y * W * 3 + i];
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]));
}

function makeNoise(seed) {
  let s = seed >>> 0;
  const rand = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
  const table = new Float32Array(256 * 256);
  for (let i = 0; i < table.length; i++) table[i] = rand();
  const fade = (t) => t * t * (3 - 2 * t);
  // Value noise that repeats every py cells on y, so the art tiles when it scrolls.
  const noise = (x, y, py) => {
    const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
    const g = (a, b) => table[(((a % 256) + 256) % 256) * 256 + ((((b % py) + py) % py) % 256)];
    const u = fade(xf), v = fade(yf);
    return (g(xi, yi) * (1 - u) + g(xi + 1, yi) * u) * (1 - v) + (g(xi, yi + 1) * (1 - u) + g(xi + 1, yi + 1) * u) * v;
  };
  const fbm = (x, y, py, oct) => {
    let total = 0, amp = 0.5, f = 1, norm = 0;
    for (let i = 0; i < oct; i++) { total += noise(x * f, y * f, py * f) * amp; norm += amp; amp *= 0.5; f *= 2; }
    return total / norm;
  };
  return { fbm, rand };
}

const SECTORS = [
  { base: [5, 9, 26], a: [26, 86, 170], b: [10, 160, 180], c: [90, 60, 190], seed: 11, planet: { x: 285, y: 170, r: 92, col: [70, 130, 210] } },
  { base: [18, 7, 14], a: [170, 62, 20], b: [210, 120, 30], c: [120, 20, 70], seed: 29, planet: { x: 70, y: 440, r: 70, col: [230, 110, 40] } },
  { base: [13, 5, 28], a: [120, 30, 170], b: [210, 40, 140], c: [50, 50, 190], seed: 53, planet: { x: 300, y: 500, r: 105, col: [190, 70, 200] } },
  { base: [4, 16, 22], a: [20, 120, 130], b: [120, 210, 220], c: [30, 70, 130], seed: 71, planet: { x: 60, y: 150, r: 84, col: [130, 220, 225] } },
  { base: [20, 4, 10], a: [160, 20, 40], b: [230, 70, 60], c: [80, 20, 90], seed: 97, planet: { x: 270, y: 330, r: 120, col: [225, 60, 60] } },
  { base: [14, 10, 6], a: [150, 105, 30], b: [235, 190, 90], c: [80, 40, 120], seed: 131, planet: { x: 180, y: 120, r: 130, col: [240, 190, 90] } },
];

SECTORS.forEach((cfg, index) => {
  const { fbm } = makeNoise(cfg.seed);
  const rgb = new Uint8Array(W * H * 3);
  const cellsY = 8, sx = cellsY / H;
  const p = cfg.planet;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const nx = x * sx, ny = y * sx;
      // Domain warp gives the clouds wispy folds instead of round blobs.
      const wx = fbm(nx + 3.1, ny, cellsY, 3) - 0.5, wy = fbm(nx, ny + 2.3, cellsY, 3) - 0.5;
      const n1 = fbm(nx + wx * 2.6, ny + wy * 2.6, cellsY, 5);
      const n2 = fbm(nx * 2 + 8.4, ny * 2, cellsY * 2, 4);
      const n3 = fbm(nx * 0.75 + 20.0, ny * 0.75 * (1 / 0.75), cellsY, 4);
      const cloud = Math.pow(Math.max(0, (n1 - 0.40) * 3.0), 2.0);
      const veil = Math.pow(Math.max(0, (n2 - 0.46) * 3.2), 2.2) * cloud * 1.6;
      const haze = Math.pow(Math.max(0, (n3 - 0.42) * 2.6), 2.0);
      let r = cfg.base[0], g = cfg.base[1], b = cfg.base[2];
      r += cfg.a[0] * cloud * 0.52 + cfg.b[0] * veil * 0.70 + cfg.c[0] * haze * 0.28;
      g += cfg.a[1] * cloud * 0.52 + cfg.b[1] * veil * 0.70 + cfg.c[1] * haze * 0.28;
      b += cfg.a[2] * cloud * 0.52 + cfg.b[2] * veil * 0.70 + cfg.c[2] * haze * 0.28;
      // Distant planet with a lit limb and soft atmosphere.
      for (const off of [-H, 0, H]) {
        const dx = (x - p.x) / p.r, dy = (y + off - p.y) / p.r, d2 = dx * dx + dy * dy, d = Math.sqrt(d2);
        if (d < 1.28) {
          if (d < 1) {
            const nz = Math.sqrt(1 - d2);
            const light = Math.max(0, -dx * 0.55 - dy * 0.62 + nz * 0.55);
            const bands = 0.72 + 0.28 * fbm(dx * 2.2 + 30, dy * 6 + 30, 64, 4);
            const shade = Math.pow(light, 1.5) * bands * 0.62;
            r = r * 0.16 + p.col[0] * shade;
            g = g * 0.16 + p.col[1] * shade;
            b = b * 0.16 + p.col[2] * shade;
          }
          const rim = Math.exp(-Math.pow((d - 1) * 13, 2)) * Math.max(0.12, -dx * 0.7 - dy * 0.7 + 0.35);
          r += p.col[0] * rim * 0.55; g += p.col[1] * rim * 0.55; b += p.col[2] * rim * 0.55;
        }
      }
      const i = (y * W + x) * 3;
      // Tiny dither removes the banding that dark gradients get on phone screens.
      const d = (((x * 7 + y * 13) ^ (x * y)) & 3) - 1.5;
      rgb[i] = Math.min(255, Math.max(0, r + d));
      rgb[i + 1] = Math.min(255, Math.max(0, g + d));
      rgb[i + 2] = Math.min(255, Math.max(0, b + d));
    }
  }
  const file = path.join(OUT, `sector_${index + 1}.png`);
  writePng(file, rgb);
  console.log(path.basename(file), fs.statSync(file).size);
});
