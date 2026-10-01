"""Flutify 品牌标生成器：一套几何参数 → SVG 母版 + 各平台图标。

设计：连续曲率圆角方块（superellipse，n=5，接近 iOS 图标轮廓）+ 品牌绿对角渐变；
白色字形为「F」——竖笔 + 一长一短两道横笔（像递减的音量电平），第三行收成圆点（音符 / 播放头）。
App 内的 `FlutifyMark`（lib/ui/screens/auth/widgets/flutify_mark.dart）按同一组比例绘制，改这里要同步改那里。

用法（在 app 目录）：python tool/brand/generate_logo.py
输出：
  assets/brand/flutify_logo.svg / flutify_logo_1024.png / flutify_glyph.svg
  windows/runner/resources/app_icon.ico
  android/app/src/main/res/mipmap-*/ic_launcher.png（旧版启动器）
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png + mipmap-anydpi-v26/ic_launcher.xml（自适应图标）
"""

import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# ---------------------------------------------------------------------------
# 几何（以边长 1 为单位）
# ---------------------------------------------------------------------------
GREEN_LIGHT = (0x3B, 0xE4, 0x77)  # 左上
GREEN_DEEP = (0x12, 0x9A, 0x48)  # 右下：比品牌绿更深，白字对比更足
SUPERELLIPSE_N = 5.0

T = 0.118  # 笔画粗细
X0 = 0.300  # 竖笔左缘
Y0 = 0.250  # 顶部
Y1 = 0.750  # 底部
TOP_BAR_RIGHT = 0.720
MID_BAR_RIGHT = 0.600
DOT_GAP = 0.062  # 圆点与竖笔的间距

# 字形元素：(类型, 参数)，矩形均为全圆角（半径 T/2）
GLYPH = [
    ('rect', (X0, Y0, X0 + T, Y1)),  # 竖笔
    ('rect', (X0, Y0, TOP_BAR_RIGHT, Y0 + T)),  # 上横（长）
    ('rect', (X0, 0.5 - T / 2, MID_BAR_RIGHT, 0.5 + T / 2)),  # 中横（短）
    ('circle', (X0 + T + DOT_GAP + T / 2, Y1 - T / 2, T / 2)),  # 圆点
]


def superellipse(size, inset=0.0, steps=720):
    """边长 size 的方框内（四周留 inset 比例）的 superellipse 轮廓点。"""
    half = size * (1 - 2 * inset) / 2
    c = size / 2
    pts = []
    for i in range(steps):
        a = 2 * math.pi * i / steps
        ca, sa = math.cos(a), math.sin(a)
        x = math.copysign(abs(ca) ** (2 / SUPERELLIPSE_N), ca)
        y = math.copysign(abs(sa) ** (2 / SUPERELLIPSE_N), sa)
        pts.append((c + half * x, c + half * y))
    return pts


# ---------------------------------------------------------------------------
# SVG
# ---------------------------------------------------------------------------
def glyph_svg(scale=1024, offset=0.0, fill='#FFFFFF'):
    parts = []
    r = T / 2 * scale
    for kind, p in GLYPH:
        if kind == 'rect':
            x0, y0, x1, y1 = (v * scale + offset for v in p)
            parts.append(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{x1 - x0:.1f}" height="{y1 - y0:.1f}" '
                         f'rx="{r:.1f}" fill="{fill}"/>')
        else:
            cx, cy, cr = p
            parts.append(f'<circle cx="{cx * scale + offset:.1f}" cy="{cy * scale + offset:.1f}" r="{cr * scale:.1f}" '
                         f'fill="{fill}"/>')
    return '\n  '.join(parts)


def write_svgs():
    s = 1024
    pts = superellipse(s)
    path = 'M' + ' L'.join(f'{x:.1f},{y:.1f}' for x, y in pts) + ' Z'
    hex_ = lambda c: '#%02X%02X%02X' % c
    logo = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s} {s}" width="{s}" height="{s}">
  <!-- Flutify 品牌标（由 tool/brand/generate_logo.py 生成，勿手改） -->
  <defs>
    <linearGradient id="plate" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{hex_(GREEN_LIGHT)}"/>
      <stop offset="1" stop-color="{hex_(GREEN_DEEP)}"/>
    </linearGradient>
  </defs>
  <path d="{path}" fill="url(#plate)"/>
  {glyph_svg(s)}
