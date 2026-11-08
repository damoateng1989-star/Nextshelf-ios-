#!/usr/bin/env python3
"""Generate NextShelf/Assets.xcassets from the logo set.

Re-runnable: reads the PNGs in ~/workspace/your_files/nextshelf-logo-v2/
and writes the app-icon sizes, colour sets (light/dark) and image sets.

    python3 tools/generate-assets.py

App icon sizes follow the Xcode template for an iOS 17 iPhone app
(iPad sizes included for completeness).
"""
import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
LOGO_DIR = Path.home() / "workspace" / "your_files" / "nextshelf-logo-v2"
ASSETS = ROOT / "NextShelf" / "Assets.xcassets"

ICON_SIZES = [
    # (idiom, size_pt, scale, filename)
    ("iphone", 20, 2, "icon-40.png"),
    ("iphone", 20, 3, "icon-60.png"),
    ("iphone", 29, 2, "icon-58.png"),
    ("iphone", 29, 3, "icon-87.png"),
    ("iphone", 40, 2, "icon-80.png"),
    ("iphone", 40, 3, "icon-120.png"),
    ("iphone", 60, 2, "icon-120-60.png"),
    ("iphone", 60, 3, "icon-180.png"),
    ("ipad", 20, 1, "icon-20.png"),
    ("ipad", 20, 2, "icon-40-ipad.png"),
    ("ipad", 29, 1, "icon-29.png"),
    ("ipad", 29, 2, "icon-58-ipad.png"),
    ("ipad", 40, 1, "icon-40-1x.png"),
    ("ipad", 40, 2, "icon-80-ipad.png"),
    ("ipad", 76, 1, "icon-76.png"),
    ("ipad", 76, 2, "icon-152.png"),
    ("ipad", 83.5, 2, "icon-167.png"),
    ("ios-marketing", 1024, 1, "icon-1024.png"),
]

COLORS = {
    # name: (light hex, dark hex or None)
    "Paper": ("#F6F6F3", "#0E1116"),
    "Card": ("#FFFFFF", "#171B22"),
    "Ink": ("#1A1C22", "#F2F3F5"),
    "Muted": ("#6E746E", "#9AA0AB"),
    "Line": ("#E7E0D6", "#262B34"),
    "BrandBlue": ("#2F6BFF", None),
    "UpGreen": ("#22C55E", None),
    "DownRed": ("#DC2626", None),
    "Amber": ("#D97706", None),
    "AccentColor": ("#2F6BFF", None),
}


def hex_components(hexstr):
    h = hexstr.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return {"alpha": "1.000", "blue": f"0x{b:02X}", "green": f"0x{g:02X}", "red": f"0x{r:02X}"}


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def gen_appicon():
    d = ASSETS / "AppIcon.appiconset"
    d.mkdir(parents=True, exist_ok=True)
    master = Image.open(LOGO_DIR / "logo-app-icon-white.png").convert("RGBA")
    # App Store rule: no alpha in app icons. Flatten onto the tile colour, sampled from an
    # opaque pixel on the tile's top edge (iOS rounds the corners itself).
    fill = master.getpixel((master.width // 2, 16))[:3]
    flat = Image.new("RGB", master.size, fill)
    flat.paste(master, mask=master.getchannel("A"))
    images = []
    for idiom, size, scale, filename in ICON_SIZES:
        px = int(size * scale)
        flat.resize((px, px), Image.LANCZOS).save(d / filename)
        images.append({
            "filename": filename,
            "idiom": idiom,
            "scale": f"{scale}x",
            "size": f"{size:g}x{size:g}",
        })
    write_json(d / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})


def gen_colors():
    for name, (light, dark) in COLORS.items():
        d = ASSETS / f"{name}.colorset"
        d.mkdir(parents=True, exist_ok=True)
        colors = [{"color": {"color-space": "srgb", "components": hex_components(light)},
                   "idiom": "universal"}]
        if dark:
            colors.append({
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "color": {"color-space": "srgb", "components": hex_components(dark)},
                "idiom": "universal",
            })
        write_json(d / "Contents.json", {"colors": colors, "info": {"author": "xcode", "version": 1}})


def gen_images():
    # AppIconTile: the 1024 mark, used as the auth hero tile.
    d = ASSETS / "AppIconTile.imageset"
    d.mkdir(parents=True, exist_ok=True)
    shutil.copy(LOGO_DIR / "logo-app-icon-white.png", d / "tile.png")
    write_json(d / "Contents.json", {
        "images": [{"filename": "tile.png", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1},
    })
    # LaunchLogo + Wordmark: light lockup on light, dark lockup on dark.
    for name in ("LaunchLogo", "Wordmark"):
        d = ASSETS / f"{name}.imageset"
        d.mkdir(parents=True, exist_ok=True)
        shutil.copy(LOGO_DIR / "logo-primary.png", d / "logo-light.png")
        shutil.copy(LOGO_DIR / "logo-dark.png", d / "logo-dark.png")
        write_json(d / "Contents.json", {
            "images": [
                {"filename": "logo-light.png", "idiom": "universal", "scale": "1x"},
                {"appearances": [{"appearance": "luminosity", "value": "dark"}],
                 "filename": "logo-dark.png", "idiom": "universal", "scale": "1x"},
            ],
            "info": {"author": "xcode", "version": 1},
        })


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    write_json(ASSETS / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    gen_appicon()
    gen_colors()
    gen_images()
    print(f"Wrote {ASSETS}")


if __name__ == "__main__":
    main()
