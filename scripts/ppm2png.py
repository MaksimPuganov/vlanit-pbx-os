#!/usr/bin/env python3
"""ppm2png.py — конвертер P6 PPM -> PNG для скриншотов QEMU (monitor screendump).

Pillow — зависимость хоста тестов (apt install python3-pil; в build-контейнере
уже есть). Раньше был самописный PNG-энкодер (~55 строк) — заменён (ponytail #27).
"""
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("ppm2png: требуется Pillow (apt install python3-pil)")

src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src)          # Pillow читает PPM (P6) сам
img.save(dst, "PNG")
print(f"{dst} ({img.width}x{img.height})")
