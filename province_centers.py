from PIL import Image
import statistics
import sys
from collections import defaultdict
import json


def wrap(value, max):
    return value % max


def get_center(points):
    return (
        round(statistics.mean(i[0] for i in points)),
        round(statistics.mean(i[1] for i in points))
    )


def main():
    if len(sys.argv) != 2 and len(sys.argv) != 3:
        print("Usage: " + __file__ + " input [output]")
        return

    image = Image.open(sys.argv[1]).convert("RGB")
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
        json_out[str(color)] = list(get_center(positions))

    if len(sys.argv) == 3:
        path_out = sys.argv[2]
    else:
        path_out = "province_centers.json"

    output = json.dumps(json_out)
    with open(path_out, "w") as f:
        f.write(output)

    print("Saved json to", path_out)


if __name__ == "__main__":
    main()
