#!/usr/bin/env python3
"""Генерация фонового изображения GRUB в фирменной стилистике VLANit
(палитра с vlanit.com: #09090b / #F5F4F0 / #D4AA6A).
Выполняется в build-контейнере (scripts/Dockerfile.build: python3-cairosvg,
python3-pil, fonts-dejavu-core).

Использование: make-grub-bg.py <logo.svg> <out.png>
"""
import sys

import cairosvg
from PIL import Image, ImageDraw, ImageFont

LOGO, OUT = sys.argv[1], sys.argv[2]
W, H = 1920, 1080
BG = (9, 9, 11)          # #09090b
BG2 = (18, 18, 20)       # #121214
GOLD = (212, 170, 106)   # #D4AA6A
LIGHT = (245, 244, 240)  # #F5F4F0

img = Image.new("RGB", (W, H))
px = img.load()
for y in range(H):
    t = y / H
    c = tuple(int(BG[i] + (BG2[i] - BG[i]) * t) for i in range(3))
    for x in range(W):
        px[x, y] = c

# золотые фирменные полосы сверху и снизу (центр занят меню GRUB)
draw = ImageDraw.Draw(img)
draw.rectangle([0, 0, W, 8], fill=GOLD)
draw.rectangle([0, H - 6, W, H], fill=GOLD)

# компактный логотип по центру в свободной полосе между заголовком
# «GNU GRUB version…» (первая строка, по центру!) и рамкой меню.
# Свободная полоса на 800x600: ~40..66 px → на 1080p: ~72..119 px.
cairosvg.svg2png(url=LOGO, write_to="/tmp/_vlanit_logo.png",
                 output_width=220, background_color="rgba(0,0,0,0)")
logo = Image.open("/tmp/_vlanit_logo.png").convert("RGBA")
mark = logo.crop((0, 0, int(logo.width * 0.42), logo.height))
mark_h = 40                      # ≤ высоты полоси (~47 px на 1080p)
mark = mark.resize((int(mark.width * mark_h / mark.height), mark_h), Image.LANCZOS)
fb = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 28)
d2 = ImageDraw.Draw(img)
w1 = int(d2.textlength("VLANit", font=fb))
ws = int(d2.textlength(" ", font=fb))
w2 = int(d2.textlength("PBX OS", font=fb))
total = mark.width + 12 + w1 + ws + w2
x = (W - total) // 2
y = 72                           # верх полосы на 1080p
img.paste(mark, (x, y), mark)
d2.text((x + mark.width + 12, y + 7), "VLANit", font=fb, fill=LIGHT)
d2.text((x + mark.width + 12 + w1 + ws, y + 7), "PBX OS", font=fb, fill=GOLD)

img.save(OUT, optimize=True)
print("фон GRUB:", OUT, img.size)
