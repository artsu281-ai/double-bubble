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

from PIL import Image, ImageDraw, ImageFilter, ImageChops
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

    def __init__(self, name, plate, near, far, *,
                 sheen, floor, cast, spec, rim, foot):
        self.name = name
        self.plate = plate
        self.near = near      # left disc, the lighter of the two
        self.far = far        # right disc, laid over the keyline
        # Glass strengths, per theme, because the same light behaves
        # differently on cream and on near-black: a highlight that is barely
        # there on the light plate is the whole effect on the dark one, and a
        # sheen strong enough for cream washes the dark plate out to grey.
        self.sheen = sheen    # light gathering at the top of the plate
        self.floor = floor    # its absence at the bottom
        self.cast = cast      # the mark's shadow onto the plate
        self.spec = spec      # highlight on each disc
        self.rim = rim        # lit top lip
        self.foot = foot      # shaded bottom lip


LIGHT = Theme("light", CREAM, CLAY, CLAY_DEEP,
              sheen=0.10, floor=0.07, cast=0.20, spec=0.15, rim=0.34, foot=0.16)
DARK = Theme("dark", INK, CLAY_LIT, CLAY_MID,
             sheen=0.095, floor=0.10, cast=0.26, spec=0.20, rim=0.55, foot=0.30)

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

# How much Liquid Glass the mark carries, 0 being the flat drawing. Apple's own
# icons are restrained about this, and so is the number: past ~0.8 the top of
# the plate lightens enough to read as plastic rather than glass. The effects
# are all proportional to the tile, so they fade out on their own by 16pt and
# leave the flat mark behind — which is exactly where legibility matters most.
GLASS = 0.65

# Highlights are warm, not white. Pure white over terracotta desaturates it
# toward grey and the icon stops looking like the same brand.
SPARK = (255, 247, 238)

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


# MARK: glass helpers
#
# Each returns or composites one physical effect, so the stack in render() reads
# as a description of the material rather than a pile of blurs.


def _mask(canvas):
    return Image.new("L", (canvas, canvas), 0)


def _shift(mask, dy):
    return mask.transform(mask.size, Image.AFFINE, (1, 0, 0, 0, 1, -dy))


def _ramp(canvas, colour, top_alpha, bottom_alpha, y0, y1):
    """A vertical alpha ramp — the slab catching light along its height."""
    g = _mask(canvas)
    d = ImageDraw.Draw(g)
    span = max(1.0, y1 - y0)
    for y in range(canvas):
        t = min(1.0, max(0.0, (y - y0) / span))
        d.line([(0, y), (canvas, y)],
               fill=int(255 * (top_alpha + (bottom_alpha - top_alpha) * t)))
    layer = Image.new("RGBA", (canvas, canvas), colour + (255,))
    layer.putalpha(g)
    return layer


def _clipped(layer, mask):
    out = layer.copy()
    out.putalpha(ImageChops.multiply(out.getchannel("A"), mask))
    return out


def _tint(img, mask, colour, alpha):
    """Paint `colour` through `mask` at `alpha`, in place."""
    if alpha <= 0:
        return
    faded = mask.point(lambda v: int(v * alpha))
    img.paste(Image.new("RGBA", img.size, colour + (255,)), (0, 0), faded)


def _edge(mask, thickness, blur, downward):
    """The lit top lip or the shaded foot: the sliver the slab's own thickness
    leaves when the shape is slid against itself."""
    other = _shift(mask, thickness if downward else -thickness)
    band = ImageChops.subtract(mask, other)
    return ImageChops.multiply(band.filter(ImageFilter.GaussianBlur(blur)), mask)


