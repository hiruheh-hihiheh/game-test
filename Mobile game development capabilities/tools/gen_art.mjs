// Paints original ship, enemy and boss art with a small software rasteriser.
// Everything is drawn from polygons at 2x and downsampled, so it needs no image editor.
// Run: node tools/gen_art.mjs [name]
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const OUT = path.resolve("assets/starfall/gen");
fs.mkdirSync(OUT, { recursive: true });
const S = 2, SIZE = 512, N = SIZE * S;

let seed = 4242;
const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const mix = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const lift = (c, k) => [c[0] * k, c[1] * k, c[2] * k];

// Smooth value noise, used to give flat panels a worn metal or organic surface.
const NT = new Float32Array(65536).map(() => rnd());
const vnoise = (x, y) => {
  const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
  const g = (a, b) => NT[((a & 255) << 8) | (b & 255)];
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  return (g(xi, yi) * (1 - u) + g(xi + 1, yi) * u) * (1 - v) + (g(xi, yi + 1) * (1 - u) + g(xi + 1, yi + 1) * u) * v;
};
const fbm = (x, y) => vnoise(x, y) * 0.55 + vnoise(x * 2.1, y * 2.1) * 0.3 + vnoise(x * 4.3, y * 4.3) * 0.15;

class Art {
  constructor() {
    this.px = new Float32Array(N * N * 4);
  }
  blend(i, r, g, b, a) {
    const p = this.px, ia = 1 - a;
    p[i] = r * a + p[i] * ia; p[i + 1] = g * a + p[i + 1] * ia; p[i + 2] = b * a + p[i + 2] * ia;
    p[i + 3] = a + p[i + 3] * ia;
  }
  fill(pts, paint) {
    let minY = 1e9, maxY = -1e9;
    const P = pts.map(([x, y]) => [x * S, y * S]);
    for (const [, y] of P) { minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
    minY = clamp(Math.floor(minY), 0, N - 1); maxY = clamp(Math.ceil(maxY), 0, N - 1);
    for (let y = minY; y <= maxY; y++) {
      const xs = [];
      for (let i = 0; i < P.length; i++) {
        const [ax, ay] = P[i], [bx, by] = P[(i + 1) % P.length];
        if ((ay <= y + 0.5 && by > y + 0.5) || (by <= y + 0.5 && ay > y + 0.5)) xs.push(ax + (y + 0.5 - ay) / (by - ay) * (bx - ax));
      }
      xs.sort((a, b) => a - b);
      for (let k = 0; k + 1 < xs.length; k += 2) {
        const x0 = clamp(Math.ceil(xs[k]), 0, N), x1 = clamp(Math.floor(xs[k + 1]), 0, N);
        for (let x = x0; x < x1; x++) {
          const c = paint(x / S, y / S);
          this.blend((y * N + x) * 4, c[0], c[1], c[2], c[3] ?? 1);
        }
      }
    }
  }
  stroke(pts, closed, width, color, alpha = 1) {
    const r = width * S * 0.5, n = closed ? pts.length : pts.length - 1;
    for (let i = 0; i < n; i++) {
      const ax = pts[i][0] * S, ay = pts[i][1] * S, bx = pts[(i + 1) % pts.length][0] * S, by = pts[(i + 1) % pts.length][1] * S;
      const x0 = clamp(Math.floor(Math.min(ax, bx) - r - 1), 0, N - 1), x1 = clamp(Math.ceil(Math.max(ax, bx) + r + 1), 0, N - 1);
      const y0 = clamp(Math.floor(Math.min(ay, by) - r - 1), 0, N - 1), y1 = clamp(Math.ceil(Math.max(ay, by) + r + 1), 0, N - 1);
      const dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy || 1;
      for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
        const t = clamp(((x - ax) * dx + (y - ay) * dy) / l2, 0, 1);
        const qx = ax + dx * t - x, qy = ay + dy * t - y;
        if (qx * qx + qy * qy <= r * r) this.blend((y * N + x) * 4, color[0], color[1], color[2], alpha);
      }
    }
  }
  glow(cx, cy, radius, color, strength = 1) {
    const R = radius * S, X = cx * S, Y = cy * S;
    const x0 = clamp(Math.floor(X - R), 0, N - 1), x1 = clamp(Math.ceil(X + R), 0, N - 1);
    const y0 = clamp(Math.floor(Y - R), 0, N - 1), y1 = clamp(Math.ceil(Y + R), 0, N - 1);
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
      const d = Math.hypot(x - X, y - Y) / R;
      if (d >= 1) continue;
      const k = Math.pow(1 - d, 2.2) * strength, i = (y * N + x) * 4;
      this.px[i] += color[0] * k; this.px[i + 1] += color[1] * k; this.px[i + 2] += color[2] * k;
      this.px[i + 3] = Math.max(this.px[i + 3], Math.min(1, k * 1.4));
    }
  }
  save(name) {
    const out = Buffer.alloc((SIZE * 4 + 1) * SIZE);
    for (let y = 0; y < SIZE; y++) {
      const row = y * (SIZE * 4 + 1);
      for (let x = 0; x < SIZE; x++) {
        let r = 0, g = 0, b = 0, a = 0;
        for (let sy = 0; sy < S; sy++) for (let sx = 0; sx < S; sx++) {
          const i = ((y * S + sy) * N + x * S + sx) * 4;
          r += this.px[i]; g += this.px[i + 1]; b += this.px[i + 2]; a += this.px[i + 3];
        }
        const n = S * S; a /= n;
        const o = row + 1 + x * 4;
        // Stored premultiplied while painting, so divide alpha back out for PNG.
        const k = a > 0.0001 ? 1 / (a * n) : 0;
        out[o] = clamp(r * k, 0, 255); out[o + 1] = clamp(g * k, 0, 255); out[o + 2] = clamp(b * k, 0, 255); out[o + 3] = clamp(a * 255, 0, 255);
      }
    }
    writePng(path.join(OUT, name + ".png"), out);
    console.log(name);
  }
}

