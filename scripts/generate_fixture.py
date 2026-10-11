#!/usr/bin/env python3
"""Deterministic independent Robot 36 transmitter; Python standard library only.
Timing reference: pySSTV Robot36 and SSTV Handbook. No decoder imports.
Outputs PCM16 mono 48 kHz WAV and its RGB source PNG.
"""
import math
from pathlib import Path
import struct
import wave
import zlib

ROOT = Path(__file__).resolve().parents[1] / 'SSTVReceiverTests' / 'Fixtures'
ROOT.mkdir(parents=True, exist_ok=True)
COLORS = [(230, 220, 210), (220, 30, 40), (30, 210, 40), (30, 40, 220),
          (210, 210, 30), (30, 210, 210), (210, 30, 210), (30, 30, 30)]

def rgb(x, y):
    return tuple(round(c * (1 if y < 120 else .55)) for c in COLORS[x // 40])

def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data))

raw = b''.join(b'\0' + bytes(c for x in range(320) for c in rgb(x, y)) for y in range(240))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 320, 240, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
(ROOT / 'source.png').write_bytes(png)

rate, phase, endpoint, count = 48000, 0.0, 0.0, 0
pcm = bytearray()
def tone(hz, seconds):
    global phase, endpoint, count
    endpoint += rate * seconds
    target = round(endpoint)
    for _ in range(target - count):
        pcm.extend(struct.pack('<h', round(24575 * math.sin(phase))))
        phase = (phase + 2 * math.pi * hz / rate) % (2 * math.pi)
    count = target

tone(1900, .3); tone(1200, .01); tone(1900, .3); tone(1200, .03)
for bit in range(7): tone(1100 if 8 & (1 << bit) else 1300, .03)
tone(1100, .03); tone(1200, .03)
for row in range(240):
    pixels = [rgb(x, row) for x in range(320)]
    lumas = [.299*r + .587*g + .114*b for r,g,b in pixels]
    tone(1200, .009); tone(1500, .003)
    for y in lumas: tone(1500 + 800*y/255, .088/320)
    tone(1500 if row % 2 == 0 else 2300, .0045); tone(1900, .0015)
    for (r,g,b), y in zip(pixels, lumas):
        c = 128 + ((r-y)/1.402 if row % 2 == 0 else (b-y)/1.772)
        tone(1500 + 800*c/255, .044/320)
tone(1900, .03)
with wave.open(str(ROOT / 'robot36.wav'), 'wb') as wav:
    wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(rate); wav.writeframes(pcm)
print(f'Wrote source.png and robot36.wav ({count/rate:.2f}s)')