def render(px, theme=LIGHT, glass=GLASS):
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

    plate_mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(plate_mask).polygon(outline, fill=255)

    plate = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    ImageDraw.Draw(plate).polygon(outline, fill=theme.plate + (255,))
    img.alpha_composite(plate)

    # Light pools at the head of the slab and drains toward its foot.
    if glass > 0:
        img.alpha_composite(_clipped(
            _ramp(canvas, SPARK, theme.sheen * glass, 0.0,
                  offset, offset + tile * 0.62), plate_mask))
        img.alpha_composite(_clipped(
            _ramp(canvas, (0, 0, 0), 0.0, theme.floor * glass,
                  offset + tile * 0.45, offset + tile), plate_mask))

    r = tile * 0.235
    gap = tile * 0.160        # half the distance between centres
    keyline = tile * 0.028

    # The keyline widens the group to the right only, so geometric centring
    # leaves the pair sitting off to that side.
    cy = canvas / 2
    cx = canvas / 2 - keyline / 2
    near_c, far_c = (cx - gap, cy), (cx + gap, cy)

    def circle(centre, radius):
        m = Image.new("L", (canvas, canvas), 0)
        ImageDraw.Draw(m).ellipse(
            [centre[0] - radius, centre[1] - radius,
             centre[0] + radius, centre[1] + radius], fill=255)
        return m

    # What is actually visible of each disc: the near one is bitten into by the
    # keyline, and the effects have to follow the shape the eye sees.
    near_m = ImageChops.subtract(circle(near_c, r), circle(far_c, r + keyline))
    far_m = circle(far_c, r)

    # The mark sits above the slab rather than in it, so it casts onto it.
    if glass > 0:
        cast = ImageChops.lighter(near_m, far_m)
        cast = cast.filter(ImageFilter.GaussianBlur(tile * 0.030))
        cast = _shift(cast, -tile * 0.018)
        _tint(img, ImageChops.multiply(cast, plate_mask),
              (0, 0, 0), theme.cast * glass)

    draw = ImageDraw.Draw(img)

    def disc(centre, radius, colour):
        draw.ellipse(
            [centre[0] - radius, centre[1] - radius,
             centre[0] + radius, centre[1] + radius],
            fill=colour + (255,),
        )

    disc(near_c, r, theme.near)
    disc(far_c, r + keyline, theme.plate)   # separates the two at 16pt
    disc(far_c, r, theme.far)

    if glass > 0:
        # A specular on each disc, up and to the left — the same direction the
        # sheen comes from, or the two light sources fight each other.
        for centre, shape in ((near_c, near_m), (far_c, far_m)):
            spec = Image.new("L", (canvas, canvas), 0)
            ImageDraw.Draw(spec).ellipse(
                [centre[0] - r * 0.78, centre[1] - r * 1.02,
                 centre[0] + r * 0.42, centre[1] - r * 0.10], fill=255)
            spec = spec.filter(ImageFilter.GaussianBlur(r * 0.22))
            _tint(img, ImageChops.multiply(spec, shape), SPARK,
                  theme.spec * glass)

        # The lit lip and the shaded foot. This pair is what actually says
        # "glass" rather than "gradient": an edge with a thickness to it.
        t = max(1.0, tile * 0.010)
        _tint(img, _edge(plate_mask, t, t * 0.55, downward=True),
              SPARK, theme.rim * glass)
        _tint(img, _edge(plate_mask, t, t * 0.55, downward=False),
              (0, 0, 0), theme.foot * glass)

    return img.resize((px, px), Image.LANCZOS)


def filename(points, scale):
    suffix = "" if scale == 1 else f"@{scale}x"
    return f"icon_{points}x{points}{suffix}.png"


# What ships, and under which name. The bundle's own icon is the default pick;
# the rest are loaded at runtime by DockIcon when the user chooses otherwise.
DEFAULT_VARIANT = "light-glass"
VARIANTS = [
    ("light-flat", LIGHT, 0.0),
    ("light-glass", LIGHT, GLASS),
    ("dark-flat", DARK, 0.0),
    ("dark-glass", DARK, GLASS),
]


def contents_json():
    """Written here rather than left to Xcode, so the catalogue can never drift
    from the files this script actually produced.

    One variant only, and not for want of trying: a `.appiconset` has no slot
    for a dark macOS app icon. Adding `appearances: luminosity/dark` entries
    compiles without failing, but `actool` reports the dark images as
    "unassigned children" and drops them — `assetutil` on the built Assets.car
    then shows every AppIcon entry with no appearance at all. So the catalogue
    carries the default and DockIcon swaps the rest in at runtime.
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


def write_icns(path, theme, glass):
    """.icns rather than an imageset because it carries the whole size ladder
    with every size drawn from the geometry, instead of the Dock downsampling
    one 1024 master — which is what keeps the keyline crisp at Dock sizes."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        for points, scale in SIZES:
            render(points * scale, theme, glass).save(
                os.path.join(iconset, filename(points, scale))
            )
        subprocess.run(["iconutil", "-c", "icns", "-o", path, iconset], check=True)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "DoubleBubble/Assets.xcassets/AppIcon.appiconset")
    if not os.path.isdir(out):
        sys.exit(f"asset catalogue not found: {out}")

    resources = os.path.join(root, "DoubleBubble/Resources")
    for name, theme, glass in VARIANTS:
        write_icns(os.path.join(resources, f"AppIcon-{name}.icns"), theme, glass)
        if name == DEFAULT_VARIANT:
            for points, scale in SIZES:
                render(points * scale, theme, glass).save(
                    os.path.join(out, filename(points, scale))
                )

    with open(os.path.join(out, "Contents.json"), "w") as fh:
        fh.write(contents_json())

    # Master for previews and store artwork, matching the bundle's own icon.
    default = next(v for v in VARIANTS if v[0] == DEFAULT_VARIANT)
    write_icns(os.path.join(root, "Scripts", "AppIcon.icns"), default[1], default[2])

    print(f"wrote {len(VARIANTS)} variants to {resources}")
    print(f"catalogue + Scripts/AppIcon.icns follow '{DEFAULT_VARIANT}'")


if __name__ == "__main__":
    main()
