"""应用图标：把满版方形插画套进 macOS 风格的圆角方块，输出 assets/icon.png。
插画原图（GPT Image 生成）不放在仓库里，运行时传入路径。

1024×1024 透明画布，824×824 的超椭圆圆角方块居中（苹果图标网格），下方一层柔和投影。
Windows / 窗口图标用同一张图，Godot 导出时自动转成 .icns / .ico。

用法：python3 tools/make_icon.py <插画原图.png>
"""

import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/icon.png"

CANVAS = 1024
BODY = 824
# 超椭圆指数：越大越接近直角，5 左右接近苹果的连续曲率圆角
SQUIRCLE_N = 5.0
SS = 4  # 蒙版超采样倍数，抗锯齿


def squircle_mask(size: int) -> Image.Image:
    big = size * SS
    r = big / 2.0
    mask = Image.new("L", (big, big), 0)
    pts = []
    steps = 720
    for i in range(steps):
        t = 2.0 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = r + r * math.copysign(abs(c) ** (2.0 / SQUIRCLE_N), c)
        y = r + r * math.copysign(abs(s) ** (2.0 / SQUIRCLE_N), s)
        pts.append((x, y))
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("用法：python3 tools/make_icon.py <插画原图.png>")
    art = Image.open(sys.argv[1]).convert("RGB")
    s = min(art.size)
    art = art.crop(((art.width - s) // 2, (art.height - s) // 2, (art.width + s) // 2, (art.height + s) // 2))
    art = art.resize((BODY, BODY), Image.LANCZOS)
    mask = squircle_mask(BODY)
    off = (CANVAS - BODY) // 2

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    # 投影：圆角方块形状，往下偏 12 px，模糊后 30% 不透明度
    shadow = Image.new("L", (CANVAS, CANVAS), 0)
    shadow.paste(mask, (off, off + 12))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.30))
    canvas.paste(Image.new("RGBA", (CANVAS, CANVAS), (10, 14, 40, 255)), (0, 0), shadow)

    body = art.convert("RGBA")
    # 边缘一圈很淡的内描边，浅色背景上也有清楚的轮廓
    edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(5)))
    body.paste(Image.new("RGBA", (BODY, BODY), (255, 255, 255, 255)), (0, 0), edge.point(lambda v: int(v * 0.18)))
    canvas.paste(body, (off, off), mask)
    canvas.save(OUT)
    print(f"{OUT.relative_to(ROOT)}  {canvas.size}")


if __name__ == "__main__":
    main()
