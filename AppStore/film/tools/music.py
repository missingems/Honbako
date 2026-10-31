"""Procedural 45-second score for the Honbako film. Deterministic: fixed seed, no samples.

Single felt-piano notes over a quiet pad in D major, on a slow 72 BPM grid, mostly rests. The
chords follow the film's sections (shots.json): one per feature, a higher register for the
Japanese section, a low octave on the title page and under the app icon on the end card, and a held
chord under the end card.
No sound effects, no page-turn sounds.

usage: python3 tools/music.py assets/audio/score.wav
"""
import sys
import wave
from pathlib import Path

import numpy as np

SR = 48000
DUR = 45.0
rng = np.random.default_rng(810)  # seeded; used only for gentle humanisation
N = int(SR * DUR)
t_all = np.arange(N) / SR


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def adsr(n, a, d, s, r):
    env = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = max(na, 1)
    env[:na] = np.linspace(0, 1, na)
    end_d = min(na + nd, n)
    env[na:end_d] = np.linspace(1, s, end_d - na)
    if nr > 0 and n > nr:
        env[-nr:] *= np.linspace(1, 0, nr)
    return env


def piano(m, dur, vel):
    """Felt-piano-ish tone: few inharmonic partials, fast attack, exponential decay, soft lowpass."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = midi_hz(m)
    tone = np.zeros(n)
    for k, amp in ((1, 1.0), (2, 0.42), (3, 0.16), (4, 0.07), (5, 0.03)):
        fk = f * k * (1 + 0.0004 * k * k)
        tone += amp * np.sin(2 * np.pi * fk * t) * np.exp(-t * (0.9 + 0.8 * k))
    hammer = np.exp(-t * 60) * np.sin(2 * np.pi * f * 2.01 * t) * 0.15
    env = np.minimum(1, t / 0.006)
    return (tone + hammer) * env * vel


def pad(ms, dur, vel):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for m in ms:
        f = midi_hz(m)
        for det in (-0.12, 0.0, 0.11):
            fd = f * 2 ** (det / 12)
            out += np.sin(2 * np.pi * fd * t + rng.uniform(0, 2 * np.pi)) * 0.5
            out += np.sin(2 * np.pi * 2 * fd * t) * 0.08
    lfo = 1 + 0.06 * np.sin(2 * np.pi * 0.21 * t)
    return out * adsr(n, 1.6, 0.5, 0.85, 1.8) * lfo * vel / len(ms)


def place(buf, sig, start):
    i = int(start * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i]


# One chord per beat of the film: the title page, then each feature, then the end card.
# Single felt-piano notes on a slow 72 BPM eighth grid, mostly rests, over a quiet pad.
EIGHTH = 60.0 / 72 / 2
D, Bm, G, A, Em, Fs = (38, [62, 66, 69, 76]), (35, [62, 66, 71, 74]), (31, [62, 67, 71, 74]), (33, [61, 64, 69, 73]), (40, [62, 67, 71, 76]), (42, [61, 66, 69, 73])
segments = [  # start, end, chord, energy, register lift
    (0.0, 3.2, D, 0.45, 0),
    (3.2, 5.8, D, 0.6, 0), (5.8, 8.2, Bm, 0.62, 0), (8.2, 10.6, G, 0.65, 0), (10.6, 13.0, A, 0.66, 0),
    (13.0, 15.4, D, 0.7, 0), (15.4, 17.8, Bm, 0.7, 0), (17.8, 20.2, Em, 0.72, 0), (20.2, 22.6, G, 0.75, 0), (22.6, 25.0, A, 0.75, 0),
    (25.0, 27.0, G, 0.78, 12), (27.0, 29.0, D, 0.8, 12), (29.0, 31.0, Em, 0.8, 12), (31.0, 33.0, A, 0.78, 12),
    (33.0, 35.0, G, 0.74, 0), (35.0, 37.0, Fs, 0.72, 0), (37.0, 38.8, Bm, 0.66, 0), (38.8, 40.6, A, 0.6, 0),
]
pattern = [0, None, None, 2, None, 1, None, None, 3, None, 2, None, None, 1, None, None]

piano_buf = np.zeros(N)
pad_buf = np.zeros(N)
bass_buf = np.zeros(N)

for start, end, (root, chord), energy, lift in segments:
    place(pad_buf, pad(chord[:3], end - start + 1.4, 0.42 * energy), start)
    place(bass_buf, piano(root, end - start + 1.5, 0.5 * energy), start)
    for i, idx in enumerate(pattern):
        when = start + i * EIGHTH + rng.normal(0, 0.004)
        if idx is None or when > end - 0.2:
            continue
        vel = (0.34 if i % 4 == 0 else 0.24) * energy * (1 + rng.normal(0, 0.05))
        place(piano_buf, piano(chord[idx] + lift, 3.4, vel), when)

# The title page: a low octave as the line settles under the app icon.
place(bass_buf, piano(26, 3.0, 0.5) + piano(38, 3.0, 0.35), 1.45)

# Colophon: the app icon arrives, then a held D major add9 that rings out.
end = 40.7
place(bass_buf, piano(26, 4.3, 0.5), end)
for m, v in ((38, 0.4), (57, 0.32), (62, 0.32), (66, 0.28), (69, 0.26), (76, 0.2)):
    place(piano_buf, piano(m, 4.3, v), end + 0.25 + (m - 38) * 0.012)
place(pad_buf, pad([62, 66, 69, 76], 4.3, 0.4), end)

mix = piano_buf * 0.9 + pad_buf * 0.55 + bass_buf * 0.6

# Small room: a few feedback-free early reflections plus a soft tail.
wet = np.zeros_like(mix)
for delay, gain in ((0.031, 0.32), (0.047, 0.26), (0.071, 0.2), (0.113, 0.15), (0.167, 0.11), (0.241, 0.08)):
    k = int(delay * SR)
    wet[k:] += mix[:-k] * gain
mix = mix + wet * 0.6

# Fades: in over 0.6 s, out over the last 2.2 s; settle the act boundaries slightly.
fade = np.ones(N)
fade[: int(0.6 * SR)] = np.linspace(0, 1, int(0.6 * SR))
fade[-int(2.2 * SR):] *= np.linspace(1, 0, int(2.2 * SR)) ** 1.5
mix *= fade

peak = np.max(np.abs(mix))
mix = np.tanh(mix / peak * 1.1) / np.tanh(1.1) * 0.84  # gentle saturation, -1.5 dBFS peak

stereo = np.stack([mix, np.roll(mix, int(0.0007 * SR))], axis=1)
pcm = (stereo * 32767).astype('<i2')
out = Path(sys.argv[1] if len(sys.argv) > 1 else 'score.wav')
out.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(out), 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print(out, f'{DUR:.1f}s')
