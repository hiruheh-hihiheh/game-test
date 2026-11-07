// Synthesises every sound effect and music track from scratch, with no samples.
// Run: node tools/gen_audio.mjs
import fs from "node:fs";
import path from "node:path";

const SR = 44100;
const SFX_DIR = path.resolve("assets/audio/sfx");
const MUS_DIR = path.resolve("assets/audio/music");
fs.mkdirSync(SFX_DIR, { recursive: true });
fs.mkdirSync(MUS_DIR, { recursive: true });

let seed = 90210;
const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
const noise = () => rnd() * 2 - 1;
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
const lerp = (a, b, t) => a + (b - a) * t;

function writeWav(file, channels) {
  const n = channels[0].length, ch = channels.length;
  const data = Buffer.alloc(n * ch * 2);
  for (let i = 0, o = 0; i < n; i++) for (let c = 0; c < ch; c++, o += 2) data.writeInt16LE(Math.round(clamp(channels[c][i], -1, 1) * 32767), o);
  const h = Buffer.alloc(44);
  h.write("RIFF", 0); h.writeUInt32LE(36 + data.length, 4); h.write("WAVE", 8); h.write("fmt ", 12);
  h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(ch, 22); h.writeUInt32LE(SR, 24);
  h.writeUInt32LE(SR * ch * 2, 28); h.writeUInt16LE(ch * 2, 32); h.writeUInt16LE(16, 34);
  h.write("data", 36); h.writeUInt32LE(data.length, 40);
  fs.writeFileSync(file, Buffer.concat([h, data]));
}

// ---------- Sound effects ----------

function sfx(name, dur, gain, fn) {
  const n = Math.floor(dur * SR), out = new Float32Array(n);
  const state = {};
  for (let i = 0; i < n; i++) out[i] = fn(i / SR, i / n, state);
  let peak = 0;
  for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(out[i]));
  const k = gain / (peak || 1);
  for (let i = 0; i < n; i++) out[i] *= k * Math.min(1, (n - i) / 220) * Math.min(1, (i + 1) / 16);
  writeWav(path.join(SFX_DIR, name + ".wav"), [out]);
}
const phase = (st, key, f) => { st[key] = (st[key] || 0) + f / SR; return st[key]; };
const sine = (st, key, f) => Math.sin(phase(st, key, f) * Math.PI * 2);
const saw = (st, key, f) => { const p = phase(st, key, f); return 2 * (p - Math.floor(p)) - 1; };
const square = (st, key, f, w = 0.5) => { const p = phase(st, key, f); return p - Math.floor(p) < w ? 1 : -1; };
const lp = (st, key, x, cut) => { const a = 1 - Math.exp(-2 * Math.PI * cut / SR); st[key] = (st[key] || 0) + a * (x - (st[key] || 0)); return st[key]; };
const exp = (t, k) => Math.exp(-t * k);

