#!/usr/bin/env python3
"""Generates Double Bubble's app icon into the asset catalogue.

    python3 Scripts/make_app_icon.py

Drawn rather than hand-painted so the geometry stays reproducible: the shapes
are defined once here and every size is rendered from the same numbers.

House style is ConstantaAI's — flat terracotta marks on cream, no gradients.
The product idea is two instances of one app, so the mark is two circles that
just touch; the keyline between them is what keeps them readable as two at
16pt, where tone alone blurs into one blob.

Two themes are rendered. The dark one is not the light one with an inverted
background: it keeps the *relationships* that make the mark legible. The gap
between the two discs is held at the same 43 points of luma, which is what
separates them at small sizes, and the weaker disc keeps the same ~80 points
of contrast against its tile that the lighter disc has on cream. Simply
darkening the plate under the existing clays would have collapsed the deeper
disc into the background.

Requires Pillow (`pip3 install Pillow`) and macOS `iconutil`.
"""

from PIL import Image, ImageDraw, ImageFilter
import json
import math
import os
import subprocess
import sys
import tempfile

# ConstantaAI palette, sampled from the publisher's mark.
CREAM = (226, 221, 205)
CLAY = (193, 118, 87)
CLAY_DEEP = (142, 78, 51)

# Dark counterparts. INK is a warm near-black rather than a neutral one — a
# grey plate under terracotta reads as a different brand. The clays are lifted
# rather than reused: see the module docstring for the luma the pair holds to.
INK = (45, 37, 33)
CLAY_LIT = (216, 146, 112)
CLAY_MID = (176, 101, 72)


class Theme:
    """A plate colour and the two discs drawn on it. The keyline is always the
    plate's own colour, so it reads as a gap rather than as a third mark."""

    def __init__(self, name, plate, near, far):
        self.name = name
        self.plate = plate
        self.near = near      # left disc, the lighter of the two
        self.far = far        # right disc, laid over the keyline


LIGHT = Theme("light", CREAM, CLAY, CLAY_DEEP)
DARK = Theme("dark", INK, CLAY_LIT, CLAY_MID)

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


def render(px, theme=LIGHT):
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
    ImageDraw.Draw(plate).polygon(outline, fill=theme.plate + (255,))
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

    disc((cx - gap, cy), r, theme.near)
    disc((cx + gap, cy), r + keyline, theme.plate)   # separates the two at 16pt
    disc((cx + gap, cy), r, theme.far)

    return img.resize((px, px), Image.LANCZOS)


def filename(points, scale):
    suffix = "" if scale == 1 else f"@{scale}x"
    return f"icon_{points}x{points}{suffix}.png"


def contents_json():
    """Written here rather than left to Xcode, so the catalogue can never drift
    from the files this script actually produced.

    Light only, and not for want of trying: a `.appiconset` has no slot for a
    dark macOS app icon. Adding `appearances: luminosity/dark` entries compiles
    without failing, but `actool` reports the dark images as "unassigned
    children" and drops them — `assetutil` on the built Assets.car then shows
    every AppIcon entry with no appearance at all. Dark app icons on current
    macOS come from Icon Composer's `.icon` format instead, which is why the
    dark art below is rendered to Scripts/ as design source rather than here.
    """
    images = [
        {
            "filename": filename(points, scale),
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{points}x{points}",
        }
        for points, scale in SIZES
    ]
    return json.dumps(
        {"images": images, "info": {"author": "xcode", "version": 1}}, indent=2
    ) + "\n"


def write_iconset(directory, theme):
    os.makedirs(directory, exist_ok=True)
    for points, scale in SIZES:
        render(points * scale, theme).save(
            os.path.join(directory, filename(points, scale))
        )


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "DoubleBubble/Assets.xcassets/AppIcon.appiconset")
    if not os.path.isdir(out):
        sys.exit(f"asset catalogue not found: {out}")

    write_iconset(out, LIGHT)
    with open(os.path.join(out, "Contents.json"), "w") as fh:
        fh.write(contents_json())

    # The dark mark as loose PNGs, kept as design source: what Icon Composer
    # would want as layers, and usable on any dark page.
    dark_dir = os.path.join(root, "Scripts", "AppIcon-dark")
    write_iconset(dark_dir, DARK)

    # The dark .icns ships inside the app: DockIcon swaps to it at runtime.
    # .icns rather than an imageset because it carries the whole size ladder,
    # each size rendered from the geometry rather than downsampled from 1024 —
    # which is the difference that keeps the keyline crisp in the Dock.
    icns_targets = (
        (LIGHT, os.path.join(root, "Scripts", "AppIcon.icns")),
        (DARK, os.path.join(root, "DoubleBubble/Resources/AppIcon-dark.icns")),
    )
    for theme, path in icns_targets:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with tempfile.TemporaryDirectory() as tmp:
            iconset = os.path.join(tmp, "AppIcon.iconset")
            os.makedirs(iconset)
            for points, scale in SIZES:
                render(points * scale, theme).save(
                    os.path.join(iconset, filename(points, scale))
                )
            subprocess.run(["iconutil", "-c", "icns", "-o", path, iconset], check=True)

    print(f"wrote {len(SIZES)} light sizes to {out}")
    print(f"wrote {len(SIZES)} dark sizes to {dark_dir}")
    print("also wrote Contents.json, Scripts/AppIcon.icns,")
    print("             DoubleBubble/Resources/AppIcon-dark.icns")


if __name__ == "__main__":
    main()
