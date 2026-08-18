#!/usr/bin/env python3
"""Optionally add cosmetic class hints for Arch kernel variants.

GRUB's generated Arch entries normally share distro classes, so gfxmenu cannot
otherwise choose a distinct icon for linux-zen vs linux-lts.  This script only
adds --class hints to menuentry declaration lines; it does not alter commands
inside an entry. It is idempotent and writes a .senren.bak backup before the
first change.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import shutil


def add_priority_class(line: str, klass: str) -> tuple[str, bool]:
    token = f'--class {klass}'
    if token in line:
        return line, False
    marker = ' --class '
    if marker in line:
        return line.replace(marker, f' --class {klass}{marker}', 1), True
    brace = line.rfind('{')
    if brace >= 0:
        return line[:brace].rstrip() + f' --class {klass} ' + line[brace:], True
    return line, False


def process(text: str) -> tuple[str, int]:
    changed = 0
    out = []
    for raw in text.splitlines(keepends=True):
        line = raw
        stripped = raw.lstrip()
        if stripped.startswith('submenu ') and 'advanced options for arch linux' in stripped.lower():
            line, did = add_priority_class(line, 'advanced')
            changed += int(did)
        elif stripped.startswith('menuentry '):
            low = stripped.lower()
            klass = None
            if 'fallback initramfs' in low or 'recovery mode' in low:
                klass = 'recovery'
            elif 'linux-zen' in low or ' linux zen' in low:
                klass = 'linux-zen'
            elif 'linux-lts' in low or ' linux lts' in low or 'lts uki' in low:
                klass = 'linux-lts'
            elif 'arch linux' in low and 'with linux' in low:
                klass = 'kernel'
            if klass:
                line, did = add_priority_class(line, klass)
                changed += int(did)
        out.append(line)
    return ''.join(out), changed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('grub_cfg', nargs='?', default='/boot/grub/grub.cfg')
    ap.add_argument('--no-backup', action='store_true')
    args = ap.parse_args()
    p = Path(args.grub_cfg)
    old = p.read_text(encoding='utf-8', errors='replace')
    new, count = process(old)
    if count:
        if not args.no_backup:
            bak = p.with_name(p.name + '.senren.bak')
            if not bak.exists():
                shutil.copy2(p, bak)
        p.write_text(new, encoding='utf-8')
    print(f'Arch kernel class hints: {count} line(s) changed in {p}')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
