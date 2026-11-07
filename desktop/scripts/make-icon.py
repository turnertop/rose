#!/usr/bin/env python3
"""Generate Rose's code-drawn Windows icon using only Python's standard library."""
import math
from pathlib import Path
import struct
import zlib


def rounded(x, y, left, top, right, bottom, radius):
    dx = max(left + radius - x, 0, x - right + radius)
    dy = max(top + radius - y, 0, y - bottom + radius)
    return left <= x <= right and top <= y <= bottom and dx * dx + dy * dy <= radius * radius


def png(size):
    rows = bytearray()
    for py in range(size):
        rows.append(0)
        for px in range(size):
            x, y = (px + .5) / size, (py + .5) / size
            if not rounded(x, y, .025, .025, .975, .975, .23):
                rows.extend((0, 0, 0, 0))
                continue
            t = min(1, (x + y) / 2)
            color = (round(255 - 38 * t), round(131 - 100 * t), round(185 - 65 * t), 255)
            # A tilted photo behind a second, upright photo.
            angle = -.18
            xx = (x - .43) * math.cos(angle) - (y - .46) * math.sin(angle) + .43
            yy = (x - .43) * math.sin(angle) + (y - .46) * math.cos(angle) + .46
            back = rounded(xx, yy, .23, .27, .69, .65, .055) and not rounded(xx, yy, .255, .295, .665, .625, .033)
            front = rounded(x, y, .34, .37, .8, .75, .05) and not rounded(x, y, .368, .398, .772, .722, .025)
            sun = (x - .66) ** 2 + (y - .47) ** 2 < .037 ** 2
            mountain = .38 < x < .76 and .58 < y < .71 and (y > .69 - .7 * (x - .39) if x < .57 else y > .55 + .9 * (x - .57))
            if back or front or sun or mountain:
                color = (255, 255, 255, 255)
            rows.extend(color)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')


sizes = (16, 32, 48, 64, 128, 256)
images = [png(size) for size in sizes]
offset = 6 + 16 * len(sizes)
header = bytearray(struct.pack('<HHH', 0, 1, len(sizes)))
for size, data in zip(sizes, images):
    header.extend(struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(data), offset))
    offset += len(data)
destination = Path(__file__).resolve().parents[1] / 'src/Rose.Desktop/Assets/Rose.ico'
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(header + b''.join(images))
destination.with_suffix('.png').write_bytes(images[-1])
print(destination)
