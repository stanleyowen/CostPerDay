"""Renders the Wallet app icon (default, dark and tinted variants).

The mark mirrors `BrandMark` in Theme.swift: two cards rising out of an
ember→amber wallet, closed by an ink clasp holding a white "today" dot — the dot
that has ended every version of the mark. Geometry is in unit coordinates shared
with `BrandMark.Geometry`.

Usage: python3 Design/make_icon.py Wallet/Assets.xcassets/AppIcon.appiconset
"""
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024
SS = 4  # supersampling factor
W = S * SS

EMBER = (255, 95, 58)
AMBER = (255, 178, 63)
INK = (22, 20, 34)
INK_RAISED = (46, 34, 66)

# Shared with `BrandMark.Geometry` in Theme.swift.
BACK_CARD = (0.25, 0.19, 0.69, 0.47)   # x0, y0, x1, y1
BACK_ANGLE = -10                        # degrees, clockwise positive
FRONT_CARD = (0.31, 0.24, 0.75, 0.52)
FRONT_ANGLE = 7
CARD_RADIUS = 0.045
CARD_STRIPE = (0.305, 0.345)            # y band of the magnetic stripe, before rotation
BODY = (0.17, 0.41, 0.83, 0.81)
BODY_RADIUS = 0.11
SEAM_Y = 0.47
CLASP = (0.58, 0.535, 0.89, 0.695)
DOT = (0.735, 0.615, 0.045)             # centre x, centre y, radius


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def diagonal_gradient(c0, c1):
    small = Image.new("RGB", (256, 256))
    p = small.load()
    for y in range(256):
        for x in range(256):
            p[x, y] = lerp(c0, c1, (x + y) / 510)
    return small.resize((W, W), Image.BICUBIC)


def vertical_gradient(c0, c1, y0, y1):
    small = Image.new("RGB", (1, 256))
    p = small.load()
    for y in range(256):
        p[0, y] = lerp(c0, c1, min(1, max(0, (y / 255 - y0) / (y1 - y0))))
    return small.resize((W, W), Image.BICUBIC)


def mask_rect(rect, radius, angle=0, rounded=True):
    mask = Image.new("L", (W, W), 0)
    box = tuple(v * W for v in rect)
    draw = ImageDraw.Draw(mask)
    if rounded:
        draw.rounded_rectangle(box, radius=radius * W, fill=255)
    else:
        draw.rectangle(box, fill=255)
    if angle:
        mask = mask.rotate(-angle, resample=Image.BICUBIC, center=((rect[0] + rect[2]) / 2 * W, (rect[1] + rect[3]) / 2 * W))
    return mask


def card(img, rect, angle, color, stripe_color):
    shape = mask_rect(rect, CARD_RADIUS, angle)
    shadow = shape.filter(ImageFilter.GaussianBlur(W * 0.012)).point(lambda v: int(v * 0.35))
    img.paste(Image.new("RGB", (W, W), (0, 0, 0)), (int(W * 0.004), int(W * 0.01)), shadow)
    img.paste(Image.new("RGB", (W, W), color), (0, 0), shape)
    # Rotate the stripe about the card's own centre so it stays on the card.
    stripe_rect = (rect[0], CARD_STRIPE[0] + (rect[1] - FRONT_CARD[1]), rect[2], CARD_STRIPE[1] + (rect[1] - FRONT_CARD[1]))
    stripe = Image.new("L", (W, W), 0)
    ImageDraw.Draw(stripe).rectangle(tuple(v * W for v in stripe_rect), fill=255)
    stripe = stripe.rotate(-angle, resample=Image.BICUBIC, center=((rect[0] + rect[2]) / 2 * W, (rect[1] + rect[3]) / 2 * W))
    img.paste(Image.new("RGB", (W, W), stripe_color), (0, 0), ImageChops.multiply(stripe, shape))


def render(variant):
    if variant == "default":
        bg = diagonal_gradient(INK_RAISED, INK)
        top, bottom, back, front, clasp, dot, glow_c = AMBER, EMBER, (124, 108, 176), (250, 250, 252), INK, (255, 255, 255), EMBER
    elif variant == "dark":
        bg = diagonal_gradient((24, 19, 33), (6, 6, 10))
        top, bottom, back, front, clasp, dot, glow_c = AMBER, EMBER, (104, 90, 150), (236, 236, 240), (12, 11, 18), (255, 255, 255), EMBER
    else:  # tinted: grayscale on black; iOS applies the tint by luminance
        bg = Image.new("RGB", (W, W), (0, 0, 0))
        top, bottom, back, front, clasp, dot, glow_c = (245, 245, 245), (185, 185, 185), (80, 80, 80), (140, 140, 140), (0, 0, 0), (255, 255, 255), (90, 90, 90)

    img = bg.copy()
    card(img, BACK_CARD, BACK_ANGLE, back, lerp(back, (0, 0, 0), 0.25))
    card(img, FRONT_CARD, FRONT_ANGLE, front, lerp(front, bottom, 0.9))

    body = mask_rect(BODY, BODY_RADIUS)
    glow = body.filter(ImageFilter.GaussianBlur(W * 0.05)).point(lambda v: int(v * 0.5))
    img.paste(Image.new("RGB", (W, W), glow_c), (0, int(W * 0.02)), glow)
    img.paste(vertical_gradient(top, bottom, BODY[1], BODY[3]), (0, 0), body)

    d = ImageDraw.Draw(img)
    inset = BODY_RADIUS * 0.7
    d.line([((BODY[0] + inset) * W, SEAM_Y * W), ((BODY[2] - inset) * W, SEAM_Y * W)],
           fill=lerp(top, (255, 255, 255), 0.45), width=int(0.012 * W))

    img.paste(Image.new("RGB", (W, W), clasp), (0, 0), mask_rect(CLASP, (CLASP[3] - CLASP[1]) / 2))
    cx, cy, r = DOT[0] * W, DOT[1] * W, DOT[2] * W
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=dot)
    return img.resize((S, S), Image.LANCZOS)


if __name__ == "__main__":
    out = sys.argv[1]
    # File names match AppIcon.appiconset/Contents.json.
    names = {"default": "AppIcon.png", "dark": "AppIcon-Dark.png", "tinted": "AppIcon-Tinted.png"}
    for variant, name in names.items():
        render(variant).save(f"{out}/{name}")
    print("ok")