</svg>
'''
    glyph = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s} {s}" width="{s}" height="{s}">
  <!-- Flutify 字形（单色，可用于单色场景 / 通知图标），由 tool/brand/generate_logo.py 生成 -->
  {glyph_svg(s, fill='#000000')}
</svg>
'''
    out = os.path.join(ROOT, 'assets', 'brand')
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, 'flutify_logo.svg'), 'w', encoding='utf-8') as f:
        f.write(logo)
    with open(os.path.join(out, 'flutify_glyph.svg'), 'w', encoding='utf-8') as f:
        f.write(glyph)


# ---------------------------------------------------------------------------
# 栅格化（4 倍超采样后 LANCZOS 缩小，边缘平滑）
# ---------------------------------------------------------------------------
SS = 4


def draw_glyph(draw, size, scale=1.0, offset=(0.0, 0.0), fill=(255, 255, 255, 255)):
    """在 size 画布上绘制字形；scale / offset 用于自适应图标把字形缩进安全区。"""
    ox, oy = offset
    r = T / 2 * size * scale
    tf = lambda v, o: (v * scale) * size + o
    for kind, p in GLYPH:
        if kind == 'rect':
            x0, y0, x1, y1 = p
            draw.rounded_rectangle((tf(x0, ox), tf(y0, oy), tf(x1, ox), tf(y1, oy)), radius=r, fill=fill)
        else:
            cx, cy, cr = p
            cx, cy, cr = tf(cx, ox), tf(cy, oy), cr * size * scale
            draw.ellipse((cx - cr, cy - cr, cx + cr, cy + cr), fill=fill)


def gradient(size):
    """左上 → 右下的对角渐变。"""
    small = 256
    img = Image.new('RGB', (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(GREEN_LIGHT, GREEN_DEEP))
    return img.resize((size, size), Image.BICUBIC)


def render_logo(px, inset=0.0):
    """完整品牌标（squircle 底板 + 字形）；inset 为四周留白比例。"""
    s = px * SS
    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).polygon(superellipse(s, inset), fill=255)
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    img.paste(gradient(s), (0, 0), mask)
    # 字形随底板一起缩进
    inner = 1 - 2 * inset
    draw_glyph(ImageDraw.Draw(img), s, scale=inner, offset=(s * inset, s * inset))
    return img.resize((px, px), Image.LANCZOS)


def render_foreground(px):
    """自适应图标前景：108dp 画布，字形缩进 72dp 区域（安全区 66dp 内留足余量）。"""
    s = px * SS
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    scale = 72 / 108
    off = s * (1 - scale) / 2
    draw_glyph(ImageDraw.Draw(img), s, scale=scale, offset=(off, off))
    return img.resize((px, px), Image.LANCZOS)


def write_rasters():
    brand = os.path.join(ROOT, 'assets', 'brand')
    render_logo(1024).save(os.path.join(brand, 'flutify_logo_1024.png'))

    # Windows：多尺寸 ICO，四周留 3% 与系统图标视觉大小一致
    ico_sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
    base = render_logo(256, inset=0.03)
    frames = [render_logo(n, inset=0.03) for n in ico_sizes]
    base.save(os.path.join(ROOT, 'windows', 'runner', 'resources', 'app_icon.ico'),
              sizes=[(n, n) for n in ico_sizes], append_images=frames)

    # Android
    res = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, k in densities.items():
        folder = os.path.join(res, f'mipmap-{name}')
        os.makedirs(folder, exist_ok=True)
        render_logo(round(48 * k), inset=0.06).save(os.path.join(folder, 'ic_launcher.png'))
        render_foreground(round(108 * k)).save(os.path.join(folder, 'ic_launcher_foreground.png'))

    anydpi = os.path.join(res, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, 'ic_launcher.xml'), 'w', encoding='utf-8') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<!-- 自适应图标：渐变底 + 白色字形（由 tool/brand/generate_logo.py 生成） -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''')
    drawable = os.path.join(res, 'drawable')
    hex_ = lambda c: '#FF%02X%02X%02X' % c
    with open(os.path.join(drawable, 'ic_launcher_background.xml'), 'w', encoding='utf-8') as f:
        f.write(f'''<?xml version="1.0" encoding="utf-8"?>
<!-- 自适应图标背景：与品牌标相同的对角渐变（由 tool/brand/generate_logo.py 生成） -->
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient
        android:angle="315"
        android:startColor="{hex_(GREEN_LIGHT)}"
        android:endColor="{hex_(GREEN_DEEP)}"/>
</shape>
''')


if __name__ == '__main__':
    write_svgs()
    write_rasters()
    print('done')
