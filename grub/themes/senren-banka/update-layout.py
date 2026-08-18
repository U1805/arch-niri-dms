#!/usr/bin/env python3
"""Update Senren＊Banka GRUB theme geometry from a generated grub.cfg.

Counts top-level menuentry/submenu blocks only, so entries nested inside an
"Advanced options" submenu do not inflate the title-screen menu height.
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def brace_delta(line: str) -> int:
    """Count { and } outside shell quotes/comments on one grub.cfg line."""
    delta = 0
    quote = None
    escaped = False
    i = 0
    while i < len(line):
        ch = line[i]
        if escaped:
            escaped = False
            i += 1
            continue
        if ch == "\\" and quote != "'":
            escaped = True
            i += 1
            continue
        if quote:
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            i += 1
            continue
        if ch == '#':
            break
        if ch == '{':
            delta += 1
        elif ch == '}':
            delta -= 1
        i += 1
    return delta


def top_level_count(text: str) -> int:
    depth = 0
    count = 0
    for raw in text.splitlines():
        line = raw.lstrip()
        # A visible top-level item starts while no enclosing { ... } block is open.
        if depth == 0 and (line.startswith('menuentry ') or line.startswith('submenu ')):
            count += 1
        depth += brace_delta(raw)
        if depth < 0:  # malformed/odd snippets: recover instead of cascading
            depth = 0
    return count


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('grub_cfg', nargs='?', default='/boot/grub/grub.cfg')
    ap.add_argument('--theme-dir', default=str(Path(__file__).resolve().parent))
    ap.add_argument('--output', default=None)
    args = ap.parse_args()

    cfg = Path(args.grub_cfg)
    theme_dir = Path(args.theme_dir)
    output = Path(args.output) if args.output else theme_dir / 'theme.txt'
    text = cfg.read_text(encoding='utf-8', errors='replace')
    count = top_level_count(text)
    if count < 1:
        print(f'error: no top-level GRUB menu entries found in {cfg}', file=sys.stderr)
        return 2

    generator = theme_dir / 'generate-theme.py'
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f'.{output.name}.', dir=output.parent)
    os.close(fd)
    try:
        subprocess.run([sys.executable, str(generator), str(count), '-o', temporary], check=True)
        os.replace(temporary, output)
        os.chmod(output, 0o644)
    finally:
        Path(temporary).unlink(missing_ok=True)
    import json
    profile = json.loads((theme_dir / '.profile.json').read_text(encoding='utf-8'))
    visible = min(count, int(profile.get('max_visible', 8)))
    print(f"Senren layout refreshed: {count} top-level items, {visible} visible at once ({profile.get('resolution','?')}, {profile.get('profile','?')}) -> {output}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
