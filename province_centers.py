#!/usr/bin/python

from PIL import Image
import json
import struct
import argparse

from collections import defaultdict
import statistics


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=str)
    parser.add_argument("--outpath", default="province_centers.json", type=str)
    args = parser.parse_args()

    image = Image.open(args.outpath).convert("RGB")
    pixels = image.load()
    if not pixels:
        return

    width, height = image.size

    BLACK = (0, 0, 0)

    color_positions = defaultdict(list)
    for y in range(height):
        for x in range(width):
            c = pixels[x, y]
            if c == BLACK:
                continue
            color_positions[c].append((x, y))

    json_out = {}
    for color, positions in color_positions.items():
        rgba = color + (0,)
        packed = struct.pack('<4B', *rgba)
        i = int.from_bytes(packed, byteorder='little', signed=False)
        json_out[i] = list(get_center(positions))

    with open(args.outpath, "w") as f:
        json.dump(json_out, f, indent=2)

    print("Wrote output to:", args.outpath)


def wrap(value, max):
    return value % max


def get_center(points):
    return (
        round(statistics.mean(i[0] for i in points)),
        round(statistics.mean(i[1] for i in points))
    )


if __name__ == "__main__":
    main()

