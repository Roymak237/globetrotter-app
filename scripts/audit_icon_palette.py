"""
Report the dominant colours of the app icon and compare them with the brand
palette, so the "the icon clashes" claim is measured rather than asserted.

Decodes the PNG with zlib and the standard PNG filters. No third-party
imaging library is installed, and adding one for a one-off check is not worth
it.
"""
import struct
import zlib
from collections import Counter

PATH = "frontend/assets/icons/icon.png"

BRAND = {
    "primary #B4462A": (0xB4, 0x46, 0x2A),
    "primaryDark #7A2E19": (0x7A, 0x2E, 0x19),
    "secondary #D98E2B": (0xD9, 0x8E, 0x2B),
    "accent #E9C46A": (0xE9, 0xC4, 0x6A),
    "background #FAF5EE": (0xFA, 0xF5, 0xEE),
    "indigo #1F3A63": (0x1F, 0x3A, 0x63),
}


def read_png(path):
    data = open(path, "rb").read()
    width, height = struct.unpack(">II", data[16:24])
    depth, colour = data[24], data[25]
    if (depth, colour) != (8, 2):
        raise SystemExit(f"expected 8-bit RGB, got depth={depth} type={colour}")

    idat = b""
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        if kind == b"IDAT":
            idat += data[offset + 8:offset + 8 + length]
        offset += 12 + length

    raw = zlib.decompress(idat)
    stride = width * 3
    out = bytearray()
    previous = bytearray(stride)
    pos = 0
    for _ in range(height):
        filter_type = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        for i in range(stride):
            a = line[i - 3] if i >= 3 else 0
            b = previous[i]
            c = previous[i - 3] if i >= 3 else 0
            if filter_type == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filter_type == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filter_type == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filter_type == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out += line
        previous = line
    return width, height, bytes(out)


def distance(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def main():
    width, height, pixels = read_png(PATH)
    counts = Counter()
    for i in range(0, len(pixels), 3):
        # Quantise so near-identical shades group together.
        counts[(pixels[i] // 16 * 16,
                pixels[i + 1] // 16 * 16,
                pixels[i + 2] // 16 * 16)] += 1

    total = width * height
    print(f"{PATH}  {width}x{height}\n")
    print("dominant colours:")
    for colour, count in counts.most_common(8):
        share = 100 * count / total
        nearest, gap = min(
            ((name, distance(colour, rgb)) for name, rgb in BRAND.items()),
            key=lambda pair: pair[1])
        print(f"  #{colour[0]:02X}{colour[1]:02X}{colour[2]:02X}  "
              f"{share:5.1f}%   nearest brand colour: {nearest} "
              f"(distance {gap:.0f})")


if __name__ == "__main__":
    main()
