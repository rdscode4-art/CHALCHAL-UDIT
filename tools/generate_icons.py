"""
generate_icons.py
-----------------
Generates Chal Chal Gadi app icon PNGs for all Android mipmap densities,
iOS, and web sizes using Pillow (already installed).

Run from the project root:
    python tools/generate_icons.py
"""

import os
import math
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# Output sizes
# ---------------------------------------------------------------------------
ANDROID_SIZES = {
    "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
    "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
}

WEB_SIZES = {
    "web/icons/Icon-192.png": 192,
    "web/icons/Icon-512.png": 512,
    "web/favicon.png": 32,
    # Maskable variants — logo drawn smaller (80% safe zone) with padded bg
    "web/icons/Icon-maskable-192.png": 192,
    "web/icons/Icon-maskable-512.png": 512,
}

IOS_SIZES = {
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png": 20,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png": 40,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png": 60,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png": 29,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png": 58,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png": 87,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png": 40,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png": 80,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png": 120,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png": 120,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png": 180,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png": 76,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png": 152,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png": 167,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": 1024,
}

WINDOWS_ICON_PATH = "windows/runner/resources/app_icon.ico"
ALL_SIZES = {**ANDROID_SIZES, **WEB_SIZES, **IOS_SIZES}

# Brand colours
BG_COLOR      = (46,  52,  64,  255)   # #2E3440 charcoal
RED_DOT       = (229,  57,  53,  255)  # #E53935
YELLOW_DOT    = (253, 216,  53,  255)  # #FDD835
GREEN_DOT     = ( 67, 160,  71,  255)  # #43A047
WHITE         = (255, 255, 255, 255)
YELLOW_TEXT   = (253, 216,  53,  255)


def draw_icon(size: int, maskable: bool = False) -> Image.Image:
    """Generate the app icon from the `assets/logo2.png` source asset.

    maskable=True draws the icon on a padded square background so maskable
    launcher icons remain safe for shape clipping.
    """
    scale = 4
    S = size * scale
    project_root = os.path.dirname(os.path.dirname(__file__))
    logo_path = os.path.join(project_root, "assets", "logo2.png")

    if not os.path.exists(logo_path):
        raise FileNotFoundError(f"Logo source asset not found: {logo_path}")

    logo_img = Image.open(logo_path).convert("RGBA")

    if logo_img.width != logo_img.height:
        square_size = max(logo_img.width, logo_img.height)
        padded = Image.new("RGBA", (square_size, square_size), (0, 0, 0, 0))
        padded.paste(logo_img, ((square_size - logo_img.width) // 2, (square_size - logo_img.height) // 2), logo_img)
        logo_img = padded

    if maskable:
        background = Image.new("RGBA", (S, S), BG_COLOR)
        logo_size = int(S * 0.80)
        logo_resized = logo_img.resize((logo_size, logo_size), Image.LANCZOS)
        offset = (S - logo_size) // 2
        background.paste(logo_resized, (offset, offset), logo_resized)
        return background.resize((size, size), Image.LANCZOS)

    return logo_img.resize((size, size), Image.LANCZOS)


def _draw_logo_content(S: int) -> Image.Image:
    raise NotImplementedError("This icon generator now uses assets/logo2.png directly.")


def main():
    script_dir   = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    for rel_path, size in ALL_SIZES.items():
        out_path = os.path.join(project_root, rel_path)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        is_maskable = "maskable" in rel_path
        img = draw_icon(size, maskable=is_maskable)
        img.save(out_path, "PNG")
        tag = " [maskable]" if is_maskable else ""
        print(f"  ✓  {rel_path}  ({size}px){tag}")

    # Save master 1024px PNG to assets/
    master_path = os.path.join(project_root, "assets", "logo.png")
    draw_icon(1024).save(master_path, "PNG")
    print(f"\n  ✓  assets/logo.png  (1024px master)")

    # Save Windows ICO file
    windows_ico_path = os.path.join(project_root, WINDOWS_ICON_PATH)
    os.makedirs(os.path.dirname(windows_ico_path), exist_ok=True)
    icon_sizes = [256, 128, 64, 48, 32, 16]
    icon_images = [draw_icon(size) for size in icon_sizes]
    icon_images[0].save(windows_ico_path, format="ICO", sizes=[(size, size) for size in icon_sizes])
    print(f"  ✓  {WINDOWS_ICON_PATH} (multi-size ICO)")

    print("\n✅  All icons generated successfully.")


if __name__ == "__main__":
    main()