function crc32(buf) {
  let crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    let c = (crc ^ buf[n]) & 0xff;
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
function writePng(file, raw) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(SIZE, 0); ihdr.writeUInt32BE(SIZE, 4); ihdr[8] = 8; ihdr[9] = 6;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]));
}

const INK = [8, 10, 20];
const mirror = (pts) => pts.map(([x, y]) => [512 - x, y]).reverse();
const ell = (cx, cy, rx, ry, n = 40, rot = 0) => Array.from({ length: n }, (_, i) => {
  const a = i / n * Math.PI * 2, x = Math.cos(a) * rx, y = Math.sin(a) * ry;
  return [cx + x * Math.cos(rot) - y * Math.sin(rot), cy + x * Math.sin(rot) + y * Math.cos(rot)];
});
const blob = (cx, cy, rx, ry, wob, seedOff, n = 48) => Array.from({ length: n }, (_, i) => {
  const a = i / n * Math.PI * 2, k = 1 + (fbm(Math.cos(a) * 2 + seedOff, Math.sin(a) * 2 + seedOff) - 0.5) * wob;
  return [cx + Math.cos(a) * rx * k, cy + Math.sin(a) * ry * k];
});
const arcBand = (cx, cy, r0, r1, a0, a1, n = 20) => {
  const out = [];
  for (let i = 0; i <= n; i++) { const a = a0 + (a1 - a0) * i / n; out.push([cx + Math.cos(a) * r1, cy + Math.sin(a) * r1]); }
  for (let i = n; i >= 0; i--) { const a = a0 + (a1 - a0) * i / n; out.push([cx + Math.cos(a) * r0, cy + Math.sin(a) * r0]); }
  return out;
};

// A panel: dark outline, shaded fill, worn surface and a lit top-left edge.
function panel(g, pts, light, dark, opt = {}) {
  const list = opt.mirror === false ? [pts] : [pts, mirror(pts)];
  for (const P of list) {
    let y0 = 1e9, y1 = -1e9, x0 = 1e9, x1 = -1e9;
    for (const [x, y] of P) { y0 = Math.min(y0, y); y1 = Math.max(y1, y); x0 = Math.min(x0, x); x1 = Math.max(x1, x); }
    const ang = (opt.angle ?? 70) * Math.PI / 180, ca = Math.cos(ang), sa = Math.sin(ang);
    const span = Math.abs(ca) * (x1 - x0) + Math.abs(sa) * (y1 - y0) || 1;
    const wear = opt.wear ?? 0.13, scale = opt.scale ?? 0.045;
    g.stroke(P, true, opt.ow ?? 7, opt.ink ?? INK);
    g.fill(P, (x, y) => {
      const t = clamp(((x - x0) * ca + (y - y0) * sa) / span, 0, 1);
      const c = mix(light, dark, t);
      const n = 1 + (fbm(x * scale, y * scale) - 0.5) * wear * 2;
      return lift(c, n);
    });
    if (opt.bevel !== false) {
      for (let i = 0; i < P.length; i++) {
        const a = P[i], b = P[(i + 1) % P.length];
        const dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy) || 1;
        // Sign of the polygon decides which way is outward.
        let area = 0;
        for (let k = 0; k < P.length; k++) { const q = P[k], w = P[(k + 1) % P.length]; area += q[0] * w[1] - w[0] * q[1]; }
        const s = area > 0 ? 1 : -1;
        const nx = dy / len * s, ny = -dx / len * s; // outward normal
        if (ny < -0.25 || nx < -0.6) {
          const ix = -nx * 3.6, iy = -ny * 3.6;
          g.stroke([[a[0] + ix, a[1] + iy], [b[0] + ix, b[1] + iy]], false, 2.4, mix(light, [255, 255, 255], 0.65), 0.72);
        }
      }
    }
  }
}
const line = (g, a, b, w, c, alpha = 0.8, mir = true) => { g.stroke([a, b], false, w, c, alpha); if (mir) g.stroke([[512 - a[0], a[1]], [512 - b[0], b[1]]], false, w, c, alpha); };
const lights = (g, pts, r, color, strength = 0.9) => {
  for (const [x, y] of pts) {
    for (const X of [x, 512 - x]) {
      g.glow(X, y, r * 2.8, color, strength * 0.75);
      g.fill(ell(X, y, r, r, 14), () => mix(color, [255, 255, 255], 0.55));
    }
  }
};
const flame = (g, x, y, w, h, core = [255, 240, 170], outer = [255, 130, 30]) => {
  for (const X of x === 256 ? [256] : [x, 512 - x]) {
    g.glow(X, y + h * 0.4, h * 0.95, outer, 0.8);
    g.fill([[X - w, y], [X + w, y], [X, y + h]], (px, py) => mix(outer, [255, 70, 20], clamp((py - y) / h, 0, 1)));
    g.fill([[X - w * 0.55, y], [X + w * 0.55, y], [X, y + h * 0.66]], () => core);
  }
};
const cockpit = (g, pts, a = [120, 235, 255], b = [14, 70, 130]) => panel(g, pts, a, b, { mirror: false, ow: 5, angle: 80, wear: 0 });

// ---------- Player ships (nose up) ----------

