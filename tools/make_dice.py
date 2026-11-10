"""주사위 그림판 (3x2 칸, 칸마다 눈 1~6).

    python make_dice.py  →  ../textures/dice/dice_atlas.png
칸 순서: 1 2 3 / 4 5 6  (scripts/world3d/mesh_kit.gd 의 rounded_box(atlas=true) 와 맞춤)
"""
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "textures", "dice")
C = 256
S = 4
FACE = (253, 251, 244)
PIP = (10, 70, 74)
ONE = (238, 78, 96)
SPOTS = {
    1: [(0.5, 0.5)],
    2: [(0.3, 0.3), (0.7, 0.7)],
    3: [(0.28, 0.28), (0.5, 0.5), (0.72, 0.72)],
    4: [(0.3, 0.3), (0.7, 0.3), (0.3, 0.7), (0.7, 0.7)],
    5: [(0.28, 0.28), (0.72, 0.28), (0.5, 0.5), (0.28, 0.72), (0.72, 0.72)],
    6: [(0.3, 0.26), (0.7, 0.26), (0.3, 0.5), (0.7, 0.5), (0.3, 0.74), (0.7, 0.74)],
}


def face(n):
    im = Image.new("RGB", (C * S, C * S), FACE)
    # 가장자리로 갈수록 살짝 어둡게 (둥근 모서리 느낌)
    shade = Image.new("L", (C * S, C * S), 0)
    d = ImageDraw.Draw(shade)
    m = int(C * S * 0.04)
    d.rounded_rectangle([m, m, C * S - m, C * S - m], radius=C * S * 0.2, fill=255)
    shade = shade.filter(ImageFilter.GaussianBlur(C * S * 0.05))
    dark = Image.new("RGB", im.size, (226, 222, 210))
    im = Image.composite(im, dark, shade)
    d = ImageDraw.Draw(im)
    r = (0.13 if n == 1 else 0.085) * C * S
    col = ONE if n == 1 else PIP
    for x, y in SPOTS[n]:
        cx, cy = x * C * S, y * C * S
        # 오목한 눈: 테두리 그림자 + 안쪽
        d.ellipse([cx - r * 1.08, cy - r * 1.08, cx + r * 1.08, cy + r * 1.08], fill=tuple(int(c * 0.55) for c in col))
        d.ellipse([cx - r, cy - r * 0.92, cx + r, cy + r], fill=col)
        hl = r * 0.35
        d.ellipse([cx - r * 0.45 - hl, cy + r * 0.25 - hl, cx - r * 0.45 + hl, cy + r * 0.25 + hl],
                  fill=tuple(min(255, int(c * 1.35 + 30)) for c in col))
    return im.resize((C, C), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    atlas = Image.new("RGB", (C * 3, C * 2), FACE)
    for n in range(1, 7):
        k = n - 1
        atlas.paste(face(n), ((k % 3) * C, (k // 3) * C))
    atlas.save(os.path.join(OUT, "dice_atlas.png"))
    print("dice ->", OUT)