sfx("shoot", 0.11, 0.55, (t, p, s) => {
  const f = 1500 * Math.pow(0.32, p * 1.4);
  return (square(s, "a", f, 0.3) * 0.5 + sine(s, "b", f * 0.5) * 0.7) * exp(t, 34) + noise() * 0.08 * exp(t, 120);
});
sfx("enemy_shoot", 0.16, 0.36, (t, p, s) => {
  const f = 620 * Math.pow(0.45, p);
  return (sine(s, "a", f) + saw(s, "b", f * 1.01) * 0.3) * exp(t, 18);
});
sfx("hit", 0.07, 0.42, (t, p, s) => lp(s, "n", noise(), 5200) * 0.7 * exp(t, 60) + sine(s, "a", 950 - 500 * p) * 0.6 * exp(t, 46));
sfx("crit", 0.2, 0.5, (t, p, s) => (sine(s, "a", 1760) + sine(s, "b", 2637) * 0.7 + sine(s, "c", 3520) * 0.3) * exp(t, 22) + noise() * 0.3 * exp(t, 150));
sfx("explode_s", 0.42, 0.72, (t, p, s) => {
  const body = lp(s, "n", noise(), lerp(4200, 340, Math.sqrt(p))) * exp(t, 8);
  return body * 1.3 + sine(s, "a", lerp(170, 44, p * 1.6)) * exp(t, 11) * 0.9;
});
sfx("explode_m", 0.75, 0.82, (t, p, s) => {
  const body = lp(s, "n", noise(), lerp(3200, 200, Math.pow(p, 0.5))) * exp(t, 4.6);
  return body * 1.5 + sine(s, "a", lerp(120, 34, Math.min(1, p * 1.4))) * exp(t, 6) + (rnd() > 0.992 ? noise() * 0.5 * exp(t, 5) : 0);
});
sfx("explode_l", 2.1, 0.95, (t, p, s) => {
  const roar = lp(s, "n", noise(), lerp(2600, 110, Math.pow(p, 0.42))) * exp(t, 1.9) * 1.8;
  const sub = sine(s, "a", lerp(90, 28, Math.min(1, p * 1.5))) * exp(t, 2.1) * 1.1;
  const crackle = rnd() > 0.985 ? noise() * exp(t, 2.6) * 0.9 : 0;
  return Math.tanh((roar + sub + crackle) * 1.4);
});
sfx("shield_hit", 0.36, 0.62, (t, p, s) => {
  const mod = sine(s, "m", 311) * 340 * exp(t, 9);
  return sine(s, "a", 780 + mod - 300 * p) * exp(t, 11) + sine(s, "b", 1560) * 0.2 * exp(t, 24);
});
sfx("hull_hit", 0.62, 0.9, (t, p, s) => {
  const thump = sine(s, "a", lerp(150, 42, p)) * exp(t, 6);
  const grit = lp(s, "n", noise(), 1500) * exp(t, 9) * 1.2;
  const alarm = square(s, "b", t < 0.2 ? 880 : 660, 0.5) * 0.22 * exp(t, 6);
  return Math.tanh((thump + grit + alarm) * 2.2);
});
sfx("pickup", 0.17, 0.42, (t, p, s) => {
  const f = t < 0.06 ? 1319 : 1976;
  return (sine(s, "a", f) + sine(s, "b", f * 2) * 0.25) * exp(t < 0.06 ? t : t - 0.06, 18);
});
sfx("repair", 0.55, 0.5, (t, p, s) => {
  const seq = [659, 880, 1109, 1319], i = Math.min(3, Math.floor(t / 0.1));
  return (sine(s, "a", seq[i]) + saw(s, "b", seq[i]) * 0.12) * exp(t - i * 0.1, 8);
});
sfx("powerup", 0.7, 0.55, (t, p, s) => {
  const seq = [523, 659, 784, 1047, 1319], i = Math.min(4, Math.floor(t / 0.075));
  const e = exp(t - i * 0.075, i === 4 ? 4.6 : 13);
  return (square(s, "a", seq[i], 0.35) * 0.3 + sine(s, "b", seq[i]) * 0.8 + sine(s, "c", seq[i] * 2) * 0.2) * e;
});
sfx("burst", 1.5, 0.95, (t, p, s) => {
  const riser = t < 0.22 ? lp(s, "r", noise(), 400 + 11000 * (t / 0.22)) * (t / 0.22) * 0.9 : 0;
  const after = Math.max(0, t - 0.22);
  const blast = t >= 0.22 ? (lp(s, "n", noise(), lerp(5400, 180, Math.pow(after / 1.28, 0.45))) * 1.7 + sine(s, "a", lerp(180, 32, Math.min(1, after * 1.8))) * 1.3 + saw(s, "b", lerp(1400, 70, Math.min(1, after * 2.3))) * 0.26) * exp(after, 2.7) : 0;
  return Math.tanh((riser + blast) * 1.3);
});
sfx("energy_ready", 0.6, 0.48, (t, p, s) => (sine(s, "a", 880) * exp(t, 7) + sine(s, "b", 1318) * exp(Math.max(0, t - 0.08), 6) * (t > 0.08 ? 1 : 0) + sine(s, "c", 1760) * exp(Math.max(0, t - 0.16), 5) * (t > 0.16 ? 1 : 0)));
sfx("ui_click", 0.075, 0.42, (t, p, s) => (sine(s, "a", 1250 - 600 * p) + square(s, "b", 2500, 0.5) * 0.08) * exp(t, 58));
sfx("ui_back", 0.12, 0.36, (t, p, s) => sine(s, "a", 760 - 420 * p) * exp(t, 28));
sfx("ui_deny", 0.26, 0.4, (t, p, s) => square(s, "a", t < 0.11 ? 196 : 165, 0.45) * (t % 0.13 < 0.095 ? 1 : 0) * 0.7);
sfx("ui_buy", 0.44, 0.5, (t, p, s) => {
  const f = t < 0.08 ? 988 : 1319;
  return (sine(s, "a", f) + sine(s, "b", f * 2.01) * 0.3 + sine(s, "c", f * 3.02) * 0.14) * exp(t < 0.08 ? t : t - 0.08, 7.5);
});
sfx("card_in", 0.24, 0.26, (t, p, s) => lp(s, "n", noise(), 800 + 6000 * Math.sin(p * Math.PI)) * Math.sin(p * Math.PI));
sfx("card_pick", 0.5, 0.58, (t, p, s) => {
  const chord = [392, 587, 784, 1175];
  let v = 0;
  chord.forEach((f, i) => { v += saw(s, "n" + i, f) * 0.25; });
  return lp(s, "f", v, lerp(5200, 500, Math.sqrt(p))) * exp(t, 7) + noise() * 0.12 * exp(t, 90);
});
for (const [i, base] of [[1, 880], [2, 1109], [3, 1319]]) {
  sfx("star_" + i, 0.8, 0.5 + i * 0.05, (t, p, s) => (sine(s, "a", base) + sine(s, "b", base * 2) * 0.4 + sine(s, "c", base * 3.01) * 0.18 + sine(s, "d", base * 4.2) * 0.08) * exp(t, 5.5));
}
sfx("wave_start", 0.85, 0.42, (t, p, s) => {
  const f = lerp(170, 900, p * p);
  return lp(s, "f", saw(s, "a", f) + saw(s, "b", f * 1.007) + noise() * 0.5, 500 + 4000 * p) * Math.sin(Math.PI * Math.min(1, p * 1.05)) * 0.6;
});
sfx("wave_clear", 0.6, 0.46, (t, p, s) => {
  const f = t < 0.14 ? 659 : 988;
  return (square(s, "a", f, 0.4) * 0.3 + sine(s, "b", f) * 0.8) * exp(t < 0.14 ? t : t - 0.14, 6.5);
});
sfx("warning", 2.0, 0.6, (t, p, s) => {
  const cycle = (t % 0.66) / 0.66;
  const f = lerp(420, 860, Math.sin(cycle * Math.PI));
  return lp(s, "f", square(s, "a", f, 0.5) + saw(s, "b", f * 0.5) * 0.6, 2400) * (cycle < 0.86 ? 1 : 0) + sine(s, "c", 55) * 0.55;
});
sfx("charge", 0.55, 0.34, (t, p, s) => {
  const f = lerp(180, 1500, p * p);
  return (saw(s, "a", f) * 0.3 + sine(s, "b", f * 0.5) * 0.7) * p;
});
sfx("laser", 1.0, 0.56, (t, p, s) => {
  const wob = 1 + sine(s, "m", 34) * 0.05;
  return Math.tanh((saw(s, "a", 92 * wob) + saw(s, "b", 138 * wob) * 0.8 + lp(s, "n", noise(), 3200) * 1.2) * 1.8) * Math.min(1, t * 18) * Math.min(1, (1 - p) * 8);
});
sfx("mine", 0.18, 0.38, (t, p, s) => square(s, "a", 1240, 0.5) * exp(t, 15) * 0.6);
sfx("whoosh", 0.55, 0.26, (t, p, s) => lp(s, "n", noise(), 300 + 5200 * Math.sin(p * Math.PI)) * Math.sin(p * Math.PI));