const STEEL = [226, 234, 244], STEEL_D = [120, 134, 156];
const art = {
  ship_lancer(g) {
    // A long needle: the silhouette says "sniper" before any stats do.
    flame(g, 256, 410, 17, 76);
    flame(g, 218, 392, 9, 42);
    panel(g, [[214, 300], [150, 372], [120, 398], [152, 404], [226, 382]], [130, 90, 230], [52, 30, 120]);
    panel(g, [[226, 230], [196, 300], [184, 372], [220, 400], [232, 330]], STEEL, STEEL_D);
    panel(g, [[256, 26], [278, 140], [292, 300], [286, 400], [256, 420], [226, 400], [220, 300], [234, 140]], STEEL, [150, 160, 190], { mirror: false });
    panel(g, [[256, 26], [266, 110], [256, 200], [246, 110]], [190, 140, 255], [100, 60, 210], { mirror: false, ow: 4 });
    cockpit(g, [[256, 228], [272, 262], [268, 306], [256, 318], [244, 306], [240, 262]]);
    line(g, [236, 150], [226, 300], 3, INK, 0.55);
    line(g, [204, 330], [168, 382], 3, [220, 200, 255], 0.8);
    lights(g, [[200, 360]], 5, [190, 130, 255]);
    g.glow(256, 60, 42, [180, 130, 255], 0.75);
  },
  ship_warden(g) {
    // Broad and blocky, with shoulder pods and a shield-like prow.
    flame(g, 214, 416, 17, 56);
    flame(g, 256, 416, 12, 46);
    panel(g, [[150, 200], [84, 232], [62, 320], [92, 400], [170, 408], [184, 300]], [120, 190, 170], [34, 84, 84]);
    panel(g, [[96, 250], [76, 322], [100, 378], [132, 378], [136, 262]], [50, 74, 86], [20, 32, 44], { ow: 5 });
    for (const y of [278, 316, 352]) { lights(g, [[108, y]], 6, [90, 255, 190], 0.65); }
    panel(g, [[256, 96], [332, 140], [364, 246], [346, 396], [256, 424], [166, 396], [148, 246], [180, 140]], STEEL, [110, 128, 148], { mirror: false });
    panel(g, [[256, 62], [314, 118], [290, 196], [256, 216], [222, 196], [198, 118]], [120, 230, 190], [30, 110, 100], { mirror: false });
    cockpit(g, [[256, 230], [290, 256], [286, 310], [256, 330], [226, 310], [222, 256]]);
    line(g, [188, 214], [196, 380], 4, INK, 0.5);
    line(g, [150, 250], [186, 300], 3, INK, 0.45);
    lights(g, [[172, 150]], 6, [90, 255, 190]);
  },
  ship_magpie(g) {
    // Forward-swept claws and a stubby body: a scavenger built to get close.
    flame(g, 228, 372, 12, 58);
    panel(g, [[206, 190], [128, 84], [86, 58], [100, 150], [150, 262], [206, 300]], [255, 208, 96], [130, 76, 22]);
    panel(g, [[128, 84], [86, 58], [60, 112], [100, 150]], [60, 58, 72], [20, 20, 30], { ow: 6 });
    panel(g, [[190, 288], [120, 276], [96, 322], [168, 360], [216, 344]], [62, 60, 76], [22, 22, 34]);
    panel(g, [[256, 110], [300, 170], [316, 290], [292, 372], [256, 386], [220, 372], [196, 290], [212, 170]], [78, 76, 94], [26, 26, 38], { mirror: false });
    panel(g, [[256, 150], [286, 200], [292, 272], [256, 300], [220, 272], [226, 200]], [255, 224, 130], [176, 104, 30], { mirror: false, ow: 5 });
    cockpit(g, [[256, 176], [272, 204], [266, 246], [256, 256], [246, 246], [240, 204]], [255, 240, 170], [150, 80, 20]);
    line(g, [150, 150], [196, 250], 3, INK, 0.5);
    lights(g, [[124, 120], [150, 316]], 5, [255, 200, 90]);
  },
  // ---------- Allies and neutrals ----------
  ally_hauler(g) {
    flame(g, 200, 430, 13, 44); flame(g, 256, 436, 14, 44);
    panel(g, [[256, 84], [346, 150], [362, 420], [150, 420], [166, 150]], STEEL, [120, 132, 150], { mirror: false });
    for (const y of [176, 244, 312]) panel(g, [[176, y], [336, y], [342, y + 54], [170, y + 54]], [255, 190, 70], [190, 110, 24], { mirror: false, ow: 5 });
    panel(g, [[150, 210], [96, 250], [96, 380], [150, 400]], [100, 190, 230], [30, 80, 130]);
    cockpit(g, [[256, 104], [300, 138], [256, 162], [212, 138]]);
    lights(g, [[112, 300]], 6, [120, 240, 255]);
  },
  // ---------- Debris Belt ----------
  wreck_a(g) {
    panel(g, [[120, 180], [230, 120], [356, 150], [400, 250], [360, 330], [240, 300], [170, 370], [100, 300]], [120, 128, 142], [44, 48, 60], { mirror: false, scale: 0.03, wear: 0.3 });
    panel(g, [[230, 120], [356, 150], [320, 220], [216, 200]], [70, 78, 94], [30, 34, 46], { mirror: false, ow: 5 });
    line(g, [150, 230], [250, 250], 5, INK, 0.7, false);
    line(g, [250, 250], [240, 300], 5, INK, 0.7, false);
    g.stroke([[350, 270], [316, 260], [300, 290]], false, 7, [255, 150, 60], 0.9);
    g.glow(322, 270, 46, [255, 120, 40], 0.5);
    for (const [x, y] of [[170, 210], [200, 280], [290, 170]]) g.fill(ell(x, y, 7, 7, 10), () => [24, 26, 36]);
  },
  wreck_b(g) {
    panel(g, [[180, 90], [300, 110], [346, 240], [320, 400], [230, 420], [170, 330], [146, 200]], [132, 138, 150], [46, 50, 62], { mirror: false, scale: 0.03, wear: 0.3 });
    panel(g, [[180, 90], [300, 110], [280, 190], [196, 180]], [76, 84, 100], [30, 34, 46], { mirror: false, ow: 5 });
    panel(g, [[346, 240], [424, 200], [430, 260], [336, 320]], [100, 106, 122], [40, 44, 56], { mirror: false, ow: 5 });
    line(g, [190, 240], [300, 270], 5, INK, 0.7, false);
    line(g, [220, 300], [210, 380], 5, INK, 0.6, false);
    g.glow(250, 330, 40, [120, 220, 255], 0.5);
  },
  // ---------- Ember Drift ----------
  fuel_tank(g) {
    panel(g, ell(256, 256, 110, 160, 44), [255, 190, 80], [150, 60, 20], { mirror: false, scale: 0.05 });
    for (const y of [150, 256, 362]) g.stroke([[150, y], [362, y]], false, 14, [40, 26, 26], 0.9);
    panel(g, [[206, 74], [306, 74], [316, 104], [196, 104]], [80, 76, 86], [24, 24, 34], { mirror: false, ow: 5 });
    panel(g, [[210, 410], [302, 410], [316, 440], [196, 440]], [80, 76, 86], [24, 24, 34], { mirror: false, ow: 5 });
    panel(g, [[256, 190], [316, 300], [196, 300]], [255, 240, 120], [240, 170, 30], { mirror: false, ow: 6, bevel: false });
    g.fill(ell(256, 282, 7, 7, 10), () => INK);
    g.fill([[250, 222], [262, 222], [259, 266], [253, 266]], () => INK);
    g.glow(256, 256, 170, [255, 110, 30], 0.3);
  },
  cinder(g) {
    // A burning dart that hunts the player.
    g.glow(256, 290, 150, [255, 120, 30], 0.7);
    flame(g, 256, 150, 42, -120, [255, 240, 170], [255, 110, 20]);
    panel(g, [[256, 440], [320, 300], [300, 170], [256, 120], [212, 170], [192, 300]], [100, 60, 50], [30, 16, 18], { mirror: false, scale: 0.08 });
    panel(g, [[220, 220], [120, 130], [150, 260], [204, 300]], [255, 150, 50], [150, 40, 20]);
    panel(g, [[256, 420], [282, 310], [256, 250], [230, 310]], [255, 220, 110], [255, 110, 30], { mirror: false, ow: 4, bevel: false });
  },
  // ---------- Violet Nursery ----------
  pod(g) {
    g.glow(256, 256, 190, [255, 60, 190], 0.34);
    panel(g, blob(256, 262, 140, 176, 0.3, 3.1), [226, 120, 220], [70, 20, 90], { mirror: false, scale: 0.02, wear: 0.4, ow: 9, bevel: false, angle: 60 });
    g.fill(blob(256, 262, 94, 124, 0.26, 7.1), (x, y) => { const k = fbm(x * 0.03, y * 0.03); return mix([255, 120, 220], [120, 20, 140], k); });
    g.stroke(blob(256, 262, 94, 124, 0.26, 7.1), true, 5, [255, 190, 240], 0.6);
    g.fill(blob(256, 270, 40, 56, 0.4, 2.2), () => [40, 8, 60]);
    g.glow(256, 262, 90, [255, 150, 240], 0.5);
    for (const [a, r] of [[0.7, 150], [2.1, 160], [3.9, 150], [5.3, 162]]) g.stroke([[256 + Math.cos(a) * 130, 262 + Math.sin(a) * 160], [256 + Math.cos(a) * r * 1.2, 262 + Math.sin(a) * r * 1.34]], false, 12, [100, 30, 120], 1);
  },
  swarmlet(g) {
    g.glow(256, 256, 170, [255, 70, 200], 0.4);
    panel(g, [[256, 460], [340, 300], [430, 170], [330, 180], [256, 120], [182, 180], [82, 170], [172, 300]], [255, 120, 210], [110, 20, 120], { mirror: false, ow: 12, scale: 0.03, wear: 0.3 });
    g.fill(ell(226, 250, 22, 30, 16), () => [255, 240, 150]);
    g.fill(ell(286, 250, 22, 30, 16), () => [255, 240, 150]);
    g.fill(ell(226, 256, 9, 16, 12), () => INK);
    g.fill(ell(286, 256, 9, 16, 12), () => INK);
  },
  brood(g) {
    // A swollen flying nest: reads as "kill me first".
    g.glow(256, 280, 230, [220, 50, 200], 0.3);
    for (const [a, b] of [[[150, 150], [50, 60]], [[110, 260], [20, 280]], [[150, 370], [70, 470]]]) {
      g.stroke([a, [(a[0] + b[0]) / 2 - 30, (a[1] + b[1]) / 2], b], false, 22, [60, 16, 80], 1);
      g.stroke([[512 - a[0], a[1]], [512 - (a[0] + b[0]) / 2 + 30, (a[1] + b[1]) / 2], [512 - b[0], b[1]]], false, 22, [60, 16, 80], 1);
    }
    panel(g, blob(256, 256, 180, 170, 0.28, 5.5), [190, 80, 200], [50, 14, 76], { mirror: false, scale: 0.02, wear: 0.4, ow: 10, bevel: false });
    for (const [x, y, r] of [[196, 206, 46], [316, 206, 46], [256, 310, 56], [176, 300, 32], [336, 300, 32]]) {
      g.fill(blob(x, y, r, r, 0.2, x * 0.1), (px, py) => mix([255, 170, 240], [200, 40, 180], fbm(px * 0.04, py * 0.04)));
      g.stroke(blob(x, y, r, r, 0.2, x * 0.1), true, 5, [50, 10, 70], 1);
      g.glow(x, y, r * 1.1, [255, 120, 230], 0.4);
    }
  },
  // ---------- Pale Graveyard ----------
  sentinel(g) {
    // A dormant gun platform: ring base with a single long barrel.
    panel(g, [[256, 90], [352, 150], [392, 256], [352, 362], [256, 422], [160, 362], [120, 256], [160, 150]], [188, 214, 226], [60, 84, 104], { mirror: false, scale: 0.04 });
    panel(g, ell(256, 256, 88, 88, 32), [90, 120, 140], [24, 38, 54], { mirror: false, ow: 7 });
    panel(g, [[230, 268], [282, 268], [272, 480], [240, 480]], [214, 234, 244], [90, 112, 130], { mirror: false, ow: 6 });
    panel(g, ell(256, 256, 44, 44, 24), [170, 250, 255], [40, 130, 190], { mirror: false, ow: 6, wear: 0 });
    g.glow(256, 256, 88, [130, 240, 255], 0.6);
    for (let i = 0; i < 6; i++) { const a = i / 6 * Math.PI * 2 + 0.5; g.fill(ell(256 + Math.cos(a) * 128, 256 + Math.sin(a) * 128, 8, 8, 10), () => [150, 240, 255]); }
  },
  revenant(g) {
    // Frozen derelict fighter: broken wing, jagged ice growth.
    panel(g, [[256, 462], [298, 340], [300, 200], [256, 120], [212, 200], [214, 340]], [176, 200, 216], [64, 84, 104], { mirror: false, scale: 0.05 });
    panel(g, [[300, 210], [430, 120], [414, 230], [300, 320]], [150, 176, 196], [50, 70, 90], { mirror: false });
    panel(g, [[212, 210], [120, 150], [90, 96], [100, 214], [212, 312]], [150, 176, 196], [50, 70, 90], { mirror: false });
    for (const [x, y, s] of [[150, 160, 1], [352, 170, 0.8], [256, 180, 1.1], [290, 310, 0.8], [216, 310, 0.7]]) {
      panel(g, [[x, y - 78 * s], [x + 26 * s, y + 16 * s], [x - 22 * s, y + 20 * s]], [240, 255, 255], [120, 210, 240], { mirror: false, ow: 5, wear: 0.04 });
    }
    cockpit(g, [[256, 270], [276, 320], [256, 350], [236, 320]], [255, 110, 90], [120, 20, 30]);
    g.glow(256, 310, 60, [255, 80, 70], 0.5);
  },
  // ---------- Crimson Front ----------
  bomber(g) {
    panel(g, [[256, 470], [330, 360], [460, 290], [430, 180], [322, 200], [300, 120], [212, 120], [190, 200], [82, 180], [52, 290], [182, 360]], [120, 60, 66], [36, 16, 24], { mirror: false, scale: 0.05 });
    panel(g, [[256, 410], [300, 300], [290, 170], [222, 170], [212, 300]], [232, 80, 74], [120, 24, 34], { mirror: false, ow: 6 });
    for (const x of [120, 170]) panel(g, ell(x, 262, 20, 42, 16), [40, 42, 52], [12, 12, 20]);
    cockpit(g, [[256, 340], [276, 290], [256, 250], [236, 290]], [255, 210, 120], [150, 50, 20]);
    flame(g, 228, 124, 10, -44, [255, 230, 200], [255, 70, 50]);
  },
  frigate(g) {
    // Side-on warship that crosses the arena. Nose points right.
    flame(g, 60, 256, 0, 0);
    panel(g, [[476, 256], [400, 214], [300, 190], [120, 190], [52, 226], [52, 286], [120, 322], [300, 322], [400, 298]], [176, 70, 72], [58, 18, 30], { mirror: false, angle: 90, scale: 0.03 });
    panel(g, [[300, 190], [262, 140], [160, 140], [120, 190]], [120, 46, 56], [40, 14, 24], { mirror: false, ow: 6 });
    panel(g, [[300, 322], [262, 372], [160, 372], [120, 322]], [90, 34, 44], [30, 10, 20], { mirror: false, ow: 6 });
    for (const x of [150, 214, 278, 342]) panel(g, ell(x, 256, 22, 22, 18), [220, 220, 228], [80, 84, 96], { mirror: false, ow: 5 });
    for (const x of [150, 214, 278, 342]) g.stroke([[x, 256], [x, 334]], false, 11, [30, 30, 40], 1);
    g.glow(40, 256, 70, [255, 120, 60], 0.8);
  },
  // ---------- Sunken Core ----------
  wraith(g) {
    g.glow(256, 240, 210, [150, 90, 255], 0.35);
    panel(g, [[256, 476], [312, 330], [420, 136], [330, 190], [300, 90], [256, 170], [212, 90], [182, 190], [92, 136], [200, 330]], [100, 86, 170], [18, 14, 44], { mirror: false, scale: 0.05, ink: [40, 20, 90] });
    panel(g, [[256, 400], [290, 280], [256, 200], [222, 280]], [220, 180, 255], [120, 60, 230], { mirror: false, ow: 5, wear: 0 });
    g.fill(ell(256, 276, 15, 34, 16), () => [255, 245, 200]);
    g.glow(256, 276, 76, [255, 220, 170], 0.6);
  },
  elite_dread(g) {
    // Mini-boss for elite levels: a heavy wedge with twin prongs.
    panel(g, [[256, 494], [300, 400], [394, 470], [440, 330], [474, 180], [380, 210], [346, 90], [166, 90], [132, 210], [38, 180], [72, 330], [118, 470], [212, 400]], [86, 86, 110], [20, 20, 34], { mirror: false, scale: 0.035 });
    panel(g, [[166, 150], [346, 150], [320, 300], [292, 380], [220, 380], [192, 300]], [200, 60, 110], [80, 16, 60], { mirror: false, ow: 7 });
    panel(g, ell(256, 240, 58, 58, 28), [255, 214, 120], [230, 90, 40], { mirror: false, ow: 7, wear: 0 });
    g.fill(ell(256, 240, 20, 46, 16), () => INK);
    g.glow(256, 240, 110, [255, 150, 70], 0.5);
    lights(g, [[120, 300], [150, 390]], 7, [255, 70, 120]);
  },
  // ---------- Boss parts ----------
  boss_warden_core(g) {
    // A hollowed asteroid fortress around a blazing gravity engine.
    g.glow(256, 256, 250, [90, 200, 255], 0.3);
    panel(g, blob(256, 256, 214, 200, 0.3, 1.7, 56), [150, 156, 170], [44, 48, 62], { mirror: false, scale: 0.028, wear: 0.45, ow: 10, angle: 50 });
    for (const [x, y, r] of [[136, 190, 46], [376, 210, 54], [176, 356, 40], [356, 346, 44]]) {
      panel(g, blob(x, y, r, r * 0.86, 0.34, x * 0.03), [188, 194, 206], [80, 84, 96], { mirror: false, scale: 0.05, wear: 0.4, ow: 6 });
    }
    panel(g, [[256, 120], [346, 170], [376, 256], [346, 342], [256, 392], [166, 342], [136, 256], [166, 170]], [90, 104, 124], [22, 28, 44], { mirror: false, ow: 8 });
    panel(g, ell(256, 256, 88, 88, 36), [210, 250, 255], [40, 150, 230], { mirror: false, ow: 7, wear: 0, bevel: false });
    g.fill(ell(256, 256, 40, 40, 24), () => [255, 255, 255]);
    g.glow(256, 256, 150, [130, 230, 255], 0.9);
  },
  boss_tyrant_hull(g) {
    // A forge-ship: black iron, furnace mouth, chimney horns.
    g.glow(256, 330, 240, [255, 110, 30], 0.3);
    panel(g, [[150, 180], [90, 60], [70, 170], [110, 280]], [84, 66, 62], [22, 16, 18]);
    panel(g, [[256, 76], [356, 110], [444, 210], [476, 340], [384, 330], [340, 440], [256, 486], [172, 440], [128, 330], [36, 340], [68, 210], [156, 110]], [92, 76, 72], [24, 18, 22], { mirror: false, scale: 0.035, wear: 0.24 });
    panel(g, [[256, 130], [320, 158], [352, 250], [326, 366], [256, 420], [186, 366], [160, 250], [192, 158]], [64, 50, 50], [16, 12, 16], { mirror: false, ow: 7 });
    panel(g, [[256, 190], [306, 240], [296, 340], [256, 396], [216, 340], [206, 240]], [255, 236, 130], [255, 86, 20], { mirror: false, ow: 7, wear: 0.2, bevel: false, scale: 0.09 });
    for (const y of [240, 282, 324]) g.stroke([[206, y], [306, y]], false, 12, [24, 16, 18], 1);
    g.glow(256, 300, 130, [255, 170, 60], 0.7);
    line(g, [64, 214], [150, 170], 5, [255, 120, 40], 0.8);
  },
  boss_tyrant_vent(g) {
    panel(g, [[256, 60], [400, 130], [430, 360], [340, 440], [172, 440], [82, 360], [112, 130]], [120, 96, 84], [36, 26, 26], { mirror: false, ow: 11, scale: 0.05 });
    panel(g, ell(256, 256, 118, 118, 36), [255, 244, 170], [255, 90, 20], { mirror: false, ow: 9, wear: 0.2, bevel: false, scale: 0.08 });
    g.fill(ell(256, 256, 50, 50, 24), () => [255, 255, 240]);
    g.glow(256, 256, 190, [255, 150, 50], 0.8);
  },
  boss_hydra_head(g) {
    // Serpent head with mandibles, nose down.
    g.glow(256, 300, 200, [255, 60, 180], 0.3);
    panel(g, [[256, 60], [346, 90], [400, 190], [372, 320], [320, 410], [256, 480], [192, 410], [140, 320], [112, 190], [166, 90]], [156, 60, 150], [42, 14, 60], { mirror: false, scale: 0.04, wear: 0.26 });
    panel(g, [[140, 300], [64, 260], [96, 380], [170, 480], [196, 380]], [230, 190, 240], [120, 50, 150]);
    panel(g, [[206, 130], [306, 130], [346, 210], [256, 260], [166, 210]], [100, 34, 110], [26, 8, 40], { mirror: false, ow: 6 });
    for (const x of [196, 316]) { g.fill(ell(x, 286, 34, 24, 20), () => [255, 236, 120]); g.fill(ell(x, 286, 8, 22, 12), () => INK); g.glow(x, 286, 60, [255, 210, 90], 0.5); }
    panel(g, [[256, 400], [292, 340], [256, 322], [220, 340]], [255, 120, 210], [160, 20, 120], { mirror: false, ow: 5, bevel: false });
  },
  boss_hydra_seg(g) {
    panel(g, blob(256, 256, 150, 150, 0.1, 2.0), [150, 60, 150], [40, 12, 60], { mirror: false, ow: 11, scale: 0.05, wear: 0.26, bevel: false });
    panel(g, [[256, 150], [316, 256], [256, 362], [196, 256]], [255, 150, 220], [150, 30, 130], { mirror: false, ow: 7, bevel: false });
    g.glow(256, 256, 100, [255, 100, 210], 0.5);
  },
  boss_hydra_core(g) {
    g.glow(256, 256, 250, [230, 50, 200], 0.34);
    for (let i = 0; i < 8; i++) {
      const a = i / 8 * Math.PI * 2, c = Math.cos(a), s = Math.sin(a), n = [-s, c];
      const tip = [256 + c * 236, 256 + s * 236], l = [256 + c * 120 + n[0] * 60, 256 + s * 120 + n[1] * 60], r = [256 + c * 120 - n[0] * 60, 256 + s * 120 - n[1] * 60];
      panel(g, [l, tip, r], [186, 80, 170], [60, 16, 80], { mirror: false, ow: 7 });
    }
    panel(g, blob(256, 256, 164, 164, 0.14, 8.8), [130, 50, 150], [32, 10, 56], { mirror: false, ow: 11, scale: 0.05, wear: 0.3, bevel: false });
    panel(g, ell(256, 256, 84, 84, 30), [255, 210, 120], [240, 60, 160], { mirror: false, ow: 7, wear: 0, bevel: false });
    g.fill(ell(256, 256, 26, 66, 18), () => INK);
    g.glow(256, 256, 120, [255, 180, 120], 0.6);
  },
  boss_regent(g) {
    // A towering ice crown. Long vertical spires, utterly unlike the other bosses.
    g.glow(256, 240, 250, [150, 230, 255], 0.3);
    const spire = (x, top, w, base) => panel(g, [[x, top], [x + w, base - 60], [x + w * 0.5, base], [x - w * 0.5, base], [x - w, base - 60]], [245, 255, 255], [110, 190, 225], { mirror: false, ow: 7, wear: 0.05 });
    for (const [x, top, w, base] of [[60, 200, 34, 370], [122, 96, 40, 380], [190, 40, 44, 380], [256, 8, 50, 390], [322, 40, 44, 380], [390, 96, 40, 380], [452, 200, 34, 370]]) spire(x, top, w, base);
    panel(g, [[40, 330], [472, 330], [430, 430], [340, 490], [172, 490], [82, 430]], [120, 150, 186], [34, 50, 84], { mirror: false, scale: 0.05 });
    panel(g, [[176, 356], [336, 356], [306, 450], [206, 450]], [46, 66, 110], [14, 20, 44], { mirror: false, ow: 7 });
    panel(g, [[256, 366], [300, 404], [256, 444], [212, 404]], [190, 250, 255], [50, 170, 240], { mirror: false, ow: 6, wear: 0, bevel: false });
    g.glow(256, 404, 90, [160, 240, 255], 0.8);
    lights(g, [[120, 390]], 7, [150, 240, 255]);
  },
  boss_regent_shard(g) {
    g.glow(256, 256, 180, [150, 230, 255], 0.3);
    panel(g, [[256, 470], [330, 256], [290, 90], [222, 90], [182, 256]], [240, 255, 255], [90, 180, 225], { mirror: false, ow: 10, wear: 0.05 });
    panel(g, [[256, 400], [282, 256], [256, 130], [230, 256]], [190, 240, 255], [120, 210, 245], { mirror: false, ow: 3, bevel: false, wear: 0, ink: [255, 255, 255] });
  },
  boss_admiral(g) {
    // Viewed head-on, wider than any other boss: a capital ship that fills the top of the arena.
    panel(g, [[256, 120], [420, 150], [506, 230], [490, 300], [400, 330], [330, 402], [256, 424], [182, 402], [112, 330], [22, 300], [6, 230], [92, 150]], [150, 56, 64], [42, 14, 24], { mirror: false, scale: 0.03, angle: 80 });
    panel(g, [[256, 150], [340, 170], [360, 290], [316, 370], [256, 392], [196, 370], [152, 290], [172, 170]], [86, 30, 42], [24, 8, 16], { mirror: false, ow: 7 });
    panel(g, [[420, 170], [492, 236], [470, 282], [380, 290]], [216, 216, 226], [100, 100, 116]);
    for (const x of [434, 464]) line(g, [x - 8, 244], [x - 22, 276], 6, INK, 0.7);
    panel(g, [[256, 186], [300, 214], [304, 290], [256, 322], [208, 290], [212, 214]], [255, 214, 120], [230, 80, 30], { mirror: false, ow: 6, wear: 0, bevel: false });
    g.fill(ell(256, 256, 22, 38, 18), () => INK);
    g.glow(256, 256, 96, [255, 170, 70], 0.55);
    line(g, [100, 200], [170, 230], 5, INK, 0.5);
    lights(g, [[120, 300], [60, 256]], 6, [255, 70, 70]);
  },
  boss_admiral_turret(g) {
    panel(g, ell(256, 256, 170, 170, 12), [226, 226, 234], [90, 92, 108], { mirror: false, ow: 11 });
    for (const x of [212, 300]) panel(g, [[x - 26, 256], [x + 26, 256], [x + 20, 490], [x - 20, 490]], [200, 200, 212], [70, 72, 90], { mirror: false, ow: 8 });
    panel(g, ell(256, 256, 96, 96, 10), [170, 46, 56], [60, 14, 26], { mirror: false, ow: 8 });
    g.fill(ell(256, 256, 36, 36, 16), () => [255, 210, 120]);
    g.glow(256, 256, 70, [255, 170, 80], 0.6);
  },
  boss_core_eye(g) {
    // The final boss: a vast mechanical eye.
    g.glow(256, 256, 256, [255, 170, 60], 0.3);
    panel(g, ell(256, 256, 226, 226, 56), [108, 90, 76], [20, 14, 18], { mirror: false, ow: 11, scale: 0.03, wear: 0.26, angle: 60 });
    panel(g, ell(256, 256, 176, 176, 56), [255, 214, 110], [150, 70, 20], { mirror: false, ow: 8, scale: 0.09, wear: 0.34, bevel: false });
    for (let i = 0; i < 40; i++) {
      const a = i / 40 * Math.PI * 2;
      g.stroke([[256 + Math.cos(a) * 84, 256 + Math.sin(a) * 84], [256 + Math.cos(a) * 170, 256 + Math.sin(a) * 170]], false, 3, [100, 40, 20], 0.5);
    }
    panel(g, ell(256, 256, 88, 88, 40), [26, 14, 44], [6, 2, 16], { mirror: false, ow: 6, wear: 0, bevel: false });
    g.fill(ell(256, 256, 30, 30, 24), () => [255, 250, 220]);
    g.glow(256, 256, 96, [190, 120, 255], 0.75);
    g.glow(220, 200, 46, [255, 255, 255], 0.5);
  },
  boss_core_ring(g) {
    // One armoured segment of the rotating rings. Runs along the top of the sprite.
    const c = [256, 700];
    panel(g, arcBand(c[0], c[1], 560, 650, -Math.PI / 2 - 0.27, -Math.PI / 2 + 0.27, 24), [190, 150, 90], [54, 34, 34], { mirror: false, ow: 11, scale: 0.05, wear: 0.26 });
    panel(g, arcBand(c[0], c[1], 590, 620, -Math.PI / 2 - 0.2, -Math.PI / 2 + 0.2, 20), [255, 210, 110], [190, 90, 30], { mirror: false, ow: 5, wear: 0, bevel: false });
    g.glow(256, 96, 50, [255, 190, 90], 0.4);
  },
  // --- Rift Lords: bosses that only appear in the Rift and in Boss Rush ---
  boss_eclipse_sun(g) {
    // The bright twin: a burning disc with a corona of blades.
    g.glow(256, 256, 250, [255, 190, 70], 0.4);
    for (let i = 0; i < 12; i++) {
      const a = i / 12 * Math.PI * 2, c = Math.cos(a), s = Math.sin(a), px = -s, py = c;
      panel(g, [[256 + c * 150 + px * 26, 256 + s * 150 + py * 26], [256 + c * 236, 256 + s * 236], [256 + c * 150 - px * 26, 256 + s * 150 - py * 26]], [255, 226, 130], [200, 90, 20], { mirror: false, ow: 6, wear: 0.05 });
    }
    panel(g, ell(256, 256, 168, 168, 56), [255, 236, 150], [214, 96, 24], { mirror: false, ow: 11, scale: 0.06, wear: 0.2 });
    panel(g, ell(256, 256, 118, 118, 48), [255, 250, 210], [255, 176, 60], { mirror: false, ow: 5, wear: 0, bevel: false });
    for (let i = 0; i < 24; i++) {
      const a = i / 24 * Math.PI * 2;
      g.stroke([[256 + Math.cos(a) * 60, 256 + Math.sin(a) * 60], [256 + Math.cos(a) * 112, 256 + Math.sin(a) * 112]], false, 3, [200, 90, 20], 0.45);
    }
    g.fill(ell(256, 256, 44, 44, 28), () => [255, 255, 240]);
    g.glow(256, 256, 120, [255, 240, 170], 0.8);
  },
  boss_eclipse_moon(g) {
    // The dark twin: a cold armoured disc with a violet crescent.
    g.glow(256, 256, 240, [130, 90, 255], 0.3);
    panel(g, ell(256, 256, 190, 190, 60), [96, 92, 132], [16, 12, 34], { mirror: false, ow: 12, scale: 0.04, wear: 0.3, angle: 70 });
    panel(g, ell(256, 256, 150, 150, 52), [58, 52, 96], [10, 8, 26], { mirror: false, ow: 6, wear: 0.2 });
    panel(g, arcBand(256, 256, 120, 170, Math.PI * 0.62, Math.PI * 1.5, 26), [214, 190, 255], [96, 60, 200], { mirror: false, ow: 6, wear: 0, bevel: false });
    for (const [x, y, r] of [[300, 220, 26], [226, 300, 18], [316, 316, 14], [250, 190, 12]]) panel(g, ell(x, y, r, r, 16), [34, 30, 62], [8, 6, 20], { mirror: false, ow: 4, wear: 0, bevel: false });
    g.fill(ell(256, 256, 30, 30, 22), () => [200, 170, 255]);
    g.glow(256, 256, 80, [160, 110, 255], 0.7);
  },
  boss_lancer(g) {
    // A long hunting ship, nose down, with swept wings and a spinal cannon.
    g.glow(256, 250, 230, [90, 255, 200], 0.18);
    panel(g, [[256, 150], [300, 120], [470, 60], [500, 96], [420, 190], [330, 250], [300, 330]], [72, 96, 110], [14, 22, 34], { ow: 10, scale: 0.04, wear: 0.2 });
    panel(g, [[256, 40], [316, 70], [336, 210], [306, 400], [256, 492], [206, 400], [176, 210], [196, 70]], [150, 176, 190], [30, 44, 62], { mirror: false, ow: 11, scale: 0.05, wear: 0.24, angle: 80 });
    panel(g, [[256, 110], [292, 140], [296, 300], [256, 420], [216, 300], [220, 140]], [60, 84, 100], [12, 20, 30], { mirror: false, ow: 6 });
    panel(g, [[256, 300], [272, 330], [256, 470], [240, 330]], [150, 255, 220], [30, 170, 130], { mirror: false, ow: 4, wear: 0, bevel: false });
    panel(g, [[256, 150], [286, 176], [256, 240], [226, 176]], [255, 214, 120], [220, 90, 40], { mirror: false, ow: 5, wear: 0, bevel: false });
    lights(g, [[430, 110], [380, 150]], 7, [90, 255, 200]);
    line(g, [330, 130], [440, 96], 5, INK, 0.5);
    flame(g, 216, 60, 26, 56, [200, 255, 240], [60, 220, 170]);
    flame(g, 296, 60, 26, 56, [200, 255, 240], [60, 220, 170]);
    g.glow(256, 196, 60, [255, 190, 90], 0.6);
    g.glow(256, 460, 50, [120, 255, 210], 0.7);
  },
  boss_lancer_plate(g) {
    // The guard plate carried in front of the Lancer: a curved energy-backed shield.
    g.glow(256, 300, 220, [90, 255, 200], 0.22);
    panel(g, arcBand(256, 60, 250, 320, Math.PI * 0.2, Math.PI * 0.8, 30), [176, 200, 214], [34, 50, 70], { mirror: false, ow: 11, scale: 0.05, wear: 0.22 });
    panel(g, arcBand(256, 60, 272, 296, Math.PI * 0.24, Math.PI * 0.76, 26), [150, 255, 220], [30, 150, 130], { mirror: false, ow: 4, wear: 0, bevel: false });
    lights(g, [[150, 330], [210, 366]], 6, [120, 255, 210]);
  },
};

const only = process.argv[2];
const names = Object.keys(art).filter((n) => !only || n === only);
for (const name of names) {
  const g = new Art();
  art[name](g);
  g.save(name);
}

// A contact sheet so the whole set can be reviewed in one image.
if (!only) console.log("painted", names.length);
