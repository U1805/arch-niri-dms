Senren＊Banka GRUB Theme v0.8.0-dev — theme internals
=====================================================

This directory is integrated by scripts/07a-grub-theme.sh. The repository keeps
the source artwork and generators; resolution-specific images, icons, layouts,
and PF2 files are generated transactionally under /usr/share/grub/themes.

Generation order:
  1. configure-resolution.py WIDTHxHEIGHT
  2. build-layout-variants.py
  3. build-fonts.py
  4. scripts/07b-grub-config.sh generates a candidate grub.cfg
  5. update-layout.py and the cosmetic class/layout helpers process the candidate
  6. grub-script-check validates it before the active grub.cfg is replaced

Profiles:
  16:9      full-screen
  16:10     bottom-aligned 16:9 artwork, white above
  ultrawide centered 16:9 artwork, black pillarbox

Font:
  Gentium Book Bold revision 7.000 only. Font binaries are not distributed
  inside this package; build-fonts.py creates PF2 locally from the pinned face.

The 3:2 profile intentionally keeps the upstream centered letterbox fallback.

Selected state:
  no horizontal selection line; red-brown selected text only.

Rendering layers:
  icon/decorative class layer and main text only. Both the pale outline and the
  dark shadow are intentionally omitted to minimize GRUB software rendering
  work while navigating the menu.

Menu icons:
  unified Elegant GRUB icon language, warm brown, no pale circular tiles,
  no original game menu icons.
