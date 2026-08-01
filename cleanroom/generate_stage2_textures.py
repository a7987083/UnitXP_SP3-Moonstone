#!/usr/bin/env python3
from pathlib import Path
import sys

import numpy as np
from PIL import Image


def main() -> None:
    output = Path(sys.argv[1] if len(sys.argv) > 1 else "cleanroom_input/addon/MoonMarker/Textures")
    output.mkdir(parents=True, exist_ok=True)

    # Wide, soft vertical shaft. Alpha stays moderate because the renderer uses
    # additive blending. There is intentionally no narrow laser-like core.
    width, height = 256, 512
    yy, xx = np.mgrid[0:height, 0:width]
    x = (xx - (width - 1) / 2.0) / ((width - 1) / 2.0)
    y = yy / (height - 1.0)

    sigma_outer = 0.38 + 0.08 * (y ** 1.6)
    sigma_mid = 0.20 + 0.045 * (y ** 1.6)
    outer = np.exp(-0.5 * (x / sigma_outer) ** 2)
    middle = np.exp(-0.5 * (x / sigma_mid) ** 2)

    top_fade = np.clip((y - 0.015) / 0.24, 0.0, 1.0)
    top_fade = top_fade * top_fade * (3.0 - 2.0 * top_fade)
    lower = 0.88 + 0.12 * np.clip((y - 0.62) / 0.38, 0.0, 1.0)
    vertical_streaks = (
        0.97
        + 0.018 * np.sin((x + 1.0) * 53.0)
        + 0.012 * np.sin((x + 1.0) * 101.0 + 0.7)
    )
    vertical_streaks = np.clip(vertical_streaks, 0.92, 1.03)

    alpha = (0.61 * outer + 0.27 * middle) * top_fade * lower * vertical_streaks
    floor_bloom = np.exp(-0.5 * ((y - 0.94) / 0.08) ** 2) * np.exp(-0.5 * (x / 0.55) ** 2)
    alpha = np.clip(alpha + 0.16 * floor_bloom, 0.0, 1.0)

    beam_alpha = (alpha * 145.0).astype(np.uint8)
    center = (middle * 9.0).astype(np.uint8)
    beam_red = np.clip(228 + center, 0, 255).astype(np.uint8)
    beam_green = np.clip(240 + center, 0, 255).astype(np.uint8)
    beam_blue = np.full((height, width), 255, dtype=np.uint8)
    Image.fromarray(
        np.dstack([beam_red, beam_green, beam_blue, beam_alpha]),
        "RGBA",
    ).save(output / "moonbeam.png")

    # Broad floor pool, drawn as a separate orthographic quad before the shaft.
    width, height = 512, 256
    yy, xx = np.mgrid[0:height, 0:width]
    x = (xx - (width - 1) / 2.0) / ((width - 1) / 2.0)
    y = (yy - (height - 1) / 2.0) / ((height - 1) / 2.0)

    radius = np.sqrt((x / 1.0) ** 2 + (y / 0.78) ** 2)
    soft = np.clip(1.0 - radius, 0.0, 1.0) ** 2.15
    core = np.exp(-0.5 * ((x / 0.34) ** 2 + (y / 0.30) ** 2))
    halo = np.exp(-0.5 * ((x / 0.80) ** 2 + (y / 0.58) ** 2))
    glow_alpha = np.clip(0.72 * soft + 0.22 * core + 0.10 * halo, 0.0, 1.0)
    noise = (
        np.sin(xx * 0.043)
        + np.sin(yy * 0.081)
        + np.sin((xx + yy) * 0.031)
    ) * 0.012
    glow_alpha = np.clip(glow_alpha * (1.0 + noise), 0.0, 1.0)

    glow = np.dstack(
        [
            np.full((height, width), 238, dtype=np.uint8),
            np.full((height, width), 246, dtype=np.uint8),
            np.full((height, width), 255, dtype=np.uint8),
            (glow_alpha * 150.0).astype(np.uint8),
        ]
    )
    Image.fromarray(glow, "RGBA").save(output / "moonglow.png")


if __name__ == "__main__":
    main()
