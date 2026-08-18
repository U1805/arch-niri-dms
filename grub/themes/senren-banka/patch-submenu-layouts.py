#!/usr/bin/env python3
"""Inject count-specific, scope-local theme selection into GRUB submenus.

GRUB opens an environment context when entering a submenu and closes it on
return, so a `set theme=...` in submenu source is automatically restored when
Esc returns to the parent menu. This lets each submenu center its own item
count without changing the parent layout.
"""
from __future__ import annotations
from pathlib import Path
import argparse, re, shutil
MARK='SENREN_DYNAMIC_SUBMENU_THEME'

def brace_delta(line:str)->int:
    delta=0; quote=None; escaped=False
    for ch in line:
        if escaped: escaped=False; continue
        if ch=='\\' and quote!="'": escaped=True; continue
        if quote:
            if ch==quote: quote=None
            continue
        if ch in ("'",'"'): quote=ch; continue
        if ch=='#': break
        if ch=='{': delta+=1
        elif ch=='}': delta-=1
    return delta

def find_theme_dir(text:str)->str:
    for raw in text.splitlines():
        match=re.match(r'^\s*set\s+theme=(.+)/theme\.txt\s*$',raw)
        if match and 'senren-banka' in match.group(1):
            return match.group(1).strip('"')
    raise ValueError('Could not find the generated Senren Banka theme path in grub.cfg')

def process(text:str, theme_dir:str)->tuple[str,int]:
    lines=[ln for ln in text.splitlines(keepends=True) if MARK not in ln]
    depth=0; stack=[]; records=[]
    for i,raw in enumerate(lines):
        stripped=raw.lstrip()
        is_item=stripped.startswith('menuentry ') or stripped.startswith('submenu ')
        if is_item and stack and depth==stack[-1]['content_depth']:
            stack[-1]['count']+=1
        is_sub=stripped.startswith('submenu ')
        delta=brace_delta(raw)
        if is_sub and delta>0:
            stack.append({'line':i,'content_depth':depth+1,'count':0,'external':False})
        if stack and stripped.startswith('configfile '):
            stack[-1]['external']=True
        newdepth=depth+delta
        while stack and newdepth < stack[-1]['content_depth']:
            records.append(stack.pop())
        depth=max(0,newdepth)
    records.extend(reversed(stack))
    inserts={}
    for rec in records:
        # grub-btrfs loads its real entries from another file. Its count cannot
        # be inferred here, so keep the parent viewport instead of forcing a
        # misleading one-item layout.
        if rec['external']:
            continue
        n=max(1,min(rec['count'],8))
        opener=lines[rec['line']]
        indent=opener[:len(opener)-len(opener.lstrip())]+'  '
        inserts[rec['line']]=f'{indent}set theme="{theme_dir}/theme-count-{n}.txt" # {MARK}\n'
    out=[]
    for i,ln in enumerate(lines):
        out.append(ln)
        if i in inserts: out.append(inserts[i])
    return ''.join(out),len(inserts)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('grub_cfg',nargs='?',default='/boot/grub/grub.cfg')
    ap.add_argument('--no-backup',action='store_true')
    a=ap.parse_args(); p=Path(a.grub_cfg)
    old=p.read_text(encoding='utf-8',errors='replace')
    try:
        theme_dir=find_theme_dir(old)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    new,n=process(old,theme_dir)
    if new!=old:
        if not a.no_backup:
            bak=p.with_name(p.name+'.senren.bak')
            if not bak.exists(): shutil.copy2(p,bak)
        p.write_text(new,encoding='utf-8')
    print(f'Senren submenu layouts: {n} submenu(s) assigned count-specific themes in {p}')
if __name__=='__main__': main()
