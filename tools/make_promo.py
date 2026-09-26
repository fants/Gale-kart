"""作者推广素材：吉祥物「铂金小鸟」抠图、赛道广告牌与起点横幅（在插画上用游戏字体写「bilibili @名字」）。

名字从 src/data/credits.gd 的 NAME 读取，改名后重新运行即可。
插画原图（GPT Image 生成）在 assets/branding/promo_src/（有 .gdignore，不打进游戏包）：
mascot.png、mascot_wave.png（绿幕）、board_1.png、board_2.png。

用法：python3 tools/make_promo.py [原图目录]
"""

import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from key_icons import fit_square, key_green  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FONT_CN = str(ROOT / "assets/fonts/ZCOOLKuaiLe-Regular.ttf")
# 「bilibili」要小写：Bungee 只有大写，改用站酷快乐体的西文字形
FONT_EN = FONT_CN
INK = (27, 31, 59)
PINK = (251, 114, 153)
BLUE = (0, 174, 236)
WHITE = (255, 255, 255)


def creator_name() -> str:
    s = (ROOT / "src/data/credits.gd").read_text(encoding="utf-8")
    return re.search(r'const NAME := "([^"]+)"', s).group(1)


def cover(im: Image.Image, w: int, h: int) -> Image.Image:
    s = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    x, y = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def text(d: ImageDraw.ImageDraw, xy, s: str, font, fill, stroke, sw: int, anchor: str, shadow=None) -> None:
    if shadow:
        d.text((xy[0], xy[1] + sw * 0.9), s, font=font, fill=shadow, stroke_width=sw, stroke_fill=shadow, anchor=anchor)
    d.text(xy, s, font=font, fill=fill, stroke_width=sw, stroke_fill=stroke, anchor=anchor)


def board(bg: Image.Image, name: str, text_center_x: float) -> Image.Image:
    """2:1 广告牌：插画 + 右 / 左侧的文字区"""
    W, H = 2048, 1024
    im = cover(bg.convert("RGB"), W, H).convert("RGBA")
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = W * text_center_x
    # 「bilibili」胶囊标签
    f_en = ImageFont.truetype(FONT_EN, 140)
    tw = d.textlength("bilibili", font=f_en)
    pill = (cx - tw / 2 - 60, 170, cx + tw / 2 + 60, 350)
    d.rounded_rectangle((pill[0], pill[1] + 14, pill[2], pill[3] + 14), radius=90, fill=(*INK, 120))
    d.rounded_rectangle(pill, radius=90, fill=BLUE, outline=INK, width=10)
    text(d, (cx, 256), "bilibili", f_en, WHITE, INK, 8, "mm")
    # 「@名字」大字
    f_cn = ImageFont.truetype(FONT_CN, 250 if len(name) <= 4 else int(1000 / len(name)))
    text(d, (cx, 560), "@" + name, f_cn, WHITE, INK, 16, "mm", shadow=(*PINK, 255))
    # 副标题
    f_sub = ImageFont.truetype(FONT_CN, 96)
    text(d, (cx, 800), "关注我 · 看更多赛车视频！", f_sub, (255, 236, 120), INK, 10, "mm")
    return Image.alpha_composite(im, layer).convert("RGB")


def banner(mascot: Image.Image, wave: Image.Image, name: str) -> Image.Image:
    """3:1 起点横幅：品牌粉底 + 小鸟头像 + 「bilibili @名字」"""
    W, H = 1536, 512
    im = Image.new("RGB", (W, H), PINK)
    d = ImageDraw.Draw(im)
    # 斜条纹
    for x in range(-H, W, 90):
        d.polygon([(x, 0), (x + 40, 0), (x + 40 + H, H), (x + H, H)], fill=(255, 140, 175))
    d.rectangle((0, 0, W, 28), fill=INK)
    d.rectangle((0, H - 28, W, H), fill=INK)
    ms = 330
    m = mascot.resize((ms, ms), Image.LANCZOS)
    m2 = wave.resize((ms, ms), Image.LANCZOS)
    im.paste(m, (30, (H - ms) // 2 + 10), m)
    im.paste(m2, (W - ms - 30, (H - ms) // 2 + 10), m2)
    # 文字放在两只小鸟之间，放不下就缩小字号
    room = W - 2 * (ms + 60)
    size = 170
    while True:
        f_en = ImageFont.truetype(FONT_EN, int(size * 0.72))
        f_cn = ImageFont.truetype(FONT_CN, size)
        en_w = d.textlength("bilibili ", font=f_en)
        cn_w = d.textlength("@" + name, font=f_cn)
        if en_w + cn_w <= room or size < 60:
            break
        size -= 6
    x0 = (W - en_w - cn_w) / 2
    text(d, (x0, H / 2 + 8), "bilibili ", f_en, WHITE, INK, 9, "lm")
    text(d, (x0 + en_w, H / 2), "@" + name, f_cn, WHITE, INK, 12, "lm", shadow=INK)
    return im


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "assets/branding/promo_src"
    name = creator_name()
    out_ui = ROOT / "assets/ui/creator"
    out_ui.mkdir(parents=True, exist_ok=True)
    mascot = key_green(Image.open(src / "mascot.png"))
    fit_square(mascot, 256).save(out_ui / "mascot.png")
    big = fit_square(mascot, 512)
    wave = fit_square(key_green(Image.open(src / "mascot_wave.png")), 512)
    ads = ROOT / "assets/textures/ads"
    board(Image.open(src / "board_2.png"), name, 0.36).resize((1024, 512), Image.LANCZOS).save(ads / "ad_creator.jpg", quality=90)
    board(Image.open(src / "board_1.png"), name, 0.64).resize((1024, 512), Image.LANCZOS).save(ads / "ad_creator_2.jpg", quality=90)
    banner(big, wave, name).resize((1024, 342), Image.LANCZOS).save(ads / "banner_creator.jpg", quality=90)
    print("作者：bilibili @" + name)
    for p in ["assets/ui/creator/mascot.png", "assets/textures/ads/ad_creator.jpg", "assets/textures/ads/ad_creator_2.jpg", "assets/textures/ads/banner_creator.jpg"]:
        print(" ", p)


if __name__ == "__main__":
    main()