// ---------- Music engine ----------

class Mix {
  constructor(seconds) {
    this.n = Math.round(seconds * SR);
    this.L = new Float32Array(this.n); this.R = new Float32Array(this.n);
    this.dL = new Float32Array(this.n); this.dR = new Float32Array(this.n); // delay send
    this.rv = new Float32Array(this.n); // reverb send
    this.side = new Float32Array(this.n).fill(1);
  }
  put(i, l, r, d, rv) {
    const k = i % this.n;
    this.L[k] += l; this.R[k] += r; this.dL[k] += l * d; this.dR[k] += r * d; this.rv[k] += (l + r) * 0.5 * rv;
  }
  pump(start, depth, length) { // sidechain duck, keyed by the kick
    const a = Math.floor(start * SR), len = Math.floor(length * SR);
    for (let i = 0; i < len; i++) {
      const k = (a + i) % this.n;
      this.side[k] = Math.min(this.side[k], 1 - depth * Math.pow(1 - i / len, 2));
    }
  }
}

function tone(mix, t, dur, midi, o) {
  const f = mtof(midi), a = o.a ?? 0.005, r = o.r ?? 0.1, s = o.s ?? 0.7, dec = o.d ?? 0.2;
  const start = Math.floor(t * SR), len = Math.floor((dur + r) * SR);
  const voices = o.voices ?? 1, det = o.detune ?? 0;
  const ph = new Float64Array(voices), pan = new Float64Array(voices), fs_ = new Float64Array(voices);
  for (let v = 0; v < voices; v++) {
    const x = voices > 1 ? v / (voices - 1) * 2 - 1 : 0;
    ph[v] = rnd(); pan[v] = x * (o.width ?? 0); fs_[v] = f * Math.pow(2, x * det / 1200);
  }
  const panC = o.pan ?? 0;
  let z1L = 0, z2L = 0, z1R = 0, z2R = 0;
  const vib = o.vib ?? 0, cutEnvD = o.cutD ?? 0.2;
  for (let i = 0; i < len; i++) {
    const tt = i / SR;
    let e = tt < a ? tt / a : tt < a + dec ? lerp(1, s, (tt - a) / dec) : s;
    if (tt > dur) e *= Math.max(0, 1 - (tt - dur) / r);
    const cut = clamp((o.cut ?? 3000) + (o.cutEnv ?? 0) * Math.exp(-tt / cutEnvD), 40, 16000);
    const c = 1 - Math.exp(-2 * Math.PI * cut / SR);
    let l = 0, r2 = 0;
    const vibr = vib ? 1 + Math.sin(tt * 34) * vib * Math.min(1, tt * 4) : 1;
    for (let v = 0; v < voices; v++) {
      ph[v] += fs_[v] * vibr / SR; if (ph[v] >= 1) ph[v] -= 1;
      const p = ph[v];
      let w;
      if (o.wave === "square") w = p < (o.pw ?? 0.5) ? 1 : -1;
      else if (o.wave === "sine") w = Math.sin(p * 2 * Math.PI);
      else if (o.wave === "tri") w = 4 * Math.abs(p - 0.5) - 1;
      else w = 2 * p - 1;
      const pl = Math.cos((pan[v] + 1) * Math.PI / 4), pr = Math.sin((pan[v] + 1) * Math.PI / 4);
      l += w * pl; r2 += w * pr;
    }
    l /= Math.sqrt(voices); r2 /= Math.sqrt(voices);
    z1L += c * (l - z1L); z2L += c * (z1L - z2L); z1R += c * (r2 - z1R); z2R += c * (z1R - z2R);
    const g = e * (o.gain ?? 0.2);
    const pl = Math.cos((panC + 1) * Math.PI / 4) * 1.414, pr = Math.sin((panC + 1) * Math.PI / 4) * 1.414;
    mix.put(start + i, z2L * g * pl, z2R * g * pr, o.delay ?? 0, o.reverb ?? 0);
  }
}

