"""
scripts/generate_app_icon.py

Draws the app icon in the Sahel brand palette and writes every size the three
platforms need.

Why
---
The shipped icon is a neon pink and cyan globe on near-black. Measured with
scripts/_icon_palette.py, about 58 percent of its pixels sit under luminance
32, and its brightest colours are #F070A0 and #30A0F0. The app around it is
terracotta #B4462A on warm sand #FAF5EE. Nothing in the icon is within reach
of the palette, which is why it looks like a different product's icon on the
home screen next to the app's own splash.

The design
----------
A compass rose over a warm sand disc, in the same terracotta and ochre the app
already uses. A compass suits a travel app, reads at 16 px where a detailed
globe turns to mush, and is simple enough to draw correctly in code rather
than pulling in an asset nobody can regenerate.

Everything is drawn at 4x and downsampled, which is the cheap way to get
smooth edges without writing an antialiasing routine.

Run from the repository root:
    .venv/Scripts/python.exe scripts/generate_app_icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

# Straight from lib/utils/theme.dart.
SAND = (0xFA, 0xF5, 0xEE)
TERRACOTTA = (0xB4, 0x46, 0x2A)
TERRACOTTA_DARK = (0x7A, 0x2E, 0x19)
OCHRE = (0xD9, 0x8E, 0x2B)
GOLD = (0xE9, 0xC4, 0x6A)
INK = (0x2C, 0x1A, 0x10)

SUPERSAMPLE = 4


def draw_icon(size, *, background=True, inset=0.0):
    """Draw the icon at `size` pixels square.

    `background` off gives the transparent foreground layer Android's adaptive
    icons expect. `inset` shrinks the artwork, which that same layer needs
    because the launcher crops it to whatever mask the device uses.
    """
    scale = size * SUPERSAMPLE
    image = Image.new("RGBA", (scale, scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    centre = scale / 2
    # Full-bleed disc normally; pulled in for the adaptive foreground so the
    # launcher's mask cannot clip the compass points off.
    radius = scale / 2 * (1 - inset)

    if background:
        draw.ellipse(
            [centre - radius, centre - radius, centre + radius, centre + radius],
            fill=SAND)
        draw.ellipse(
            [centre - radius, centre - radius, centre + radius, centre + radius],
            outline=TERRACOTTA, width=max(2, int(scale * 0.018)))

    ring = radius * 0.80
    draw.ellipse([centre - ring, centre - ring, centre + ring, centre + ring],
                 outline=OCHRE, width=max(2, int(scale * 0.012)))

    # Tick marks around the bezel, skipping the four where the compass points
    # already are.
    import math
    tick_outer, tick_inner = ring * 0.99, ring * 0.86
    for step in range(16):
        if step % 4 == 0:
            continue
        angle = math.radians(step * 22.5 - 90)
        draw.line(
            [centre + tick_inner * math.cos(angle),
             centre + tick_inner * math.sin(angle),
             centre + tick_outer * math.cos(angle),
             centre + tick_outer * math.sin(angle)],
            fill=GOLD, width=max(2, int(scale * 0.010)))

    # The compass rose. Each arm is a kite: tip, two shoulders, centre. The
    # clockwise face of every arm is drawn darker so the star reads as folded
    # paper rather than a flat cross.
    long_arm, short_arm = ring * 0.92, ring * 0.44
    shoulder = ring * 0.17
    for index, (tip, side) in enumerate([
        ((0, -long_arm), (shoulder, 0)),      # north
        ((long_arm, 0), (0, shoulder)),       # east
        ((0, long_arm), (-shoulder, 0)),      # south
        ((-long_arm, 0), (0, -shoulder)),     # west
    ]):
        light = TERRACOTTA if index % 2 == 0 else TERRACOTTA_DARK
        dark = TERRACOTTA_DARK if index % 2 == 0 else TERRACOTTA
        draw.polygon([(centre + tip[0], centre + tip[1]),
                      (centre + side[0], centre + side[1]),
                      (centre, centre)], fill=light)
        draw.polygon([(centre + tip[0], centre + tip[1]),
                      (centre - side[0], centre - side[1]),
                      (centre, centre)], fill=dark)

    # The diagonal arms are shorter, so the cardinal points stay dominant.
    diagonal = short_arm
    for dx, dy in [(1, -1), (1, 1), (-1, 1), (-1, -1)]:
        tip = (dx * diagonal * 0.78, dy * diagonal * 0.78)
        draw.polygon([(centre + tip[0], centre + tip[1]),
                      (centre + shoulder * 0.55, centre - shoulder * 0.55),
                      (centre, centre),
                      (centre - shoulder * 0.55, centre + shoulder * 0.55)],
                     fill=OCHRE)

    hub = ring * 0.10
    draw.ellipse([centre - hub, centre - hub, centre + hub, centre + hub],
                 fill=SAND, outline=INK, width=max(1, int(scale * 0.006)))

    return image.resize((size, size), Image.LANCZOS)


def flatten(image, colour):
    """Composite onto an opaque background, for formats that reject alpha."""
    base = Image.new("RGB", image.size, colour)
    base.paste(image, mask=image.split()[3])
    return base


def main():
    root = Path(".")
    written = []

    def save(path, image):
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path)
        written.append(str(path))

    # The master, kept so this can be regenerated or handed to a designer.
    save(root / "frontend/assets/icons/icon.png",
         flatten(draw_icon(1024), SAND))

    # Web. The favicon is tiny, so it is drawn at its own size rather than
    # downsampled from the big one, which would smear the compass.
    for size in (192, 512):
        icon = flatten(draw_icon(size), SAND)
        save(root / f"frontend/web/icons/Icon-{size}.png", icon)
        # Maskable icons get cropped to a circle by some launchers, so the
        # artwork is inset to survive it.
        save(root / f"frontend/web/icons/Icon-maskable-{size}.png",
             flatten(draw_icon(size, inset=0.10), SAND))
    save(root / "frontend/web/favicon.png", flatten(draw_icon(16), SAND))

    # Android launcher icons.
    for folder, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                         ("xxhdpi", 144), ("xxxhdpi", 192)]:
        save(root / f"frontend/android/app/src/main/res/mipmap-{folder}/"
                    "ic_launcher.png",
             flatten(draw_icon(size), SAND))

    # Adaptive foreground: transparent, inset, no disc. Android composites it
    # over the colour in ic_launcher_background. The 25 percent inset is the
    # safe zone the launcher mask can crop into; ic_launcher.xml deliberately
    # does not inset again on top of this.
    for folder, size in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                         ("xxhdpi", 324), ("xxxhdpi", 432)]:
        save(root / f"frontend/android/app/src/main/res/drawable-{folder}/"
                    "ic_launcher_foreground.png",
             draw_icon(size, background=False, inset=0.25))

    # iOS rejects alpha in app icons, so these are flattened.
    ios = root / "frontend/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, size in [
        ("Icon-App-20x20@1x", 20), ("Icon-App-20x20@2x", 40),
        ("Icon-App-20x20@3x", 60), ("Icon-App-29x29@1x", 29),
        ("Icon-App-29x29@2x", 58), ("Icon-App-29x29@3x", 87),
        ("Icon-App-40x40@1x", 40), ("Icon-App-40x40@2x", 80),
        ("Icon-App-40x40@3x", 120), ("Icon-App-50x50@1x", 50),
        ("Icon-App-50x50@2x", 100), ("Icon-App-57x57@1x", 57),
        ("Icon-App-57x57@2x", 114), ("Icon-App-60x60@2x", 120),
        ("Icon-App-60x60@3x", 180), ("Icon-App-72x72@1x", 72),
        ("Icon-App-72x72@2x", 144), ("Icon-App-76x76@1x", 76),
        ("Icon-App-76x76@2x", 152), ("Icon-App-83.5x83.5@2x", 167),
        ("Icon-App-1024x1024@1x", 1024),
    ]:
        save(ios / f"{name}.png", flatten(draw_icon(size), SAND))

    print(f"wrote {len(written)} files")
    for path in written:
        print(f"  {path}")


if __name__ == "__main__":
    main()
