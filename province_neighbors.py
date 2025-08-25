#!/usr/bin/python

from PIL import Image
import json
import struct
import argparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("provinces_image", type=str)
    parser.add_argument("--outpath", default="province_neighbors.json", type=str)
    args = parser.parse_args()

    image = Image.open(args.provinces_image).convert("RGB")
    pixels = image.load()
    if not pixels:
        return

    width, height = image.size

    BLACK = (0, 0, 0)

    color_neighbors = {}
    for y in range(height):
        for x in range(width):
            if pixels[x, y] != BLACK:
                continue

            neighboring_colors = get_neighboring_colors8(pixels, x, y)
            neighboring_colors.discard(BLACK)

            for color in neighboring_colors:
                color_neighbors.setdefault(color, set())
                for n_color in neighboring_colors:
                    if n_color == color:
                        continue
                    color_neighbors[color].add(n_color)

    # Add remaining provinces with no neighbors
    for y in range(height):
        for x in range(width):
            if pixels[x, y] == BLACK or pixels[x, y] in color_neighbors:
                continue

            color_neighbors[pixels[x, y]] = set()

    json_out = {}
    for color, neighbors in color_neighbors.items():
        rgba = color + (0,)
        packed = struct.pack("<4B", *rgba)
        i = int.from_bytes(packed, byteorder="little", signed=False)

        packed_neighbors = []
        for n in neighbors:
            rgban = n + (0,)
            packedn = struct.pack("<4B", *rgban)
            packed_neighbors.append(int.from_bytes(packedn, byteorder="little", signed=True))

        assert(len(packed_neighbors) == len(neighbors))

        json_out[i] = list(packed_neighbors)

    with open(args.outpath, "w") as f:
        json.dump(json_out, f, indent=2)

    print("Wrote output to:", args.outpath)


def get_neighboring_colors8(pixels, x, y):
    neighbors = set()
    for i in range(-1, 2):
        for j in range(-1, 2):
            # Skip center
            if i == 0 and j == 0:
                continue

            if x+i < 0 or y+j < 0:
                continue

            try:
                neighbors.add(pixels[x+i, y+j])
            except IndexError:
                pass

    return neighbors


if __name__ == "__main__":
    main()