const inst = {
  pad: (m, t, d, n, g = 0.11) => tone(m, t, d, n, { wave: "saw", voices: 5, detune: 22, width: 0.8, a: 0.5, d: 0.5, s: 0.8, r: 0.8, cut: 1050, cutEnv: 500, cutD: 1.2, gain: g, reverb: 0.5 }),
  pluck: (m, t, n, g = 0.13, pan = 0, dur = 0.12) => tone(m, t, dur, n, { wave: "saw", voices: 2, detune: 8, width: 0.3, a: 0.002, d: 0.14, s: 0.0, r: 0.1, cut: 900, cutEnv: 4200, cutD: 0.09, gain: g, pan, delay: 0.33, reverb: 0.2 }),
  bass: (m, t, d, n, g = 0.3) => {
    tone(m, t, d, n, { wave: "saw", voices: 2, detune: 6, a: 0.004, d: 0.12, s: 0.6, r: 0.05, cut: 260, cutEnv: 1400, cutD: 0.08, gain: g });
    tone(m, t, d, n - 12, { wave: "sine", a: 0.004, d: 0.1, s: 0.9, r: 0.05, cut: 800, gain: g * 0.7 });
  },
  lead: (m, t, d, n, g = 0.11) => tone(m, t, d, n, { wave: "square", pw: 0.42, voices: 2, detune: 7, width: 0.2, a: 0.012, d: 0.1, s: 0.75, r: 0.14, cut: 2100, cutEnv: 2200, cutD: 0.13, vib: 0.004, gain: g, delay: 0.3, reverb: 0.28 }),
  bell: (m, t, n, g = 0.08, pan = 0) => {
    tone(m, t, 0.5, n, { wave: "sine", a: 0.002, d: 0.5, s: 0.0, r: 0.3, cut: 8000, gain: g, pan, delay: 0.3, reverb: 0.5 });
    tone(m, t, 0.2, n + 19, { wave: "sine", a: 0.002, d: 0.2, s: 0.0, r: 0.1, cut: 8000, gain: g * 0.3, pan, delay: 0.3, reverb: 0.5 });
  },
  stab: (m, t, d, notes, g = 0.1) => { for (const n of notes) tone(m, t, d, n, { wave: "saw", voices: 3, detune: 14, width: 0.6, a: 0.003, d: 0.14, s: 0.3, r: 0.1, cut: 800, cutEnv: 3400, cutD: 0.08, gain: g, reverb: 0.25, delay: 0.15 }); },
};

