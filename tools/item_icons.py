"""道具图标：把绿幕底的道具插画抠成透明 PNG，裁到内容、补成正方形，输出 assets/ui/items/<id>.png（256×256）。

插画用 GPT Image 生成在纯绿（#00FF00）背景上。抠像按「绿色溢出量」g - max(r, b) 算透明度，
半透明边缘按背景色反解出前景色，去掉绿边。

用法：python3 tools/item_icons.py <绿幕原图目录>   （目录里是 nitro.png、missile.png …）
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets/ui/items"
IDS = ["nitro", "missile", "water", "banana", "shield", "cloud", "magnet", "thunder", "ufo", "water_fly"]
SIZE = 256
# 绿色溢出量低于 LO 完全不透明，高于 HI 完全透明
LO, HI = 40.0, 150.0
MARGIN = 0.05


def key_green(im: Image.Image) -> Image.Image:
    rgb = np.asarray(im.convert("RGB")).astype(np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # 背景色取四角的中位数
    h, w = g.shape
    corners = np.concatenate([rgb[:8, :8].reshape(-1, 3), rgb[:8, -8:].reshape(-1, 3), rgb[-8:, :8].reshape(-1, 3), rgb[-8:, -8:].reshape(-1, 3)])
    bg = np.median(corners, axis=0)
    spill = g - np.maximum(r, b)
    alpha = 1.0 - np.clip((spill - LO) / (HI - LO), 0.0, 1.0)
    # 半透明像素：C = a·F + (1 - a)·BG → F = (C - (1 - a)·BG) / a
    a3 = np.maximum(alpha, 1e-3)[..., None]
    fg = (rgb - (1.0 - alpha[..., None]) * bg) / a3
    fg = np.clip(fg, 0.0, 255.0)
    # 残余绿边：绿色不高于红蓝中较大者太多
    fg[..., 1] = np.minimum(fg[..., 1], np.maximum(fg[..., 0], fg[..., 2]) + 12.0)
    out = np.dstack([fg, alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def fit_square(im: Image.Image) -> Image.Image:
    a = np.asarray(im)[..., 3]
    ys, xs = np.nonzero(a > 10)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    im = im.crop((x0, y0, x1, y1))
    side = int(max(im.width, im.height) * (1.0 + 2.0 * MARGIN))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    src = Path(sys.argv[1])
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for i in IDS:
        im = Image.open(src / f"{i}.png")
        icon = fit_square(key_green(im))
        icon.save(OUT_DIR / f"{i}.png")
        print(f"{i}: {OUT_DIR.relative_to(ROOT)}/{i}.png")


if __name__ == "__main__":
    main()
