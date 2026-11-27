// Writes Goldfish's 8-bit sound effects as small WAV files in App/Resources/Sounds.
// Every sound is made here from square, triangle and noise waves, so there are no third-party samples
// and no licences to track. Run with `node tools/sound/build-sfx.mjs`, then play the WAVs to check them.
//
// None of them is a failure buzzer: a Mix-up is a curious wobble and a Gap is a bubble.

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RATE = 22050;
const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', '..', 'App', 'Resources', 'Sounds');

// A deterministic noise source, so rebuilding gives identical files.
let seed = 12345;
function noise() {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return (seed / 0x3fffffff) - 1;
}

const square = (phase, duty = 0.5) => ((phase % 1) < duty ? 1 : -1);
const triangle = (phase) => 1 - 4 * Math.abs((phase % 1) - 0.5);

/**
 * One note. `freq` can be a number or a function of t (0 to 1 across the note) for slides.
 * The envelope is a short attack and a linear or exponential release, so nothing clicks.
 */
function tone({ freq, ms, wave = 'square', duty = 0.25, volume = 0.5, attack = 4, decay = 'linear', vibrato = 0 }) {
  const n = Math.round((RATE * ms) / 1000);
  const samples = new Float32Array(n);
  let phase = 0;
  const attackN = Math.max(1, Math.round((RATE * attack) / 1000));
  for (let i = 0; i < n; i++) {
    const t = i / n;
    let f = typeof freq === 'function' ? freq(t) : freq;
    if (vibrato) f *= 1 + vibrato * Math.sin(2 * Math.PI * 6 * (i / RATE));
    phase += f / RATE;
    let v;
    if (wave === 'square') v = square(phase, duty);
    else if (wave === 'triangle') v = triangle(phase);
    else v = noise();
    const env = Math.min(1, i / attackN) * (decay === 'exp' ? Math.exp(-5 * t) : 1 - t);
    samples[i] = v * env * volume;
  }
  return samples;
}

const rest = (ms) => new Float32Array(Math.round((RATE * ms) / 1000));

function join_(...parts) {
  const total = parts.reduce((s, p) => s + p.length, 0);
  const result = new Float32Array(total);
  let offset = 0;
  for (const p of parts) {
    result.set(p, offset);
    offset += p.length;
  }
  return result;
}

/** Mixes parts that start together. */
function mix(...parts) {
  const total = Math.max(...parts.map((p) => p.length));
  const result = new Float32Array(total);
  for (const p of parts) for (let i = 0; i < p.length; i++) result[i] += p[i];
  return result;
}

/** A one-pole low-pass, to soften noise into a swish. */
function lowpass(samples, amount) {
  const result = new Float32Array(samples.length);
  let last = 0;
  for (let i = 0; i < samples.length; i++) {
    last += amount * (samples[i] - last);
    result[i] = last;
  }
  return result;
}

const note = (name) => {
  const names = { C: -9, D: -7, E: -5, F: -4, G: -2, A: 0, B: 2 };
  const octave = Number(name.slice(-1));
  const sharp = name.includes('#') ? 1 : 0;
  return 440 * 2 ** ((names[name[0]] + sharp + (octave - 4) * 12) / 12);
};

const sounds = {
  // Two rising notes: right.
  correct: () => join_(
    tone({ freq: note('E5'), ms: 70, duty: 0.25, volume: 0.35 }),
    tone({ freq: note('B5'), ms: 150, duty: 0.25, volume: 0.35, decay: 'exp' }),
  ),
  // "Hm?": a soft triangle that dips and comes back up. Curious, not wrong.
  mixup: () => tone({
    freq: (t) => note('A4') * (1 - 0.12 * Math.sin(Math.PI * t)),
    ms: 260, wave: 'triangle', volume: 0.45, attack: 10,
  }),
  // A bubble: two quick upward blips.
  gap: () => join_(
    tone({ freq: (t) => 300 + 700 * t, ms: 70, wave: 'triangle', volume: 0.45, decay: 'exp' }),
    rest(30),
    tone({ freq: (t) => 420 + 900 * t, ms: 60, wave: 'triangle', volume: 0.35, decay: 'exp' }),
  ),
  // A tiny tick for choosing an option.
  select: () => tone({ freq: 1320, ms: 28, duty: 0.5, volume: 0.22, attack: 1 }),
  // A card turning: filtered noise falling away.
  flip: () => lowpass(tone({ freq: 1, ms: 110, wave: 'noise', volume: 0.5, attack: 6 }), 0.18),
  // Every question right: a quick arpeggio up to a held note.
  cheer: () => join_(
    tone({ freq: note('C5'), ms: 60, volume: 0.3 }),
    tone({ freq: note('E5'), ms: 60, volume: 0.3 }),
    tone({ freq: note('G5'), ms: 60, volume: 0.3 }),
    tone({ freq: note('C6'), ms: 260, volume: 0.3, decay: 'exp', vibrato: 0.01 }),
  ),
  // An idea mastered: a longer fanfare with a shimmer under the last note.
  mastered: () => join_(
    tone({ freq: note('G4'), ms: 55, volume: 0.28 }),
    tone({ freq: note('C5'), ms: 55, volume: 0.28 }),
    tone({ freq: note('E5'), ms: 55, volume: 0.28 }),
    tone({ freq: note('G5'), ms: 55, volume: 0.28 }),
    mix(
      tone({ freq: note('C6'), ms: 480, volume: 0.26, decay: 'exp', vibrato: 0.012 }),
      tone({ freq: note('E6'), ms: 480, wave: 'triangle', volume: 0.18, decay: 'exp' }),
    ),
  ),
  // The fire catching: crackle, then a rising whoosh.
  fire: () => mix(
    lowpass(tone({ freq: 1, ms: 420, wave: 'noise', volume: 0.35, attack: 20, decay: 'exp' }), 0.35),
    join_(rest(60), tone({ freq: (t) => 180 + 520 * t * t, ms: 360, wave: 'triangle', volume: 0.4, attack: 30 })),
  ),
  // Sent: a quick upward sweep.
  send: () => tone({ freq: (t) => 400 + 1300 * t, ms: 150, duty: 0.125, volume: 0.25, decay: 'exp' }),
};

function wav(samples) {
  const data = Buffer.alloc(samples.length * 2);
  for (let i = 0; i < samples.length; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    data.writeInt16LE(Math.round(v * 32767), i * 2);
  }
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + data.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(1, 22); // mono
  header.writeUInt32LE(RATE, 24);
  header.writeUInt32LE(RATE * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write('data', 36);
  header.writeUInt32LE(data.length, 40);
  return Buffer.concat([header, data]);
}

mkdirSync(out, { recursive: true });
for (const [name, make] of Object.entries(sounds)) {
  const samples = make();
  const file = join(out, `${name}.wav`);
  writeFileSync(file, wav(samples));
  console.log(`${name}.wav  ${(samples.length / RATE * 1000).toFixed(0)} ms`);
}
