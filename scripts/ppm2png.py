#!/usr/bin/env python3
"""ppm2png.py — конвертер P6 PPM -> PNG (только стандартная библиотека).
Используется для скриншотов QEMU (monitor screendump пишет PPM)."""
import struct
import sys
import zlib


def read_ppm(path):
    with open(path, "rb") as fh:
        data = fh.read()
    # заголовок: P6 <w> <h> <maxval>\n
    parts = []
    i = 0
    while len(parts) < 4:
        # пропуск комментариев и пробелов
        while data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            while data[i:i + 1] != b"\n":
                i += 1
            continue
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        parts.append(data[i:j])
        i = j
    i += 1  # один разделитель после maxval
    magic, w, h, maxval = parts[0], int(parts[1]), int(parts[2]), int(parts[3])
    assert magic == b"P6" and maxval == 255, "ожидается бинарный PPM (P6, 255)"
    return w, h, data[i:i + w * h * 3]


def write_png(path, w, h, rgb):
    def chunk(tag, payload):
        c = tag + payload
        return struct.pack(">I", len(payload)) + c + struct.pack(">I", zlib.crc32(c))

    raw = b"".join(
        b"\x00" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h)
    )
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as fh:
        fh.write(png)


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    width, height, pixels = read_ppm(src)
    write_png(dst, width, height, pixels)
    print(f"{dst} ({width}x{height})")
