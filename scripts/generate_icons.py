import os
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

def create_scandium_icon(accent_name, color_start, color_end, glow_color):
    # Supersampling 2048x2048
    size = 2048
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)

    # 1. Dark titanium background gradient
    for y in range(size):
        factor = y / size
        r = int(14 * (1 - factor) + 6 * factor)
        g = int(15 * (1 - factor) + 7 * factor)
        b = int(18 * (1 - factor) + 9 * factor)
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

    # Radial ambient glow in center
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    cx, cy = size // 2, size // 2 - 40
    max_radius = 750
    for r in range(max_radius, 0, -15):
        alpha = int(45 * (1 - (r / max_radius) ** 1.5))
        glow_draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(glow_color[0], glow_color[1], glow_color[2], alpha)
        )
    glow = glow.filter(ImageFilter.GaussianBlur(radius=60))
    img = Image.alpha_composite(img, glow)

    # 2. Subtle outer squircle / rounded border
    border_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    b_draw = ImageDraw.Draw(border_layer)
    margin = 120
    rect = [margin, margin, size - margin, size - margin]
    b_draw.rounded_rectangle(rect, radius=340, outline=(255, 255, 255, 25), width=8)
    b_draw.rounded_rectangle(rect, radius=340, outline=(glow_color[0], glow_color[1], glow_color[2], 50), width=3)
    img = Image.alpha_composite(img, border_layer)

    # 3. Text and Symbols
    text_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    t_draw = ImageDraw.Draw(text_layer)

    font_path = "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans-Bold.ttf"
    if not os.path.exists(font_path):
        font_path = "/usr/lib64/python3.14/site-packages/matplotlib/mpl-data/fonts/ttf/DejaVuSans-Bold.ttf"

    font_21 = ImageFont.truetype(font_path, 940)
    font_sub = ImageFont.truetype(font_path, 95)

    # Central large number "21" with vertical gradient (no "Sc" text)
    num_str = "21"
    num_bbox = t_draw.textbbox((0, 0), num_str, font=font_21)
    num_w = num_bbox[2] - num_bbox[0]
    num_h = num_bbox[3] - num_bbox[1]
    num_x = (size - num_w) // 2
    num_y = (size - num_h) // 2 - 130

    # Draw gradient mask for number 21
    mask_21 = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask_21)
    mask_draw.text((num_x, num_y), num_str, fill=255, font=font_21)

    gradient_num = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(gradient_num)
    y_start = num_y
    y_end = num_y + num_h
    for y in range(y_start, y_end + 1):
        t = (y - y_start) / max(1, (y_end - y_start))
        nr = int(color_start[0] * (1 - t) + color_end[0] * t)
        ng = int(color_start[1] * (1 - t) + color_end[1] * t)
        nb = int(color_start[2] * (1 - t) + color_end[2] * t)
        g_draw.line([(0, y), (size, y)], fill=(nr, ng, nb, 255))

    gradient_num.putalpha(mask_21)
    text_layer = Image.alpha_composite(text_layer, gradient_num)

    # 4. Sound wave bars below "21"
    bars_y = 1480
    bar_heights = [65, 120, 185, 240, 165, 105, 55]
    bar_width = 34
    bar_gap = 36
    total_w = len(bar_heights) * bar_width + (len(bar_heights) - 1) * bar_gap
    start_x = (size - total_w) // 2

    for i, bh in enumerate(bar_heights):
        bx = start_x + i * (bar_width + bar_gap)
        by1 = bars_y - bh // 2
        by2 = bars_y + bh // 2
        t = 1.0 - abs(i - 3) / 4.0
        bar_color = (
            int(color_start[0] * t + 180 * (1 - t)),
            int(color_start[1] * t + 180 * (1 - t)),
            int(color_start[2] * t + 180 * (1 - t)),
            int(180 + 75 * t)
        )
        t_draw.rounded_rectangle([bx, by1, bx + bar_width, by2], radius=17, fill=bar_color)

    # "SCANDIUM" subtitle at bottom
    sub_str = "SCANDIUM"
    sub_bbox = t_draw.textbbox((0, 0), sub_str, font=font_sub)
    sub_w = sub_bbox[2] - sub_bbox[0]
    sub_x = (size - sub_w) // 2
    sub_y = 1660
    t_draw.text((sub_x, sub_y), sub_str, fill=(160, 170, 185, 180), font=font_sub)

    img = Image.alpha_composite(img, text_layer)

    # Downscale from 2048 to 1024 with high-quality Lanczos
    final_icon = img.resize((1024, 1024), Image.Resampling.LANCZOS)
    return final_icon.convert("RGB")

variants = {
    "default": {
        "prefix": "AppIcon",
        "start": (30, 235, 110),
        "end": (16, 175, 80),
        "glow": (25, 205, 95)
    },
    "Orange": {
        "prefix": "AppIcon-Orange",
        "start": (255, 140, 20),
        "end": (255, 75, 0),
        "glow": (255, 100, 10)
    },
    "Cyan": {
        "prefix": "AppIcon-Cyan",
        "start": (40, 240, 255),
        "end": (0, 180, 230),
        "glow": (0, 210, 255)
    },
    "Purple": {
        "prefix": "AppIcon-Purple",
        "start": (210, 150, 255),
        "end": (155, 70, 245),
        "glow": (180, 100, 255)
    },
    "Monochrome": {
        "prefix": "AppIcon-Monochrome",
        "start": (255, 255, 255),
        "end": (180, 185, 195),
        "glow": (200, 205, 215)
    }
}

os.makedirs("assets", exist_ok=True)

# Generate primary default icon and all variants
for var_name, var_info in variants.items():
    print(f"Generating variant: {var_name}...")
    icon_1024 = create_scandium_icon(var_name, var_info["start"], var_info["end"], var_info["glow"])
    prefix = var_info["prefix"]

    sizes = {
        "20x20@2x": 40,
        "20x20@3x": 60,
        "29x29@2x": 58,
        "29x29@3x": 87,
        "40x40@2x": 80,
        "40x40@3x": 120,
        "60x60@2x": 120,
        "60x60@3x": 180,
        "76x76@2x": 152
    }

    if var_name == "default":
        icon_1024.save("assets/AppIcon.png", "PNG", optimize=True)
        icon_1024.resize((180, 180), Image.Resampling.LANCZOS).save("assets/icon.png", "PNG", optimize=True)
        for name, sz in sizes.items():
            resized = icon_1024.resize((sz, sz), Image.Resampling.LANCZOS)
            resized.save(f"assets/AppIcon{name}.png", "PNG", optimize=True)
    else:
        # Full master icon for variant
        icon_1024.save(f"assets/{prefix}.png", "PNG", optimize=True)
        # Direct @2x and @3x files (standard iOS resolution convention for CFBundleAlternateIcons)
        icon_1024.resize((120, 120), Image.Resampling.LANCZOS).save(f"assets/{prefix}@2x.png", "PNG", optimize=True)
        icon_1024.resize((180, 180), Image.Resampling.LANCZOS).save(f"assets/{prefix}@3x.png", "PNG", optimize=True)
        # Sized variants
        for name, sz in sizes.items():
            resized = icon_1024.resize((sz, sz), Image.Resampling.LANCZOS)
            resized.save(f"assets/{prefix}{name}.png", "PNG", optimize=True)

print("Icon generation completed successfully!")
