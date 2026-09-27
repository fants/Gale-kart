"""作者推广素材：赛道广告牌与起点横幅（在插画上用游戏字体写「bilibili @名字」）。

名字从 src/data/credits.gd 的 NAME 读取；头像用游戏里的圆形头像 assets/ui/creator/avatar.png。
- 起点横幅只需要头像，随时可以重新生成。
- 两块广告牌的背景插画（GPT Image 生成的 board_1.png、board_2.png）不放在仓库里；
  给出插画目录时才重新生成广告牌，否则保留仓库里现有的广告牌贴图。

用法：python3 tools/make_promo.py [广告牌插画目录]
"""

import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT_CN = str(ROOT / "assets/fonts/ZCOOLKuaiLe-Regular.ttf")
# 「bilibili」要小写：Bungee 只有大写，改用站酷快乐体的西文字形
FONT_EN = FONT_CN
INK = (27, 31, 59)
PINK = (251, 114, 153)
BLUE = (0, 174, 236)
WHITE = (255, 255, 255)
AVATAR = ROOT / "assets/ui/creator/avatar.png"


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


SUBTITLES = {"": "关注我 · 看更多赛车视频！", "_en": "Follow me for more racing videos!"}


def board(bg: Image.Image, name: str, text_center_x: float, avatar: Image.Image, subtitle: str) -> Image.Image:
    """2:1 广告牌：插画 + 右 / 左侧的文字区"""
    W, H = 2048, 1024
    im = cover(bg.convert("RGB"), W, H).convert("RGBA")
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = W * text_center_x
    # 「bilibili」胶囊标签
    # 第一行：圆形头像 + 「bilibili」胶囊，整组居中
    f_en = ImageFont.truetype(FONT_EN, 140)
    tw = d.textlength("bilibili", font=f_en)
    av = 250
    pw = tw + 120
    x0 = cx - (av + 30 + pw) / 2
    pill = (x0 + av + 30, 170, x0 + av + 30 + pw, 350)
    d.rounded_rectangle((pill[0], pill[1] + 14, pill[2], pill[3] + 14), radius=90, fill=(*INK, 120))
    d.rounded_rectangle(pill, radius=90, fill=BLUE, outline=INK, width=10)
    text(d, ((pill[0] + pill[2]) / 2, 256), "bilibili", f_en, WHITE, INK, 8, "mm")
    a = avatar.resize((av, av), Image.LANCZOS)
    layer.paste(a, (int(x0), 260 - av // 2), a)
    # 「@名字」大字
    f_cn = ImageFont.truetype(FONT_CN, 250 if len(name) <= 4 else int(1000 / len(name)))
    text(d, (cx, 560), "@" + name, f_cn, WHITE, INK, 16, "mm", shadow=(*PINK, 255))
    # 副标题
    size = 96
    while size > 40 and d.textlength(subtitle, font=ImageFont.truetype(FONT_CN, size)) > W * 0.6:
        size -= 4
    f_sub = ImageFont.truetype(FONT_CN, size)
    text(d, (cx, 800), subtitle, f_sub, (255, 236, 120), INK, 10, "mm")
    return Image.alpha_composite(im, layer).convert("RGB")


def banner(avatar: Image.Image, name: str) -> Image.Image:
    """3:1 起点横幅：品牌粉底 + 两端圆形头像 + 「bilibili @名字」"""
    W, H = 1536, 512
    im = Image.new("RGB", (W, H), PINK)
    d = ImageDraw.Draw(im)
    # 斜条纹
    for x in range(-H, W, 90):
        d.polygon([(x, 0), (x + 40, 0), (x + 40 + H, H), (x + H, H)], fill=(255, 140, 175))
    d.rectangle((0, 0, W, 28), fill=INK)
    d.rectangle((0, H - 28, W, H), fill=INK)
    ms = 360
    m = avatar.resize((ms, ms), Image.LANCZOS)
    im.paste(m, (50, (H - ms) // 2), m)
    im.paste(m, (W - ms - 50, (H - ms) // 2), m)
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
    name = creator_name()
    avatar = Image.open(AVATAR).convert("RGBA").resize((512, 512), Image.LANCZOS)
    ads = ROOT / "assets/textures/ads"
    out = ["assets/textures/ads/banner_creator.jpg"]
    banner(avatar, name).resize((1024, 342), Image.LANCZOS).save(ads / "banner_creator.jpg", quality=90)
    if len(sys.argv) > 1:
        src = Path(sys.argv[1])
        # 中文版与英文版（副标题不同）
        for suffix, sub in SUBTITLES.items():
            board(Image.open(src / "board_2.png"), name, 0.36, avatar, sub).resize((1024, 512), Image.LANCZOS).save(ads / f"ad_creator{suffix}.jpg", quality=90)
            board(Image.open(src / "board_1.png"), name, 0.64, avatar, sub).resize((1024, 512), Image.LANCZOS).save(ads / f"ad_creator_2{suffix}.jpg", quality=90)
            out += [f"assets/textures/ads/ad_creator{suffix}.jpg", f"assets/textures/ads/ad_creator_2{suffix}.jpg"]
    else:
        print("（没有给广告牌插画目录，只重新生成起点横幅）")
    print("作者：bilibili @" + name)
    for p in out:
        print(" ", p)


if __name__ == "__main__":
    main()
