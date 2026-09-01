#!/usr/bin/env python3
"""Крупная иконка приложения из канонической launcher-иконки 172x172.

Зачем не простое растяжение: 172 -> 512 это увеличение почти втрое, и любой
resample даёт либо мыло, либо «лесенку» исходника на прямых краях. Здесь из
исходника извлекается МАСКА покрытия глифа, увеличивается без интерполяции,
сглаживается по кривизне (размытие + жёсткий порог — мелкие ступеньки уходят,
а форма и углы крупнее радиуса размытия остаются), и уменьшается с усреднением.
Рисунок остаётся тем же самым, край получается чистым.

Форму НЕ перерисовываем примитивами: у силуэта левый и правый торцы скруглены
по-разному, и подгонка на глаз дала бы иконку, похожую на launcher-иконку, но
не ту же самую.

Фон — линейный градиент по диагонали, снятый с исходника по углам.
"""
import sys
from PIL import Image, ImageFilter

SOURCE = "icons/172x172/ru.codeagent43824.rutokentestapp.png"
# Цвета углов исходника: слева сверху и справа снизу. Синий канал постоянный.
TOP_LEFT = (64, 77, 229)
BOTTOM_RIGHT = (90, 105, 229)
SUPERSAMPLE = 8
# Радиус сглаживания в пикселях увеличенной маски. Подобран по результату:
# меньше — на длинных прямых краях остаётся волна от растра 172, заметно больше —
# начинают заплывать углы разъёма.
SMOOTH_RADIUS = 6.0


def background(size):
    """Диагональный градиент: значение зависит от (x + y)."""
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    last = 2 * (size - 1)
    for y in range(size):
        for x in range(size):
            t = (x + y) / last
            pixels[x, y] = tuple(
                round(a + (b - a) * t) for a, b in zip(TOP_LEFT, BOTTOM_RIGHT))
    return image


def glyph_mask(source):
    """Покрытие белым глифом, 0..255, с вычтенным фоном исходника."""
    width, height = source.size
    pixels = source.convert("RGB").load()
    mask = Image.new("L", (width, height))
    out = mask.load()
    last = 2 * (width - 1)
    for y in range(height):
        for x in range(width):
            t = (x + y) / last
            coverage = 0.0
            for channel in (0, 1):
                base = TOP_LEFT[channel] + (BOTTOM_RIGHT[channel] - TOP_LEFT[channel]) * t
                if base < 255:
                    coverage += (pixels[x, y][channel] - base) / (255 - base)
            out[x, y] = max(0, min(255, round(coverage / 2 * 255)))
    return mask


def sharpen(mask, low=0.42, high=0.58):
    """Возврат резкого края после увеличения: узкий переход вместо размытого."""
    table = []
    for value in range(256):
        t = value / 255
        if t <= low:
            table.append(0)
        elif t >= high:
            table.append(255)
        else:
            table.append(round((t - low) / (high - low) * 255))
    return mask.point(table)


def build(size):
    source = Image.open(SOURCE).convert("RGBA")
    large = source.size[0] * SUPERSAMPLE
    mask = glyph_mask(source).resize((large, large), Image.NEAREST)
    mask = sharpen(mask.filter(ImageFilter.GaussianBlur(SMOOTH_RADIUS)), 0.48, 0.52)
    icon = background(large)
    icon.paste((255, 255, 255), (0, 0), mask)
    return icon.resize((size, size), Image.LANCZOS).convert("RGB")


if __name__ == "__main__":
    size = int(sys.argv[1]) if len(sys.argv) > 1 else 512
    target = sys.argv[2] if len(sys.argv) > 2 else f"icon-{size}.png"
    build(size).save(target, "PNG", optimize=True)
    print(f"{target}: {size}x{size}")
