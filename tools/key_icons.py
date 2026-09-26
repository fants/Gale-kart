"""绿幕抠图：把绿底（#00FF00）插画抠成透明 PNG，裁到内容。

插画用 GPT Image 生成在纯绿背景上。抠像按「绿色溢出量」g - max(r, b) 算透明度，
半透明边缘按背景色反解出前景色，去掉绿边。

用法：
  python3 tools/key_icons.py <原图目录> [输出目录] [--size 256] [--wide 1400]
    默认输出 assets/ui/items（道具图标）。--size：补成正方形并缩放到该边长；
    --wide：不补正方形，按宽度缩放（Logo 这类横幅用）。
  例：道具 python3 tools/key_icons.py raw/items
      菜单图标 python3 tools/key_icons.py raw/icons assets/ui/icons
      Logo python3 tools/key_icons.py raw/logo assets/ui --wide 1400
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets/ui/items"
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


def trim(im: Image.Image) -> Image.Image:
    a = np.asarray(im)[..., 3]
    ys, xs = np.nonzero(a > 10)
    return im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def fit_square(im: Image.Image, size: int) -> Image.Image:
    im = trim(im)
    side = int(max(im.width, im.height) * (1.0 + 2.0 * MARGIN))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    return canvas.resize((size, size), Image.LANCZOS)


def fit_wide(im: Image.Image, width: int) -> Image.Image:
    im = trim(im)
    return im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)


def main() -> None:
    args = sys.argv[1:]
    size, wide = SIZE, 0
    if "--size" in args:
        k = args.index("--size")
        size = int(args[k + 1])
        del args[k:k + 2]
    if "--wide" in args:
        k = args.index("--wide")
        wide = int(args[k + 1])
        del args[k:k + 2]
    src = Path(args[0])
    out_dir = Path(args[1]) if len(args) > 1 else OUT_DIR
    if not out_dir.is_absolute():
        out_dir = ROOT / out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in sorted(src.glob("*.png")):
        im = key_green(Image.open(f))
        out = fit_wide(im, wide) if wide else fit_square(im, size)
        out.save(out_dir / f.name)
        print(f"{f.stem}: {(out_dir / f.name).relative_to(ROOT)}  {out.size}")


if __name__ == "__main__":
    main()
