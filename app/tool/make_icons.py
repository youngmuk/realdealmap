# -*- coding: utf-8 -*-
"""런처 아이콘을 만든다.

Flutter 템플릿의 기본 아이콘을 그대로 두면 출시본이 "만들다 만 앱"으로 보인다.
디자인 도구 없이도 다시 만들 수 있도록 그리는 규칙을 코드로 남긴다 —
PNG만 커밋해 두면 나중에 크기 하나가 필요할 때 다시 그릴 방법이 없다.

  python tool/make_icons.py

앱 팔레트를 그대로 쓴다. 아이콘만 다른 색이면 런처에서 앱을 열었을 때
다른 앱에 들어온 것처럼 보인다.
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, '..', 'android', 'app', 'src', 'main', 'res')
STORE = os.path.join(HERE, '..', 'store')

INK = (0x16, 0x13, 0x0F, 255)      # Palette.ink
ACCENT = (0xC2, 0x41, 0x0C, 255)   # Palette.accent
PAPER = (0xFA, 0xF8, 0xF4, 255)    # Palette.paper
RULE = (0x3A, 0x33, 0x2A, 255)     # 잉크 위에서 겨우 보이는 격자

FONT = 'C:/Windows/Fonts/malgunbd.ttf'
SS = 4  # 초과표본. 작은 크기에서 가장자리가 거칠어지는 것을 막는다


def pin(draw, cx, cy, r, tip_y, color):
    """지도 핀. 원 하나와 삼각형 하나로 만든다 — 48px에서도 실루엣이 남는다."""
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    # 원과 꼭짓점을 잇는 삼각형. 원 안쪽에서 시작해야 이음매가 안 보인다
    draw.polygon([(cx - r * 0.72, cy + r * 0.62),
                  (cx + r * 0.72, cy + r * 0.62),
                  (cx, tip_y)], fill=color)


def grid(draw, size, color):
    """지도라는 것을 말하는 격자. 아주 옅게 — 작은 크기에서는 사라져도 된다."""
    step = size // 6
    w = max(1, size // 90)
    for i in range(1, 6):
        draw.line([(i * step, 0), (i * step, size)], fill=color, width=w)
        draw.line([(0, i * step), (size, i * step)], fill=color, width=w)


def won(draw, size, cx, cy, h, color):
    """원화 기호. 폰트에 없으면 W에 가로줄 둘을 직접 긋는다."""
    try:
        f = ImageFont.truetype(FONT, h)
    except OSError:
        f = ImageFont.load_default()
    try:
        draw.text((cx, cy), '\u20a9', font=f, fill=color, anchor='mm')
    except Exception:
        draw.text((cx, cy), 'W', font=f, fill=color, anchor='mm')


def foreground(size, safe=0.62):
    """적응형 아이콘의 앞면. 안쪽 [safe] 비율 밖은 잘려 나갈 수 있다."""
    img = Image.new('RGBA', (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size * SS
    inner = s * safe
    cx = s / 2
    # 핀 머리를 위쪽에, 꼭짓점을 아래쪽에 둔다
    r = inner * 0.30
    cy = s / 2 - inner * 0.10
    tip = cy + inner * 0.50
    pin(d, cx, cy, r, tip, ACCENT)
    won(d, s, cx, cy, int(r * 1.15), PAPER)
    return img.resize((size, size), Image.LANCZOS)


def background(size):
    img = Image.new('RGBA', (size * SS, size * SS), INK)
    grid(ImageDraw.Draw(img), size * SS, RULE)
    return img.resize((size, size), Image.LANCZOS)


def legacy(size):
    """구형 런처용. 배경과 앞면을 합치고 모서리를 둥글린다."""
    s = size * SS
    base = background(size).resize((s, s), Image.NEAREST)
    fg = foreground(size, safe=0.78).resize((s, s), Image.LANCZOS)
    base.alpha_composite(fg)

    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=255)
    base.putalpha(mask)
    return base.resize((size, size), Image.LANCZOS)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, 'PNG')
    print('  ', os.path.relpath(path, HERE), img.size)


DENSITIES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
# 적응형 앞면·뒷면은 108dp 기준이라 밀도마다 크기가 다르다
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}

print('런처 아이콘')
for name, px in DENSITIES.items():
    save(legacy(px), os.path.join(RES, f'mipmap-{name}', 'ic_launcher.png'))
print('적응형 레이어')
for name, px in ADAPTIVE.items():
    save(foreground(px), os.path.join(RES, f'mipmap-{name}', 'ic_launcher_foreground.png'))
    save(background(px), os.path.join(RES, f'mipmap-{name}', 'ic_launcher_background.png'))
print('스토어')
save(legacy(512), os.path.join(STORE, 'icon-512.png'))
