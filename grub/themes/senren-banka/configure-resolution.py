#!/usr/bin/env python3
"""Build resolution/aspect-specific Senren＊Banka GRUB assets and layout metadata.

Profiles:
- 16:9: native full-screen composition.
- 16:10: keep the 16:9 composition bottom-aligned, fill extra top area white.
- ultrawide: keep a complete 16:9 composition centered, fill side areas black.
- fallback: fit a complete 16:9 composition centered on black.
"""
from __future__ import annotations
import argparse, json, math, re
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
SRC = HERE / "source"
BASE_W, BASE_H = 1920, 1080


def parse_resolution(value: str) -> tuple[int, int]:
    m = re.fullmatch(r"\s*(\d{3,5})[xX](\d{3,5})\s*", value)
    if not m:
        raise SystemExit(f"Invalid resolution: {value!r}; expected WIDTHxHEIGHT, e.g. 1920x1080")
    w, h = map(int, m.groups())
    if w < 800 or h < 600:
        raise SystemExit("Resolution is too small for this theme (minimum supported test range: 800x600).")
    return w, h


def profile_for(w: int, h: int):
    ratio = w / h
    r169, r1610 = 16 / 9, 16 / 10
    if abs(ratio - r169) <= 0.045:
        profile = "16:9"
        scale = h / BASE_H
        xoff = yoff = 0
        content_w, content_h = w, h
        fill = (255, 255, 255)
    elif abs(ratio - r1610) <= 0.045:
        profile = "16:10"
        scale = w / BASE_W
        content_w = w
        content_h = round(BASE_H * scale)
        xoff = 0
        yoff = h - content_h
        fill = (255, 255, 255)
    elif ratio >= 1.90:
        profile = "ultrawide"
        scale = h / BASE_H
        content_w = round(BASE_W * scale)
        content_h = h
        xoff = round((w - content_w) / 2)
        yoff = 0
        fill = (0, 0, 0)
    else:
        profile = "fallback-letterbox"
        scale = min(w / BASE_W, h / BASE_H)
        content_w = round(BASE_W * scale)
        content_h = round(BASE_H * scale)
        xoff = round((w - content_w) / 2)
        yoff = round((h - content_h) / 2)
        fill = (0, 0, 0)
    return profile, scale, xoff, yoff, content_w, content_h, fill


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("resolution", help="WIDTHxHEIGHT, e.g. 1920x1080")
    args = ap.parse_args()
    w, h = parse_resolution(args.resolution)
    profile, scale, xoff, yoff, cw, ch, fill = profile_for(w, h)

    # UI grows slightly slower than the artwork on high resolutions. This keeps
    # 1440p/4K text from looking like a mechanically enlarged 1080p theme.
    ui_scale = scale ** 0.80
    font_main = max(18, round(30 * ui_scale))
    font_message = max(14, round(22 * ui_scale))
    blank_size = max(8, round(12 * ui_scale))
    item_h = max(34, round(56 * ui_scale))
    pitch = max(item_h + 12, round(100 * scale))
    base_spacing = max(12, pitch - item_h)
    min_spacing = max(8, round(20 * scale))
    max_menu_h = round(656 * scale)
    max_visible = 6 if h < 850 else (7 if h < 1000 else 8)

    # Background: never stretch the character artwork outside the designed ratio.
    base = Image.open(SRC / "background-1920x1080.png").convert("RGB")
    canvas = Image.new("RGB", (w, h), fill)
    resized = base.resize((cw, ch), Image.Resampling.LANCZOS)
    canvas.paste(resized, (xoff, yoff))
    canvas.save(HERE / "background.png", compress_level=4)

    # Logo is generated at the artwork scale; its absolute theme size remains exact.
    logo = Image.open(SRC / "title_logo-1080p.png").convert("RGBA")
    logo_w, logo_h = max(1, round(437 * scale)), max(1, round(184 * scale))
    logo.resize((logo_w, logo_h), Image.Resampling.LANCZOS).save(HERE / "title_logo.png", compress_level=6)

    # Menu class icons include the small subtitle row, so scale them with UI metrics.
    icon_dir = HERE / "icons"
    icon_dir.mkdir(exist_ok=True)
    icon_w, icon_h = max(1, round(300 * ui_scale)), item_h
    for src in sorted((SRC / "icons").glob("*.png")):
        im = Image.open(src).convert("RGBA")
        im.resize((icon_w, icon_h), Image.Resampling.LANCZOS).save(icon_dir / src.name, compress_level=6)

    data = {
        "version": "0.8.0-dev",
        "resolution": f"{w}x{h}", "width": w, "height": h,
        "profile": profile, "artwork_scale": scale, "ui_scale": ui_scale,
        "x_offset": xoff, "y_offset": yoff,
        "content_width": cw, "content_height": ch,
        "font_main": font_main, "font_message": font_message, "blank_size": blank_size,
        "item_height": item_h, "base_spacing": base_spacing, "min_spacing": min_spacing,
        "max_menu_height": max_menu_h, "max_visible": max_visible,
        "center_y": round(yoff + 676 * scale),
        "logo_left": round(xoff + 36 * scale), "logo_top": round(yoff + 60 * scale),
        "logo_width": logo_w, "logo_height": logo_h,
        "menu_left": round(xoff + 58 * scale),
        "menu_width": round(570 * scale),
        "item_icon_space": round(52 * ui_scale),
        "icon_width": icon_w, "icon_height": icon_h,
        "icon_top_offset": max(2, round(8 * scale)),
    }
    (HERE / ".profile.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Senren profile: {data['resolution']} / {profile}; artwork scale={scale:.3f}, UI scale={ui_scale:.3f}")
    if profile == "16:10":
        print(f"16:10: 16:9 artwork bottom-aligned; {yoff}px white area above.")
    elif profile == "ultrawide":
        print(f"Ultrawide: 16:9 artwork centered; {xoff}px black pillarbox on each side (for symmetric modes).")
    elif profile == "fallback-letterbox":
        print("Warning: this aspect ratio is experimental; using centered black letterbox fallback.")

if __name__ == "__main__":
    main()
