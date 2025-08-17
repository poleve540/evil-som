#!/usr/bin/python

from PIL import Image, ImageDraw
import argparse


def wrap(value, max):
    return value % max


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("countries_image", type=str)
    parser.add_argument("--outpath", default="provinces.png", type=str)
    args = parser.parse_args()

    image = Image.open(args.countries_image).convert("RGB")
    pixels = image.load()
    if not pixels:
        return

    width, height = image.size

    BLACK = (0,0,0)

    r = 0
    g = 1
    b = 0

    colors = set()
    for y in range(height):
        for x in range(width):
            c = pixels[x, y]
            if c == BLACK or c in colors:
                continue

            new_color = (r, g, b)
            colors.add(new_color)

            ImageDraw.floodfill(image, (x, y), new_color)

            g = wrap(g+1, 256)
            if g == 0:
                r = wrap(r+1, 256)
                if r == 0:
                    b = wrap(b+1, 256)
                    if b == 256:
                        print("Ran out of unique colors !!!")
 
    print("Saved image to:", args.outpath)
    image.save(args.outpath)


if __name__ == "__main__":
    main()
