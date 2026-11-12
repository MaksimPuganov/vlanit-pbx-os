#!/usr/bin/env python3
"""Генерация фонового изображения GRUB в фирменной стилистике VLANit
(палитра с vlanit.com: #09090b / #F5F4F0 / #D4AA6A).
Выполняется в build-контейнере (scripts/Dockerfile.build: python3-cairosvg,
python3-pil, fonts-dejavu-core).

Использование: make-grub-bg.py <logo.svg> <out.png>
"""
import sys

import cairosvg
from PIL import Image, ImageDraw

LOGO, OUT = sys.argv[1], sys.argv[2]
W, H = 1920, 1080
BG = (9, 9, 11)          # #09090b
BG2 = (18, 18, 20)       # #121214
GOLD = (212, 170, 106)   # #D4AA6A

img = Image.new("RGB", (W, H))
px = img.load()
for y in range(H):
    t = y / H
    c = tuple(int(BG[i] + (BG2[i] - BG[i]) * t) for i in range(3))
    for x in range(W):
        px[x, y] = c

# золотые фирменные полосы сверху и снизу (центр занят меню GRUB;
# текст помощи занимает левые ~85% — свободного места под логотип нет).
# Логотип VLANit представлен в консольном баннере /etc/issue.
draw = ImageDraw.Draw(img)
draw.rectangle([0, 0, W, 8], fill=GOLD)
draw.rectangle([0, H - 6, W, H], fill=GOLD)

img.save(OUT, optimize=True)
print("фон GRUB:", OUT, img.size)
