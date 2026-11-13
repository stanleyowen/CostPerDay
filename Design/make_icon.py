"""Renders the Wallet app icon (default, dark and tinted variants).

The mark mirrors `BrandMark` in Theme.swift: a classic brown leather bifold with
saddle stitching and a snap strap, three cards (coral, gold, white) fanned out of
the top, on warm cream. Geometry is in unit coordinates shared with
`BrandMark.Geometry`.

Usage: python3 Design/make_icon.py Wallet/Assets.xcassets/AppIcon.appiconset
"""
import math
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024
SS = 4  # supersampling factor
W = S * SS

# Shared with `BrandMark.Geometry` in Theme.swift. Rects are (x0, y0, x1, y1);
# angles are degrees, clockwise positive, about the card's centre.
CARDS = [  # back to front
    ((0.23, 0.17, 0.67, 0.45), -14),
    ((0.29, 0.19, 0.73, 0.47), -2),
    ((0.34, 0.23, 0.78, 0.51), 9),
]
CARD_RADIUS = 0.035
CARD_STRIPE = (0.22, 0.38)              # y band of the magnetic stripe, as a fraction of card height
BODY = (0.16, 0.38, 0.84, 0.80)
BODY_RADIUS = 0.09
BODY_STITCH = (0.19, 0.41, 0.81, 0.77)  # its right edge is left out: the strap covers it
BODY_STITCH_RADIUS = 0.07
STRAP = (0.60, 0.50, 0.90, 0.68)        # a capsule
STRAP_STITCH = (0.625, 0.522, 0.875, 0.658)
STRAP_STITCH_RADIUS = 0.065
SNAP = (0.755, 0.59, 0.042)             # centre x, centre y, radius
SNAP_FACE = (0.755, 0.585, 0.03)
BG_CENTER, BG_RADIUS = (0.5, 0.35), 0.9  # radial background
# Stitch dashes: (line width, dash length, gap), shared with `BrandMark.Stitches`.
BODY_DASH = (0.008, 0.028, 0.02)
STRAP_DASH = (0.006, 0.02, 0.016)

PALETTES = {
    "default": dict(
        bg=((255, 244, 226), (246, 222, 186)),
        cards=[((255, 120, 92), (210, 80, 60)), ((255, 206, 84), (220, 160, 40)), ((250, 250, 252), (40, 168, 160))],
        body=((178, 110, 62), (130, 74, 38)), stitch=(236, 196, 150),
        strap=((150, 88, 46), (112, 62, 30)), strap_stitch=(226, 184, 138),
        snap=((210, 170, 90), (244, 214, 140)),
        body_shadow=((90, 50, 20), 0.35), strap_shadow=((60, 30, 10), 0.35), card_shadow=0.3,
    ),
    "dark": dict(
        bg=((52, 38, 30), (18, 14, 12)),
        cards=[((240, 108, 82), (196, 72, 54)), ((242, 192, 76), (206, 148, 36)), ((236, 236, 240), (36, 156, 148))],
        body=((168, 102, 56), (120, 68, 34)), stitch=(226, 186, 140),
        strap=((140, 82, 42), (102, 56, 26)), strap_stitch=(214, 172, 128),
        snap=((200, 160, 84), (236, 204, 132)),
        body_shadow=((0, 0, 0), 0.5), strap_shadow=((0, 0, 0), 0.45), card_shadow=0.45,
    ),
    # Grayscale on black: iOS applies the tint by luminance.
    "tinted": dict(
        bg=((0, 0, 0), (0, 0, 0)),
        cards=[((96, 96, 96), (64, 64, 64)), ((150, 150, 150), (104, 104, 104)), ((235, 235, 235), (150, 150, 150))],
        body=((210, 210, 210), (165, 165, 165)), stitch=(90, 90, 90),
        strap=((130, 130, 130), (105, 105, 105)), strap_stitch=(70, 70, 70),
        snap=((200, 200, 200), (255, 255, 255)),
        body_shadow=((0, 0, 0), 0.6), strap_shadow=((0, 0, 0), 0.5), card_shadow=0.5,
    ),
}


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def radial_gradient(c_in, c_out):
    small = Image.new("RGB", (256, 256))
    p = small.load()
    for y in range(256):
        for x in range(256):
            d = math.hypot(x / 255 - BG_CENTER[0], y / 255 - BG_CENTER[1]) / BG_RADIUS
            p[x, y] = lerp(c_in, c_out, min(1, d))
    return small.resize((W, W), Image.BICUBIC)


def vertical_gradient(c0, c1, y0, y1):
    small = Image.new("RGB", (1, 256))
    p = small.load()
    for y in range(256):
        p[0, y] = lerp(c0, c1, min(1, max(0, (y / 255 - y0) / (y1 - y0))))
    return small.resize((W, W), Image.BICUBIC)


