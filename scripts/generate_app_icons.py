"""Generate the shared MOYE app icon for Windows and Android.

The mark is a warm paper disc with the character 墨 on a deep pine ground,
plus a thin brass ring. Keeping one vector-like source for every platform
prevents the Windows shortcut and Android launcher from drifting apart.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CANVAS = 1024
INK_TOP = (27, 58, 47)
INK_BOTTOM = (10, 27, 22)
PAPER = (244, 238, 222)
INK = (22, 38, 31)
BRASS = (194, 157, 84)
FONT_PATH = Path(r"C:\Windows\Fonts\msyhbd.ttc")


def rounded_mask(size: int, radius: int, inset: int = 40) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (inset, inset, size - inset, size - inset),
        radius=radius,
        fill=255,
    )
    return mask


def gradient(size: int) -> Image.Image:
    image = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = y / (size - 1)
        color = tuple(
            round(INK_TOP[i] * (1 - t) + INK_BOTTOM[i] * t) for i in range(3)
        )
        draw.line((0, y, size, y), fill=color)
    return image


def font(size: int) -> ImageFont.FreeTypeFont:
    if FONT_PATH.exists():
        return ImageFont.truetype(str(FONT_PATH), size)
    return ImageFont.truetype("arial.ttf", size)


def draw_glyph(draw: ImageDraw.ImageDraw, cx: int, cy: int, size: int) -> None:
    face = font(size)
    left, top, right, bottom = draw.textbbox((0, 0), "墨", font=face)
    draw.text(
        (cx - (left + right) / 2, cy - (top + bottom) / 2),
        "墨",
        font=face,
        fill=INK,
    )


def full_icon(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    image.paste(gradient(size), (0, 0), rounded_mask(size, radius=210))
    draw = ImageDraw.Draw(image)
    center = size // 2
    disc_radius = round(size * 0.292)
    draw.ellipse(
        (
            center - disc_radius,
            center - disc_radius,
            center + disc_radius,
            center + disc_radius,
        ),
        fill=PAPER,
    )
    ring = disc_radius + round(size * 0.010)
    draw.ellipse(
        (center - ring, center - ring, center + ring, center + ring),
        outline=BRASS,
        width=max(2, round(size * 0.006)),
    )
    draw_glyph(draw, center, center - round(size * 0.006), round(size * 0.41))
    # A small brass bookmark tab at the lower-right edge of the paper disc.
    tab_w = round(size * 0.045)
    tab_h = round(size * 0.095)
    tab_x = center + round(size * 0.205)
    tab_y = center + round(size * 0.205)
    draw.rounded_rectangle(
        (tab_x, tab_y, tab_x + tab_w, tab_y + tab_h),
        radius=tab_w // 2,
        fill=BRASS,
    )
    return image


def foreground(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    center = size // 2
    disc_radius = round(size * 0.292)
    draw.ellipse(
        (
            center - disc_radius,
            center - disc_radius,
            center + disc_radius,
            center + disc_radius,
        ),
        fill=PAPER,
    )
    ring = disc_radius + round(size * 0.010)
    draw.ellipse(
        (center - ring, center - ring, center + ring, center + ring),
        outline=BRASS,
        width=max(2, round(size * 0.006)),
    )
    draw_glyph(draw, center, center - round(size * 0.006), round(size * 0.41))
    tab_w = round(size * 0.045)
    tab_h = round(size * 0.095)
    tab_x = center + round(size * 0.205)
    tab_y = center + round(size * 0.205)
    draw.rounded_rectangle(
        (tab_x, tab_y, tab_x + tab_w, tab_y + tab_h),
        radius=tab_w // 2,
        fill=BRASS,
    )
    return image


def main() -> None:
    master = full_icon(CANVAS)
    branding = ROOT / "assets" / "branding"
    branding.mkdir(parents=True, exist_ok=True)
    master.save(branding / "moye_icon_1024.png")

    ico = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    master.save(
        ico,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    densities = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    foreground_files = []
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for density, px in densities.items():
        directory = res / f"mipmap-{density}"
        directory.mkdir(parents=True, exist_ok=True)
        master.resize((px, px), Image.Resampling.LANCZOS).save(
            directory / "ic_launcher.png"
        )
        fg_size = px * 9 // 4
        fg = foreground(fg_size)
        fg.save(directory / "ic_launcher_foreground.png")
        foreground_files.append((density, fg_size))

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
""",
        encoding="utf-8",
    )
    values = res / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "colors.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#12261F</color>
</resources>
""",
        encoding="utf-8",
    )
    print("master", master.size)
    print("windows", ico, ico.stat().st_size, "bytes")
    print("android", foreground_files)


if __name__ == "__main__":
    main()
