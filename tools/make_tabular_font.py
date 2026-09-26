"""等宽数字版 Bungee：把 0–9 的字宽统一成最宽的数字（字形居中），+ - − 也统一宽度，去掉字距调整（GPOS）。

跑秒、速度这类不停变化的数字用它，数字宽度不变就不会左右抖动。
Bungee 使用 SIL OFL 1.1（无保留字体名），改名为「Bungee Tabular」以示区别。

用法：uv run --with fonttools python tools/make_tabular_font.py
"""

from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/fonts/Bungee-Regular.ttf"
OUT = ROOT / "assets/fonts/Bungee-Tabular.ttf"
GROUPS = ["0123456789", "+-−"]


def main() -> None:
    f = TTFont(SRC)
    cmap = f.getBestCmap()
    glyf = f["glyf"]
    hmtx = f["hmtx"]
    for chars in GROUPS:
        names = [cmap[ord(c)] for c in chars if ord(c) in cmap]
        width = max(hmtx[n][0] for n in names)
        for n in names:
            adv, lsb = hmtx[n]
            dx = (width - adv) // 2
            g = glyf[n]
            if g.numberOfContours > 0:
                g.coordinates.translate((dx, 0))
                g.recalcBounds(glyf)
                lsb = g.xMin
            hmtx[n] = (width, lsb)
    # 字距调整会破坏等宽，整张 GPOS 去掉（这个字体只用来显示数字）
    if "GPOS" in f:
        del f["GPOS"]
    for rec in f["name"].names:
        if rec.nameID in (1, 3, 4, 6, 16):
            s = rec.toUnicode()
            s = s.replace("Bungee-Regular", "BungeeTabular-Regular").replace("Bungee", "Bungee Tabular")
            rec.string = s
    f.save(OUT)
    print(OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
