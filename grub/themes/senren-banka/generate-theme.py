#!/usr/bin/env python3
from __future__ import annotations
import argparse, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
PROFILE=HERE/'.profile.json'
if not PROFILE.exists():
    raise SystemExit('Missing .profile.json. Run configure-resolution.py WIDTHxHEIGHT first.')
p=json.loads(PROFILE.read_text(encoding='utf-8'))
ITEM_H=int(p['item_height']); BASE_SPACING=int(p['base_spacing']); MIN_SPACING=int(p['min_spacing'])
MAX_MENU_H=int(p['max_menu_height']); CENTER_Y=int(p['center_y']); MAX_VISIBLE=int(p['max_visible'])
FONT_MAIN=int(p['font_main']); FONT_MSG=int(p['font_message']); BLANK=int(p['blank_size'])
SCALE=float(p['artwork_scale']); UI=float(p['ui_scale'])
ap=argparse.ArgumentParser(); ap.add_argument('count',type=int); ap.add_argument('-o','--output',default='theme.txt'); a=ap.parse_args()
count=max(1,a.count); visible=min(count,MAX_VISIBLE)
if visible <= 1: spacing=BASE_SPACING
else:
    fit_spacing=(MAX_MENU_H-visible*ITEM_H)//(visible-1)
    spacing=max(MIN_SPACING,min(BASE_SPACING,fit_spacing))
height=visible*ITEM_H+(visible-1)*spacing
top=round(CENTER_Y-height/2); icon_top=top+int(p['icon_top_offset'])
font=f'Senren Menu Bold {FONT_MAIN}'; blank=f'GRUB Blank Regular {BLANK}'
lines=[]
def add(*xs): lines.extend(xs)
add('title-text: ""','desktop-image: "background.png"',
    'desktop-color: "#000000"' if p['profile'] in ('ultrawide','fallback-letterbox') else 'desktop-color: "#ffffff"',
    f'message-font: "Senren Menu Bold {FONT_MSG}"','message-color: "#8f6829"','message-bg-color: "#fffdf7"',
    'terminal-left: "0"','terminal-top: "0"','terminal-width: "100%"','terminal-height: "100%"','terminal-border: "0"','',
    '+ image {',f'  left = {p["logo_left"]}',f'  top = {p["logo_top"]}',f'  width = {p["logo_width"]}',f'  height = {p["logo_height"]}','  file = "title_logo.png"','}','')

def menu(left,mt,iconw,icons,color,selcolor,blank_layer=False,width=None):
    width=int(width or p['menu_width'])
    # GRUB still resolves and scales class icons for every boot_menu layer.
    # A zero-sized icon therefore reaches grub_video_bitmap_create_scaled()
    # when a selected entry starts, even when this layer is text-only.
    render_icon_w=max(1,iconw)
    render_icon_h=max(1,int(p['icon_height']) if iconw else 1)
    add('+ boot_menu {',f'  left = {left}',f'  top = {mt}',f'  width = {width}',f'  height = {height}',
        f'  icon_width = {render_icon_w}',f'  icon_height = {render_icon_h}',f'  item_icon_space = {icons}',
        f'  item_height = {ITEM_H}','  item_padding = 0',f'  item_spacing = {spacing}',
        f'  item_font = "{blank if blank_layer else font}"',f'  item_color = "{color}"',
        f'  selected_item_font = "{blank if blank_layer else font}"',f'  selected_item_color = "{selcolor}"',
        '  scrollbar = false','}','')
left0=int(p['menu_left'])
menu(left0, icon_top, int(p['icon_width']), 0, '#ffffff','#ffffff',True)
menu(left0, top, 0, int(p['item_icon_space']), '#aa914d','#a95643')
Path(a.output).write_text('\n'.join(lines),encoding='utf-8')
print(f"count={count} visible={visible} profile={p['profile']} spacing={spacing} top={top} height={height}")