function kick(m, t, g = 0.9) {
  const s = Math.floor(t * SR), len = Math.floor(0.26 * SR);
  let ph = 0;
  for (let i = 0; i < len; i++) {
    const tt = i / SR;
    ph += (46 + 170 * Math.exp(-tt * 34)) / SR;
    const v = Math.sin(ph * Math.PI * 2) * Math.exp(-tt * 13) * g + (i < 60 ? noise() * 0.2 * (1 - i / 60) : 0);
    m.put(s + i, v * 0.5, v * 0.5, 0, 0);
  }
}
function snare(m, t, g = 0.5) {
  const s = Math.floor(t * SR), len = Math.floor(0.24 * SR);
  let ph = 0, z = 0;
  for (let i = 0; i < len; i++) {
    const tt = i / SR;
    ph += (195 - 60 * tt) / SR;
    const n = noise(); z += 0.35 * (n - z);
    const v = (n - z * 0.7) * Math.exp(-tt * 15) * g * 0.7 + Math.sin(ph * Math.PI * 2) * Math.exp(-tt * 26) * g * 0.6;
    m.put(s + i, v, v, 0, 0.18);
  }
}
function clap(m, t, g = 0.3) {
  const s = Math.floor(t * SR), len = Math.floor(0.2 * SR);
  for (let i = 0; i < len; i++) {
    const tt = i / SR;
    const burst = tt < 0.03 ? (Math.floor(tt / 0.01) % 2 ? 1 : 0.3) : Math.exp(-(tt - 0.03) * 22);
    const v = noise() * burst * g;
    m.put(s + i, v, v, 0, 0.3);
  }
}
function hat(m, t, g = 0.07, open = false, pan = 0.15) {
  const s = Math.floor(t * SR), len = Math.floor((open ? 0.16 : 0.05) * SR);
  let z = 0;
  const k = open ? 22 : 90;
  for (let i = 0; i < len; i++) {
    const n = noise(); z += 0.72 * (n - z);
    const v = (n - z) * Math.exp(-(i / SR) * k) * g;
    m.put(s + i, v * (1 - pan), v * (1 + pan), 0, 0);
  }
}
function riser(m, t, dur, g = 0.16) {
  const s = Math.floor(t * SR), len = Math.floor(dur * SR);
  let z = 0;
  for (let i = 0; i < len; i++) {
    const p = i / len;
    z += (0.02 + 0.5 * p * p) * (noise() - z);
    const v = z * p * p * g;
    m.put(s + i, v, v, 0, 0.4);
  }
}

function finish(mix, file, bpm, master = 0.9) {
  const n = mix.n, beat = 60 / bpm;
  // Tempo-synced ping-pong delay, wrapped around so the loop point is inaudible.
  const dly = Math.floor(beat * 0.75 * SR);
  const wetL = new Float32Array(n), wetR = new Float32Array(n);
  for (let pass = 0; pass < 3; pass++) {
    for (let i = 0; i < n; i++) {
      const j = (i - dly + n * 2) % n;
      const a = mix.dL[j] + wetR[j] * 0.42, b = mix.dR[j] + wetL[j] * 0.42;
      wetL[i] = a; wetR[i] = b;
    }
  }
  // Schroeder reverb, run over two loops and keeping the settled second pass.
  const combs = [1557, 1617, 1491, 1422, 1277, 1356], fb = 0.82;
  const out = new Float32Array(n * 2);
  for (const size of combs) {
    const buf = new Float32Array(size);
    let p = 0, z = 0;
    for (let i = 0; i < n * 2; i++) {
      const y = buf[p];
      z = y * 0.72 + z * 0.28;
      buf[p] = mix.rv[i % n] + z * fb;
      p = (p + 1) % size;
      out[i] += y / combs.length;
    }
  }
  for (const size of [225, 556]) {
    const buf = new Float32Array(size);
    let p = 0;
    for (let i = 0; i < n * 2; i++) {
      const y = buf[p], x = out[i];
      out[i] = y - x * 0.5;
      buf[p] = x + y * 0.5;
      p = (p + 1) % size;
    }
  }
  const L = new Float32Array(n), R = new Float32Array(n);
  let peak = 0;
  for (let i = 0; i < n; i++) {
    const rv = out[n + i] * 1.4;
    const sc = mix.side[i];
    L[i] = (mix.L[i] * sc + wetL[i] * 0.55 * sc + rv * sc);
    R[i] = (mix.R[i] * sc + wetR[i] * 0.55 * sc + rv * sc);
    peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
  }
  const g = master / (peak || 1) * 1.25;
  for (let i = 0; i < n; i++) { L[i] = Math.tanh(L[i] * g) * 0.92; R[i] = Math.tanh(R[i] * g) * 0.92; }
  writeWav(path.join(MUS_DIR, file + ".wav"), [L, R]);
  console.log(file, (n / SR).toFixed(1) + "s");
}

