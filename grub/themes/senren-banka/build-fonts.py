#!/usr/bin/env python3
"""Generate the pinned Gentium Book 7.000 PF2 files at the current resolution profile."""
from __future__ import annotations
from pathlib import Path
import json, shutil, subprocess, sys
HERE=Path(__file__).resolve().parent
PROFILE=HERE/'.profile.json'
if not PROFILE.exists(): raise SystemExit('Run configure-resolution.py WIDTHxHEIGHT first')
p=json.loads(PROFILE.read_text(encoding='utf-8'))

def find_grub_mkfont():
    for name in ('grub-mkfont','grub2-mkfont'):
        x=shutil.which(name)
        if x:return x
    raise SystemExit('grub-mkfont/grub2-mkfont not found')

def source_font():
    fc=shutil.which('fc-match')
    if not fc: raise SystemExit('fc-match not found (install fontconfig)')
    out=subprocess.check_output([fc,'-f','%{family}\n%{style}\n%{file}\n','Gentium Book:style=Bold'],text=True).splitlines()
    if len(out)<3: raise SystemExit('Could not resolve Gentium Book Bold')
    family,style,path=out[:3]
    if 'Gentium Book' not in family or 'Bold' not in style or not Path(path).is_file():
        raise SystemExit('Pinned font Gentium Book Bold is missing. Arch: sudo pacman -S ttf-gentium-book')
    from fontTools.ttLib import TTFont
    revision=TTFont(path,lazy=True)['head'].fontRevision
    if abs(float(revision)-7.0)>0.0005:
        raise SystemExit(f'Required Gentium Book revision 7.000; found {revision:.3f} at {path}')
    print(f'Pinned font OK: {family} {style}, revision {revision:.3f}: {path}')
    return path

def make_blank_ttf(path:Path):
    from fontTools.fontBuilder import FontBuilder
    from fontTools.pens.ttGlyphPen import TTGlyphPen
    ranges=[(0x20,0x024F),(0x0370,0x052F),(0x2000,0x206F),(0x3000,0x30FF),(0x4E00,0x9FFF)]
    cps=[cp for lo,hi in ranges for cp in range(lo,hi+1)]
    names={cp:f'u{cp:04X}' for cp in cps}; order=['.notdef']+[names[cp] for cp in cps]
    fb=FontBuilder(1000,isTTF=True); fb.setupGlyphOrder(order); fb.setupCharacterMap({cp:names[cp] for cp in cps})
    glyph=TTGlyphPen(None).glyph(); fb.setupGlyf({g:glyph for g in order}); fb.setupHorizontalMetrics({g:(0,0) for g in order})
    fb.setupHorizontalHeader(ascent=800,descent=-200); fb.setupMaxp(); fb.setupNameTable({'familyName':'GRUB Blank','styleName':'Regular','uniqueFontIdentifier':'GRUBBlank-Regular','fullName':'GRUB Blank Regular','psName':'GRUBBlank-Regular'}); fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200); fb.setupPost(); fb.save(path)

def patch_blank(path:Path,size:int):
    data=bytearray(path.read_bytes()); metric=max(4,round(size/2))
    for tag,value in ((b'MAXW',metric),(b'MAXH',metric),(b'ASCE',metric),(b'DESC',1)):
        pos=data.find(tag)
        if pos<0 or int.from_bytes(data[pos+4:pos+8],'big')!=2: raise SystemExit(f'Unexpected PF2 structure: {tag!r}')
        data[pos+8:pos+10]=value.to_bytes(2,'big')
    path.write_bytes(data)

def run_mkfont(args:list[str])->int:
    proc=subprocess.run(args,text=True,capture_output=True)
    ignored=0; remaining=[]
    for line in proc.stderr.splitlines():
        if line.startswith('WARNING: unsupported font feature parameters:'):
            ignored+=1
        else:
            remaining.append(line)
    if remaining:
        print('\n'.join(remaining),file=sys.stderr)
    if proc.returncode:
        raise subprocess.CalledProcessError(proc.returncode,args,proc.stdout,proc.stderr)
    return ignored

def main():
    mk=find_grub_mkfont(); src=source_font(); main=int(p['font_main']); msg=int(p['font_message']); blank=int(p['blank_size'])
    ignored=0
    for f in HERE.glob('*.pf2'): f.unlink()
    ignored+=run_mkfont([mk,'-n','Senren Menu','-s',str(main),'-o',str(HERE/'SenrenMenuMain.pf2'),src])
    ignored+=run_mkfont([mk,'-n','Senren Menu','-s',str(msg),'-o',str(HERE/'SenrenMenuMessage.pf2'),src])
    tmp=HERE/'.senren-blank.ttf'
    try:
        make_blank_ttf(tmp); out=HERE/'GRUBBlank.pf2'; ignored+=run_mkfont([mk,'-n','GRUB Blank','-s',str(blank),'-o',str(out),str(tmp)]); patch_blank(out,blank)
    finally: tmp.unlink(missing_ok=True)
    if ignored:
        print(f'Ignored {ignored} unsupported advanced OpenType feature parameter warning(s); GRUB does not use them.')
    print(f'PF2 built for {p["resolution"]}: menu={main}px, message={msg}px, blank={blank}px')
if __name__=='__main__': main()
