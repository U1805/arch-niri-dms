#!/usr/bin/env python3
from pathlib import Path
import subprocess, sys
HERE=Path(__file__).resolve().parent
for count in range(1,9):
    subprocess.run([sys.executable,str(HERE/'generate-theme.py'),str(count),'-o',str(HERE/f'theme-count-{count}.txt')],check=True)
# Safe initial default; update-layout.py replaces theme.txt after grub.cfg is generated.
(HERE/'theme.txt').write_text((HERE/'theme-count-4.txt').read_text(encoding='utf-8'),encoding='utf-8')
print('Generated count-specific theme variants 1..8; default theme.txt = 4-item layout.')
