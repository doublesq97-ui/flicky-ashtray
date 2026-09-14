#!/usr/bin/env python3
"""Trim transparent padding from generated UI cutouts while preserving a small safe margin."""

from pathlib import Path
import sys

from PIL import Image


def trim(path: Path) -> None:
    image = Image.open(path).convert("RGBA")
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError(f"{path.name} has no visible pixels")
    left, top, right, bottom = bounds
    padding = max(4, round(max(right - left, bottom - top) * 0.06))
    box = (
        max(0, left - padding),
        max(0, top - padding),
        min(image.width, right + padding),
        min(image.height, bottom + padding),
    )
    image.crop(box).save(path)
    print(f"{path.name}: {image.size} -> {image.crop(box).size}")


if __name__ == "__main__":
    for argument in sys.argv[1:]:
        trim(Path(argument))
