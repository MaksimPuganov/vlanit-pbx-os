#!/usr/bin/env python3
"""Фон GRUB VLANit: компактный бренд-локуп в верхней части (меню GRUB
занимает центр экрана). Палитра vlanit.com: #09090b / #F5F4F0 / #D4AA6A."""
import cairosvg
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
BG = (9, 9, 11)
BG2 = (18, 18, 20)
LIGHT = (245, 244, 240)
GOLD = (212, 170, 106)
GOLD_DEEP = (184, 150, 90)
MUTED = (138, 134, 128)

img = Image.new("RGB", (W, H))
px = img.load()
for y in range(H):
    t = y / H
    c = tuple(int(BG[i] + (BG2[i] - BG[i]) * t) for i in range(3))
    for x in range(W):
        px[x, y] = c

draw = ImageDraw.Draw(img)
draw.rectangle([0, 0, W, 8], fill=GOLD)

# знак «V» из логотипа (левая часть SVG) — маленький, слева сверху
cairosvg.svg2png(url="branding/vlanit-logo-on-dark.svg", write_to="/tmp/logo.png",
                 output_width=220, background_color="rgba(0,0,0,0)")
logo = Image.open("/tmp/logo.png").convert("RGBA")
mark = logo.crop((0, 0, int(logo.width * 0.42), logo.height))  # только знак V
mark = mark.resize((96, int(mark.height * 96 / mark.width)), Image.LANCZOS)
img.paste(mark, (96, 42), mark)

font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 52)
small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 30)
draw = ImageDraw.Draw(img)
draw.text((216, 52), "VLANit", font=font, fill=LIGHT)
w_vlanit = draw.textlength("VLANit", font=font)
draw.text((216 + w_vlanit + 18, 66), "PBX OS", font=font, fill=GOLD)
draw.text((220, 122), "Debian 13  ·  Podman  ·  MikoPBX", font=small, fill=MUTED)

img.save("branding/vlanit-grub-bg.png", optimize=True)
print("saved", img.size)