const CH = {
  Em: [52, 55, 59], C: [48, 52, 55], G: [43, 50, 55], D: [50, 54, 57], Am: [45, 52, 57], B: [47, 51, 54], F: [41, 48, 53],
  Dm: [50, 53, 57], Bb: [46, 50, 53], A: [45, 49, 52], Gm: [43, 50, 55 - 0], Cs: [49, 52, 56], Dmaj: [50, 54, 57],
};
const NOTE = { C: 0, "C#": 1, Db: 1, D: 2, "D#": 3, Eb: 3, E: 4, F: 5, "F#": 6, Gb: 6, G: 7, "G#": 8, Ab: 8, A: 9, "A#": 10, Bb: 10, B: 11 };
const midi = (s) => { const m = s.match(/^([A-G][#b]?)(\d)$/); return NOTE[m[1]] + (Number(m[2]) + 1) * 12; };
function melody(fn, m, startBeat, beat, text, ...args) {
  let b = startBeat;
  for (const tok of text.trim().split(/\s+/)) {
    const [n, d] = tok.split(":"), len = Number(d);
    if (n !== "_") fn(m, b * beat, len * beat * 0.92, midi(n), ...args);
    b += len;
  }
}

function buildBattle(file, bpm, prog, leadA, transpose = 0, arpShape = [0, 1, 2, 1, 2, 0, 1, 2]) {
  const beat = 60 / bpm, bars = prog.length, m = new Mix(bars * 4 * beat);
  prog.forEach((name, bar) => {
    const notes = CH[name].map((n) => n + transpose), t0 = bar * 4 * beat;
    inst.pad(m, t0, 4 * beat, notes[0] + 12, 0.075);
    inst.pad(m, t0, 4 * beat, notes[1] + 12, 0.075);
    inst.pad(m, t0, 4 * beat, notes[2] + 12, 0.075);
    for (let i = 0; i < 8; i++) {
      const hit = i % 8 === 3 || i % 8 === 6 ? notes[0] - 12 + 12 : notes[0] - 12;
      inst.bass(m, t0 + i * beat / 2, beat * 0.42, hit - (notes[0] > 49 ? 12 : 0) + 12, i % 4 === 0 ? 0.3 : 0.24);
    }
    for (let i = 0; i < 16; i++) {
      const n = notes[arpShape[i % arpShape.length]] + 24 + (i % 8 >= 6 ? 12 : 0);
      inst.pluck(m, t0 + i * beat / 4, n, 0.075, i % 2 ? 0.45 : -0.45);
    }
    for (let i = 0; i < 4; i++) {
      kick(m, t0 + i * beat, 0.95); m.pump(t0 + i * beat, 0.55, beat * 0.72);
      if (i % 2 === 1) { snare(m, t0 + i * beat, 0.42); clap(m, t0 + i * beat, 0.2); }
    }
    for (let i = 0; i < 16; i++) hat(m, t0 + i * beat / 4, i % 4 === 2 ? 0.09 : 0.05, i % 4 === 2, i % 2 ? 0.25 : -0.25);
    if (bar % 8 === 7) { riser(m, t0 + 2 * beat, 2 * beat, 0.2); for (let i = 0; i < 4; i++) snare(m, t0 + 3 * beat + i * beat / 4, 0.14 + i * 0.05); }
  });
  melody(inst.lead, m, 0, beat, leadA, 0.085);
  finish(m, file, bpm);
}

// Menu: slow, glassy and hopeful.
{
  const bpm = 92, beat = 60 / bpm, prog = ["Am", "F", "C", "G", "Am", "F", "C", "Em"];
  const voic = { Am: [57, 60, 64, 67], F: [53, 60, 65, 69], C: [55, 60, 64, 71], G: [55, 59, 62, 69], Em: [55, 59, 64, 66] };
  const m = new Mix(prog.length * 2 * 4 * beat);
  for (let rep = 0; rep < 2; rep++) prog.forEach((name, bar) => {
    const t0 = (rep * prog.length + bar) * 4 * beat, v = voic[name];
    for (const n of v) inst.pad(m, t0, 4 * beat, n, 0.075);
    inst.bass(m, t0, 2 * beat, CH[name][0] - 12, 0.14);
    inst.bass(m, t0 + 2.5 * beat, 1.2 * beat, CH[name][0] - 12, 0.1);
    const seq = [0, 2, 1, 3, 2, 1, 3, 2];
    for (let i = 0; i < 8; i++) inst.bell(m, t0 + i * beat / 2, v[seq[i]] + 12, 0.062, i % 2 ? 0.5 : -0.5);
    if (rep === 1) {
      kick(m, t0, 0.55); kick(m, t0 + 2.5 * beat, 0.42); m.pump(t0, 0.3, beat);
      snare(m, t0 + beat, 0.16); snare(m, t0 + 3 * beat, 0.18);
      for (let i = 0; i < 8; i++) hat(m, t0 + i * beat / 2, 0.035, i % 4 === 2);
    }
  });
  melody(inst.lead, m, 32, beat, `
    A5:1.5 C6:0.5 E6:2  | D6:1.5 C6:0.5 A5:2 | G5:1.5 B5:0.5 C6:2  | D6:1 B5:1 G5:2
    A5:1.5 C6:0.5 E6:2  | F6:1.5 E6:0.5 C6:2 | E6:1 D6:1 C6:1 G5:1 | B5:3 _:1`.replace(/\|/g, " "), 0.05);
  finish(m, "menu", bpm, 0.72);
}

buildBattle("battle_a", 128, ["Em", "C", "G", "D", "Em", "C", "Am", "B", "C", "D", "Em", "G", "C", "D", "B", "B"], `
  E5:.75 G5:.75 B5:.5 A5:1 G5:1
  E5:1.5 G5:.5 C6:1 B5:1
  B5:.75 A5:.75 G5:.5 D5:2
  A5:.75 F#5:.75 D5:.5 A5:1 F#5:1
  E5:.75 G5:.75 B5:.5 A5:1 G5:1
  E5:1 G5:.5 C6:.5 E6:1 D6:1
  C6:.75 B5:.75 A5:.5 E5:1 A5:1
  B5:1.5 D#6:.5 F#6:1 B5:1
  G5:2 E5:1 G5:1
  A5:2 F#5:1 A5:1
  B5:1.5 G5:.5 E6:2
  D6:1.5 B5:.5 G5:2
  C6:1 E6:1 G6:1 E6:1
  D6:1 F#6:1 A6:1 F#6:1
  B5:1 D#6:1 F#6:1 B6:1
  A6:.5 F#6:.5 D#6:.5 B5:.5 F#5:2`);

buildBattle("battle_b", 138, ["Dm", "Bb", "F", "C", "Dm", "Gm", "Bb", "A", "Bb", "C", "Dm", "F", "Gm", "Bb", "A", "A"], `
  D5:.5 F5:.5 A5:1 G5:.5 F5:.5 E5:1
  D5:1 F5:.5 Bb5:.5 A5:2
  C6:.75 A5:.75 F5:.5 G5:1 A5:1
  G5:.75 E5:.75 C5:.5 G5:2
  D5:.5 F5:.5 A5:1 G5:.5 F5:.5 E5:1
  G5:1 Bb5:.5 D6:.5 C6:2
  D6:.75 Bb5:.75 F5:.5 A5:1 Bb5:1
  A5:1 C#6:1 E6:2
  D6:1.5 C6:.5 Bb5:2
  C6:1.5 Bb5:.5 A5:2
  A5:.5 D6:.5 F6:1 E6:.5 D6:.5 A5:1
  C6:1 F6:1 E6:2
  Bb5:1 D6:1 G6:1 F6:1
  F6:.5 D6:.5 Bb5:1 D6:1 F6:1
  E6:1 C#6:1 A5:1 E6:1
  A6:.5 E6:.5 C#6:.5 A5:.5 E5:2`, 0, [0, 2, 1, 2, 0, 2, 1, 2]);

// Boss: fast, low and threatening.
{
  const bpm = 150, beat = 60 / bpm, prog = ["Cs", "Cs", "Dmaj", "Cs", "A", "Cs", "B", "Cs"];
  const m = new Mix(prog.length * 2 * 4 * beat);
  CH.Cs = [49, 52, 56]; CH.B = [47, 51, 54];
  for (let rep = 0; rep < 2; rep++) prog.forEach((name, bar) => {
    const t0 = (rep * prog.length + bar) * 4 * beat, n = CH[name];
    for (const x of n) inst.pad(m, t0, 4 * beat, x + 12, 0.055);
    const rootLow = n[0] - 24 + (n[0] < 48 ? 12 : 0);
    for (let i = 0; i < 16; i++) {
      const accent = [0, 3, 6, 10, 12, 14].includes(i);
      if (accent || i % 2 === 0) inst.bass(m, t0 + i * beat / 4, beat * 0.2, rootLow + (i === 14 ? 12 : i === 10 ? 1 : 0) + 12, accent ? 0.34 : 0.2);
    }
    inst.stab(m, t0, beat * 0.3, [n[0] + 12, n[1] + 12, n[2] + 12], 0.08);
    inst.stab(m, t0 + 1.5 * beat, beat * 0.2, [n[0] + 12, n[1] + 12, n[2] + 12], 0.06);
    inst.stab(m, t0 + 3 * beat, beat * 0.2, [n[0] + 13, n[1] + 13, n[2] + 13], 0.065);
    for (let i = 0; i < 8; i++) {
      if (i % 2 === 0 || i === 5 || i === 7) { kick(m, t0 + i * beat / 2, 0.95); m.pump(t0 + i * beat / 2, 0.45, beat * 0.4); }
      if (i === 2 || i === 6) { snare(m, t0 + i * beat / 2, 0.5); clap(m, t0 + i * beat / 2, 0.22); }
    }
    for (let i = 0; i < 16; i++) hat(m, t0 + i * beat / 4, i % 2 ? 0.06 : 0.04, i % 8 === 6, i % 2 ? 0.3 : -0.3);
    if (bar === 7) { riser(m, t0, 4 * beat, 0.2); }
  });
  melody(inst.lead, m, 32, beat, `
    C#6:1 E6:1 D6:.5 C#6:.5 G#5:1
    A5:.75 G#5:.75 E5:.5 G#5:2
    D6:1 F#6:1 E6:.5 D6:.5 A5:1
    C#6:1.5 E6:.5 G#6:2
    A6:1 G#6:1 E6:.5 C#6:.5 A5:1
    C#6:.75 D6:.75 E6:.5 G#6:2
    F#6:1 D#6:1 B5:1 F#6:1
    E6:.5 D6:.5 C#6:.5 G#5:.5 C#6:2`, 0.082);
  finish(m, "boss", bpm, 0.95);
}

// One-shot stingers (not looped).
{
  const bpm = 126, beat = 60 / bpm, m = new Mix(6.2);
  [[60, 64, 67], [65, 69, 72], [67, 71, 74]].forEach((c, i) => inst.stab(m, i * beat * 0.5, beat * 0.36, c, 0.11));
  for (const n of [72, 76, 79, 84]) inst.pad(m, beat * 1.5, 3.4, n, 0.11);
  melody(inst.lead, m, 1.5, beat, "C6:.5 E6:.5 G6:.5 C7:2.5", 0.09);
  kick(m, 0, 0.8); kick(m, beat * 0.5, 0.7); kick(m, beat, 0.7); kick(m, beat * 1.5, 0.95); snare(m, beat * 1.5, 0.5);
  [0, 0.25, 0.5, 0.75, 1].forEach((d) => inst.bell(m, beat * 2 + d, 96 - d * 4 * 2, 0.05, d - 0.5));
  finish(m, "stinger_win", bpm, 0.8);
}
{
  const bpm = 80, beat = 60 / bpm, m = new Mix(5.5);
  const seq = [[64, 67, 71], [62, 65, 69], [60, 63, 67], [59, 62, 65]];
  seq.forEach((c, i) => { for (const n of c) inst.pad(m, i * beat * 0.75, beat * 1.2, n, 0.13); });
  melody(inst.lead, m, 0, beat, "B5:.75 A5:.75 G5:.75 E5:2.5", 0.07);
  kick(m, 0, 0.8); inst.bass(m, 0, 2, 40, 0.3); inst.bass(m, beat * 2.25, 2, 35, 0.3);
  finish(m, "stinger_lose", bpm, 0.76);
}

const sum = (dir) => fs.readdirSync(dir).reduce((a, f) => a + fs.statSync(path.join(dir, f)).size, 0);
console.log("sfx", fs.readdirSync(SFX_DIR).length, "files", (sum(SFX_DIR) / 1e6).toFixed(1), "MB; music", (sum(MUS_DIR) / 1e6).toFixed(1), "MB");
