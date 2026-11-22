#!/usr/bin/python3
"""Generate a short tonal shutter cue without broadband mechanical noise."""
import math
from pathlib import Path
import struct
import sys
import wave

destination = Path(sys.argv[1])
rate = 48000
samples = []
for index in range(round(rate * .160)):
    time = index / rate
    value = 0.0
    for start, duration, frequency in [(0, .045, 1150), (.065, .055, 800)]:
        phase = time - start
        if 0 <= phase < duration:
            envelope = math.sin(math.pi * phase / duration) ** 2
            value += .52 * envelope * (math.sin(2 * math.pi * frequency * phase)
                                      + .10 * math.sin(4 * math.pi * frequency * phase))
    samples.append(round(value * 32767))
destination.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(destination), 'wb') as stream:
    stream.setparams((1, 2, rate, len(samples), 'NONE', 'not compressed'))
    stream.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
