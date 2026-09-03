"""Builds the side-by-side overview golden (00) from the two single-screen goldens.

Usage: python3 compose.py 00a.png 00b.png 00.png

Left and right are placed at full size with a 90 px gutter in the page
background (#080808), the same layout the approved 00-mobile-nav-books.png has.
"""

import sys

from PIL import Image

GUTTER = 90
BACKGROUND = (8, 8, 8)


def main(left_path: str, right_path: str, out_path: str) -> None:
    left = Image.open(left_path).convert("RGB")
    right = Image.open(right_path).convert("RGB")
    height = max(left.height, right.height)
    canvas = Image.new("RGB", (left.width + GUTTER + right.width, height), BACKGROUND)
    canvas.paste(left, (0, 0))
    canvas.paste(right, (left.width + GUTTER, 0))
    canvas.save(out_path)
    print("wrote", out_path)


if __name__ == "__main__":
    main(*sys.argv[1:4])