def mask_rect(rect, radius, angle=0):
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle(tuple(v * W for v in rect), radius=radius * W, fill=255)
    if angle:
        mask = mask.rotate(-angle, resample=Image.BICUBIC, center=((rect[0] + rect[2]) / 2 * W, (rect[1] + rect[3]) / 2 * W))
    return mask


def mask_circle(cx, cy, r):
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).ellipse(((cx - r) * W, (cy - r) * W, (cx + r) * W, (cy + r) * W), fill=255)
    return mask


def fill(img, mask, paint):
    img.paste(paint if isinstance(paint, Image.Image) else Image.new("RGB", (W, W), paint), (0, 0), mask)


def shadow(img, mask, dy, blur, color, alpha):
    s = mask.filter(ImageFilter.GaussianBlur(W * blur)).point(lambda v: int(v * alpha))
    img.paste(Image.new("RGB", (W, W), color), (0, int(W * dy)), s)


def stitch_dashes(rect, radius, dash, gap, skip=()):
    """Dash segments along a rounded rect's straight edges (top, right, bottom, left).

    Each edge holds a whole number of dash+gap steps, stretched to fit, with half a gap
    at each end. `BrandMark.Stitches` lays them out the same way.
    """
    x0, y0, x1, y1 = rect
    edges = [((x0 + radius, y0), (x1 - radius, y0)), ((x1, y0 + radius), (x1, y1 - radius)),
             ((x1 - radius, y1), (x0 + radius, y1)), ((x0, y1 - radius), (x0, y0 + radius))]
    out = []
    for i, ((ax, ay), (bx, by)) in enumerate(edges):
        length = math.hypot(bx - ax, by - ay)
        n = int(length / (dash + gap))
        if i in skip or n <= 0:
            continue
        step = length / n
        for k in range(n):
            t0, t1 = (k * step + gap / 2) / length, (k * step + gap / 2 + dash) / length
            out.append(((ax + (bx - ax) * t0, ay + (by - ay) * t0), (ax + (bx - ax) * t1, ay + (by - ay) * t1)))
    return out


def draw_stitches(img, dashes, width, color):
    d = ImageDraw.Draw(img)
    for (ax, ay), (bx, by) in dashes:
        d.line([(ax * W, ay * W), (bx * W, by * W)], fill=color, width=int(width * W))


def card(img, rect, angle, color, stripe_color, shadow_alpha):
    shape = mask_rect(rect, CARD_RADIUS, angle)
    shadow(img, shape, 0.008, 0.012, (0, 0, 0), shadow_alpha)
    fill(img, shape, color)
    x0, y0, x1, y1 = rect
    h = y1 - y0
    stripe = Image.new("L", (W, W), 0)
    ImageDraw.Draw(stripe).rectangle((x0 * W, (y0 + h * CARD_STRIPE[0]) * W, x1 * W, (y0 + h * CARD_STRIPE[1]) * W), fill=255)
    stripe = stripe.rotate(-angle, resample=Image.BICUBIC, center=((x0 + x1) / 2 * W, (y0 + y1) / 2 * W))
    fill(img, ImageChops.multiply(stripe, shape), stripe_color)


def render(variant):
    p = PALETTES[variant]
    img = radial_gradient(*p["bg"])

    for (rect, angle), (color, stripe) in zip(CARDS, p["cards"]):
        card(img, rect, angle, color, stripe, p["card_shadow"])

    body = mask_rect(BODY, BODY_RADIUS)
    shadow(img, body, 0.025, 0.035, *p["body_shadow"])
    fill(img, body, vertical_gradient(*p["body"], BODY[1], BODY[3]))
    draw_stitches(img, stitch_dashes(BODY_STITCH, BODY_STITCH_RADIUS, *BODY_DASH[1:], skip=(1,)), BODY_DASH[0], p["stitch"])

    strap = mask_rect(STRAP, (STRAP[3] - STRAP[1]) / 2)
    shadow(img, strap, 0.01, 0.012, *p["strap_shadow"])
    fill(img, strap, vertical_gradient(*p["strap"], STRAP[1], STRAP[3]))
    draw_stitches(img, stitch_dashes(STRAP_STITCH, STRAP_STITCH_RADIUS, *STRAP_DASH[1:]), STRAP_DASH[0], p["strap_stitch"])

    fill(img, mask_circle(*SNAP), p["snap"][0])
    fill(img, mask_circle(*SNAP_FACE), p["snap"][1])
    return img.resize((S, S), Image.LANCZOS)


if __name__ == "__main__":
    out = sys.argv[1]
    # File names match AppIcon.appiconset/Contents.json.
    names = {"default": "AppIcon.png", "dark": "AppIcon-Dark.png", "tinted": "AppIcon-Tinted.png"}
    for variant, name in names.items():
        render(variant).save(f"{out}/{name}")
    print("ok")
