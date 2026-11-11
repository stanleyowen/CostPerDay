"""Builds the README images from simulator screenshots.

Screenshots are taken from a simulator seeded with `-seedSampleData` (never real
data), e.g.:
    xcrun simctl launch <sim> com.stanley.Dayrate -seedSampleData -skipOnboarding -initialTab reports
    xcrun simctl io <sim> screenshot shots/reports.png

Usage: python3 Design/make_readme_images.py <shots_dir> Design/screenshots
"""
import sys
import pathlib
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

INK = (22, 20, 34)
INK_RAISED = (46, 34, 66)
EMBER = (255, 95, 58)
AMBER = (255, 178, 63)


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), radius=radius, fill=255)
    out = Image.new("RGBA", img.size)
    out.paste(img, (0, 0), mask)
    return out


def phone(name, width):
    shot = Image.open(SRC / f"{name}.png").convert("RGB")
    h = int(shot.height * width / shot.width)
    return rounded(shot.resize((width, h), Image.LANCZOS), int(width * 0.13))


def font(size, bold=True):
    for path in ["/System/Library/Fonts/SFNSRounded.ttf", "/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"]:
        try:
            f = ImageFont.truetype(path, size)
        except OSError:
            continue
        try:  # SF is a variable font; pick the weight explicitly.
            f.set_variation_by_name("Bold" if bold else "Regular")
        except Exception:
            pass
        return f
    return ImageFont.load_default()


def gradient(size, c0, c1):
    w, h = size
    small = Image.new("RGB", (64, 64))
    p = small.load()
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126
            p[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
    return small.resize(size, Image.BICUBIC)


# Individual screenshots, README-sized.
for name in ["home", "home-2", "transactions", "composer", "reports", "reports-2", "reports-3", "items", "onboarding", "settings"]:
    if (SRC / f"{name}.png").exists():
        phone(name, 390).save(OUT / f"{name}.png", optimize=True)

# Hero banner: mark + name on the left, three phones fanned on the right.
W, H = 2400, 1200
banner = gradient((W, H), INK_RAISED, INK).convert("RGBA")
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse((1250, 150, 2350, 1250), fill=(*EMBER, 90))
banner.alpha_composite(glow.filter(ImageFilter.GaussianBlur(160)))

icon = Image.open(pathlib.Path(__file__).parent.parent / "Wallet/Assets.xcassets/AppIcon.appiconset/AppIcon.png").convert("RGB")
banner.alpha_composite(rounded(icon.resize((220, 220), Image.LANCZOS), 50), (140, 300))
d = ImageDraw.Draw(banner)
d.text((140, 560), "Wallet", font=font(150), fill=(255, 255, 255))
d.text((146, 740), "Every transaction, and everything it bought.", font=font(46, False), fill=(255, 255, 255, 190))
d.text((146, 810), "Track · Report · Know what your things cost per day", font=font(36, False), fill=(*AMBER, 255))

for name, x, y, angle in [("reports", 1180, 210, 6), ("transactions", 1880, 210, -6), ("home", 1500, 120, 0)]:
    p = phone(name, 470)
    shadow = Image.new("RGBA", (p.width + 120, p.height + 120), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((60, 70, 60 + p.width, 70 + p.height), radius=60, fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    framed = Image.new("RGBA", shadow.size, (0, 0, 0, 0))
    framed.alpha_composite(shadow)
    framed.alpha_composite(p, (60, 60))
    framed = framed.rotate(angle, resample=Image.BICUBIC, expand=True)
    banner.alpha_composite(framed, (x - 60, y - 60))

banner.convert("RGB").resize((1600, 800), Image.LANCZOS).save(OUT / "hero.png", optimize=True)
print("ok", sorted(p.name for p in OUT.iterdir()))
