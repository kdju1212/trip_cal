"""Generate Android, iOS and Play Store icons from branding/app_icon_source.png.

Run from the repository root:  python3 scripts/generate_app_icons.py
Requires Pillow. The source is a square image on a flat light background (BACKGROUND).
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'branding' / 'app_icon_source.png'
BACKGROUND = (242, 247, 253)  # #F2F7FD, the flat background of the source image
RES = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

# Adaptive icons are 108dp; launchers may crop to a 66dp circle. The farthest part of the
# symbol (the plane's tip) lies 0.38 of the image width from the centre, so drawing the image
# at 84dp keeps it within a 32dp radius, inside the safe circle.
CANVAS_DP = 108
IMAGE_DP = 84
VIEWPORT_DP = 72  # the part of the adaptive canvas a launcher shows


def adaptive_canvas(source: Image.Image, size: int) -> Image.Image:
    canvas = Image.new('RGB', (size, size), BACKGROUND)
    inner = round(size * IMAGE_DP / CANVAS_DP)
    image = source.resize((inner, inner), Image.LANCZOS)
    offset = (size - inner) // 2
    canvas.paste(image, (offset, offset))
    return canvas


def rounded(image: Image.Image, radius_ratio: float) -> Image.Image:
    mask = Image.new('L', image.size, 0)
    radius = round(image.size[0] * radius_ratio)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.size[0] - 1, image.size[1] - 1), radius, fill=255)
    result = image.convert('RGBA')
    result.putalpha(mask)
    return result


def main() -> None:
    source = Image.open(SOURCE).convert('RGB')
    if source.size[0] != source.size[1]:
        raise SystemExit('The icon source must be square.')

    # One large adaptive canvas; every Android size is resampled from it.
    large = adaptive_canvas(source, CANVAS_DP * 16)
    crop = round(large.size[0] * (CANVAS_DP - VIEWPORT_DP) / CANVAS_DP / 2)
    visible = large.crop((crop, crop, large.size[0] - crop, large.size[1] - crop))

    for name, scale in DENSITIES.items():
        folder = RES / f'mipmap-{name}'
        folder.mkdir(parents=True, exist_ok=True)
        # Android 8+ adaptive icon foreground (opaque; the background layer is the same colour).
        foreground = large.resize((round(CANVAS_DP * scale),) * 2, Image.LANCZOS)
        foreground.save(folder / 'ic_launcher_foreground.png', optimize=True)
        # Android 7 and older show this file as is, so give it rounded corners.
        legacy = visible.resize((round(48 * scale),) * 2, Image.LANCZOS)
        rounded(legacy, 0.18).save(folder / 'ic_launcher.png', optimize=True)

    anydpi = RES / 'mipmap-anydpi-v26'
    anydpi.mkdir(exist_ok=True)
    (anydpi / 'ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n',
        encoding='utf-8',
    )
    (RES / 'values' / 'ic_launcher_background.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <color name="ic_launcher_background">#%02X%02X%02X</color>\n'
        '</resources>\n' % BACKGROUND,
        encoding='utf-8',
    )

    # Play Store listing icon: 512x512, full-bleed square (Play rounds the corners itself).
    store = ROOT / 'branding' / 'play_store_icon_512.png'
    visible.resize((512, 512), Image.LANCZOS).save(store, optimize=True)

    # iOS: opaque squares without transparency, sized from Contents.json.
    icon_set = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
    for entry in json.loads((icon_set / 'Contents.json').read_text(encoding='utf-8'))['images']:
        points = float(entry['size'].split('x')[0])
        pixels = round(points * float(entry['scale'].rstrip('x')))
        visible.resize((pixels, pixels), Image.LANCZOS).save(icon_set / entry['filename'], optimize=True)

    print('Generated Android, iOS and Play Store icons.')


if __name__ == '__main__':
    main()
