#!/usr/bin/env python3
"""Generates Double Bubble's app icon into the asset catalogue.

    python3 Scripts/make_app_icon.py

Drawn rather than hand-painted so the geometry stays reproducible: the shapes
are defined once here and every size is rendered from the same numbers.

House style is ConstantaAI's — flat terracotta marks on cream, no gradients.
The product idea is two instances of one app, so the mark is two circles that
just touch; the cream keyline between them is what keeps them readable as two
at 16pt, where tone alone blurs into one blob.

Requires Pillow (`pip3 install Pillow`) and macOS `iconutil`.
"""

from PIL import Image, ImageDraw, ImageFilter
import math
import os
import subprocess
import sys
import tempfile

# ConstantaAI palette, sampled from the publisher's mark.
CREAM = (226, 221, 205)
CLAY = (193, 118, 87)
CLAY_DEEP = (142, 78, 51)

SS = 4        # supersample factor; PIL has no antialiased polygon fill
BASE = 1024   # master size

# Apple's grid: the tile is 824 of a 1024 canvas. The rest is shadow room —
# measured against Notes, Music and Claude, all of which sit at exactly 824
# solid and spread to ~886 once their shadow is counted. Skipping the shadow
# is what made this icon read as smaller than its neighbours in the Dock even
# though the tile was the correct size.
TILE = 824 / 1024
SHADOW_SIGMA = 0.014      # of canvas
SHADOW_OFFSET = 0.010     # of canvas, downward
SHADOW_ALPHA = 0.30

SIZES = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2),
]


def squircle(size, n=5.0, steps=720):
    """Apple-style continuous corner as a superellipse. Circular corners read
    as visibly pinched next to real macOS icons."""
    a = size / 2.0
    pts = []
    for i in range(steps):
        t = 2.0 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        pts.append((
            a + a * math.copysign(abs(ct) ** (2.0 / n), ct),
            a + a * math.copysign(abs(st) ** (2.0 / n), st),
        ))
    return pts


def render(px):
    canvas = px * SS
    tile = canvas * TILE
    offset = (canvas - tile) / 2
    outline = [(x + offset, y + offset) for (x, y) in squircle(tile)]

    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))

    # Shadow first, so the tile lands on top of it.
    shadow_mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(shadow_mask).polygon(outline, fill=int(255 * SHADOW_ALPHA))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(canvas * SHADOW_SIGMA))
    shadow_mask = shadow_mask.transform(
        (canvas, canvas), Image.AFFINE, (1, 0, 0, 0, 1, -canvas * SHADOW_OFFSET)
    )
    img.paste(Image.new("RGBA", (canvas, canvas), (0, 0, 0, 255)), (0, 0), shadow_mask)

    plate = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    ImageDraw.Draw(plate).polygon(outline, fill=CREAM + (255,))
    img.alpha_composite(plate)

    draw = ImageDraw.Draw(img)

    r = tile * 0.235
    gap = tile * 0.160        # half the distance between centres
    keyline = tile * 0.028

    # The keyline widens the group to the right only, so geometric centring
    # leaves the pair sitting off to that side.
    cy = canvas / 2
    cx = canvas / 2 - keyline / 2

    def disc(centre, radius, colour):
        draw.ellipse(
            [centre[0] - radius, centre[1] - radius,
             centre[0] + radius, centre[1] + radius],
            fill=colour + (255,),
        )

    disc((cx - gap, cy), r, CLAY)
    disc((cx + gap, cy), r + keyline, CREAM)   # separates the two at 16pt
    disc((cx + gap, cy), r, CLAY_DEEP)

    return img.resize((px, px), Image.LANCZOS)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "DoubleBubble/Assets.xcassets/AppIcon.appiconset")
    if not os.path.isdir(out):
        sys.exit(f"asset catalogue not found: {out}")

    for points, scale in SIZES:
        px = points * scale
        suffix = "" if scale == 1 else f"@{scale}x"
        name = f"icon_{points}x{points}{suffix}.png"
        render(px).save(os.path.join(out, name))

    # A master .icns is handy for previews and store artwork.
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        for points, scale in SIZES:
            suffix = "" if scale == 1 else f"@{scale}x"
            render(points * scale).save(
                os.path.join(iconset, f"icon_{points}x{points}{suffix}.png")
            )
        icns = os.path.join(root, "Scripts", "AppIcon.icns")
        subprocess.run(["iconutil", "-c", "icns", "-o", icns, iconset], check=True)

    print(f"wrote {len(SIZES)} sizes to {out}")
    print("also wrote Scripts/AppIcon.icns")


if __name__ == "__main__":
    main()
