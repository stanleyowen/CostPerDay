"""Renders the Dayrate app icon (default, dark and tinted variants).

The mark mirrors `BrandMark` in Theme.swift: a normalised k/(t+k) hyperbola — cost per
day falling as days owned grows — stroked ember→amber, ending in a white "today" dot.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4  # supersampling factor
W = S * SS

EMBER = (255, 95, 58)
AMBER = (255, 178, 63)
INK = (22, 20, 34)
INK_RAISED = (46, 34, 66)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def curve_height(t, k=0.15, floor=0.1):
    end = k / (1 + k)
    n = (k / (t + k) - end) / (1 - end)
    return floor + (1 - floor) * n


def curve_points(rect, steps=400):
    x0, y0, x1, y1 = rect
    pts = []
    for i in range(steps + 1):
        t = i / steps
        pts.append((x0 + t * (x1 - x0), y0 + (1 - curve_height(t)) * (y1 - y0)))
    return pts


def diagonal_gradient(size, c0, c1):
    """Top-left c0 → bottom-right c1."""
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            px[x, y] = lerp(c0, c1, (x + y) / 510)
    return small.resize((size, size), Image.BICUBIC)


def horizontal_gradient(size, c0, c1, x0, x1):
    small = Image.new("RGB", (256, 1))
    px = small.load()
    for x in range(256):
        X = x / 255 * size
        t = min(1, max(0, (X - x0) / (x1 - x0)))
        px[x, 0] = lerp(c0, c1, t)
    return small.resize((size, size), Image.BICUBIC)


def stroke_mask(points, width):
    """Round-capped stroke, stamped as dense discs for a perfectly clean edge."""
    mask = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(mask)
    r = width / 2
    step = max(1.0, r / 6)
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        dist = ((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5
        n = max(1, int(dist / step))
        for i in range(n + 1):
            x = ax + (bx - ax) * i / n
            y = ay + (by - ay) * i / n
            d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return mask


def render(variant):
    # Nudged up and right so the L-shaped mass of the curve sits optically centred,
    # leaving room for the row of day dots beneath it.
    rect = (0.27 * W, 0.19 * W, 0.77 * W, 0.66 * W)
    pts = curve_points(rect)
    line_w = 0.085 * W
    dot_d = 0.13 * W

    if variant == "default":
        bg = diagonal_gradient(W, INK_RAISED, INK)
        c0, c1, glow_c, dot_c = EMBER, AMBER, EMBER, (255, 255, 255)
    elif variant == "dark":
        bg = diagonal_gradient(W, (24, 19, 33), (6, 6, 10))
        c0, c1, glow_c, dot_c = EMBER, AMBER, EMBER, (255, 255, 255)
    else:  # tinted: grayscale on black; iOS applies the tint by luminance
        bg = Image.new("RGB", (W, W), (0, 0, 0))
        c0, c1, glow_c, dot_c = (150, 150, 150), (235, 235, 235), (120, 120, 120), (255, 255, 255)

    img = bg.copy()

    # Soft glow beneath the stroke.
    glow = stroke_mask(pts, line_w * 2.2).filter(ImageFilter.GaussianBlur(W * 0.035))
    glow = glow.point(lambda v: int(v * 0.35))
    img.paste(Image.new("RGB", (W, W), glow_c), (0, 0), glow)

    # The curve itself, gradient along x.
    grad = horizontal_gradient(W, c0, c1, rect[0], rect[2])
    img.paste(grad, (0, 0), stroke_mask(pts, line_w))

    # A week of days along the bottom; the last one — today — lines up with the dot.
    days = 7
    tick_y = 0.80 * W
    tick_r = 0.026 * W
    for i in range(days):
        tx = rect[0] + (rect[2] - rect[0]) * i / (days - 1)
        shade = 0.30 if i < days - 1 else 0.0
        c = lerp(bg.getpixel((int(tx), int(tick_y))), (255, 255, 255), shade)
        d0 = ImageDraw.Draw(img)
        if i == days - 1:
            d0.ellipse((tx - tick_r, tick_y - tick_r, tx + tick_r, tick_y + tick_r), fill=c1)
        else:
            d0.ellipse((tx - tick_r, tick_y - tick_r, tx + tick_r, tick_y + tick_r), fill=c)

    # "Today" dot at the end of the curve, with a thin ink halo so it separates.
    x, y = pts[-1]
    halo = dot_d / 2 + line_w * 0.18
    d = ImageDraw.Draw(img)
    d.ellipse((x - halo, y - halo, x + halo, y + halo), fill=bg.getpixel((int(x), int(y))))
    r = dot_d / 2
    d.ellipse((x - r, y - r, x + r, y + r), fill=dot_c)

    return img.resize((S, S), Image.LANCZOS)


if __name__ == "__main__":
    out = sys.argv[1]
    for variant in ("default", "dark", "tinted"):
        render(variant).save(f"{out}/AppIcon-{variant}.png")
    print("ok")
