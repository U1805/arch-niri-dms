#!/bin/bash

# 07b-grub-config.sh - 使用发行版提供的生成器生成并验证 GRUB 配置

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"
check_root

if ! command -v grub-mkconfig >/dev/null 2>&1; then
    warn "grub-mkconfig is not available. Skip GRUB boot configuration."
    exit 0
fi

section "Phase 7B" "Generate and validate the native GRUB configuration"

set_grub_value() {
    local key="$1" value="$2" config=/etc/default/grub escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed 's,[/&],\\&,g')
    if grep -qE "^[#[:space:]]*${key}=" "$config"; then
        exe sed -i -E "s|^[#[:space:]]*${key}=.*|${key}=\"${escaped_value}\"|" "$config"
    else
        printf '%s="%s"\n' "$key" "$value" >> "$config"
    fi
}

section "Step 1/3" "Check and back up the current configuration"

for required_command in grub-script-check; do
    command -v "$required_command" >/dev/null 2>&1 || {
        error "A required GRUB validation command is not available: $required_command."
        exit 1
    }
done

if ! mountpoint -q /efi || [ "$(findmnt -no FSTYPE /efi 2>/dev/null)" != "vfat" ]; then
    error "/efi is not a mounted FAT EFI system partition."
    exit 1
fi
if ! touch /efi/.arch-niri-dms-write-test 2>/dev/null; then
    error "/efi is not writable. Repair the EFI system partition before generating GRUB."
    exit 1
fi
rm -f /efi/.arch-niri-dms-write-test

if [ ! -L /boot/grub ] || [ "$(readlink -f /boot/grub)" != "$(readlink -f /efi/grub)" ]; then
    error "/boot/grub does not point to /efi/grub. Do not change the boot configuration."
    exit 1
fi

GRUB_BACKUP_ROOT="/var/backups/arch-niri-dms/grub"
exe install -d -m 0700 "$GRUB_BACKUP_ROOT"
GRUB_BACKUP_DIR=$(mktemp -d "$GRUB_BACKUP_ROOT/$(date +%Y%m%d_%H%M%S).XXXXXX")
exe cp -a /etc/grub.d "$GRUB_BACKUP_DIR/grub.d"
exe cp -a /etc/default/grub "$GRUB_BACKUP_DIR/grub.default"
[ ! -f /boot/grub/grub.cfg ] || exe cp -a /boot/grub/grub.cfg "$GRUB_BACKUP_DIR/grub.cfg"

GRUB_CANDIDATE=""
SNAPSHOT_CANDIDATE=""
CLASS_CANDIDATE=""
GRUB_NEW_CONFIG="/boot/grub/grub.cfg.arch-niri-dms-new"
GRUB_COMMITTED=false
restore_grub_state() {
    cp -a "$GRUB_BACKUP_DIR/grub.d/." /etc/grub.d/
    cp -a "$GRUB_BACKUP_DIR/grub.default" /etc/default/grub
}
cleanup_grub_attempt() {
    [[ -z "$GRUB_CANDIDATE" ]] || rm -f -- "$GRUB_CANDIDATE"
    [[ -z "$SNAPSHOT_CANDIDATE" ]] || rm -f -- "$SNAPSHOT_CANDIDATE"
    [[ -z "$CLASS_CANDIDATE" ]] || rm -f -- "$CLASS_CANDIDATE"
    if [[ "$GRUB_COMMITTED" != true ]]; then
        rm -f -- "$GRUB_NEW_CONFIG"
        restore_grub_state
    fi
}
trap cleanup_grub_attempt EXIT
trap 'exit 130' INT TERM

section "Step 2/3" "Verify the distribution GRUB generators"

set_grub_value GRUB_DEFAULT saved
set_grub_value GRUB_SAVEDEFAULT true

for generator in /etc/grub.d/10_linux /etc/grub.d/30_uefi-firmware; do
    [ -x "$generator" ] || {
        error "A distribution GRUB generator is missing or not executable: $generator"
        exit 1
    }
done

# Add the project power actions after all native generators. Their 99_ prefix
# does not reorder any distribution menu entry.
exe cp /etc/grub.d/40_custom /etc/grub.d/99_custom
echo 'menuentry "Reboot" --class restart {reboot}' >> /etc/grub.d/99_custom
echo 'menuentry "Shutdown" --class shutdown {halt}' >> /etc/grub.d/99_custom

section "Step 3/3" "Generate and validate a candidate configuration"

GRUB_CANDIDATE=$(mktemp /tmp/arch-niri-dms-grub.XXXXXX.cfg)
if ! grub-mkconfig -o "$GRUB_CANDIDATE"; then
    restore_grub_state
    rm -f "$GRUB_CANDIDATE"
    exit 1
fi

# grub-btrfs normally locates its external menu through ${prefix}. With this
# project's /boot/grub -> /efi/grub layout, some firmware GRUB builds do not
# resolve that existence check at menu load time. Keep the upstream menu at
# its generated position, but resolve only its external file through the ESP
# UUID. This does not add, remove, rename, or reorder menu entries.
if [ -x /etc/grub.d/41_snapshots-btrfs ]; then
    if [ ! -s /boot/grub/grub-btrfs.cfg ] || \
       ! grub-script-check /boot/grub/grub-btrfs.cfg; then
        error "The generated grub-btrfs snapshot menu is missing or invalid."
        restore_grub_state
        rm -f "$GRUB_CANDIDATE"
        exit 1
    fi
    ESP_UUID=$(findmnt -no UUID /efi 2>/dev/null)
    [ -n "$ESP_UUID" ] || {
        error "The EFI system partition UUID is unavailable."
        restore_grub_state
        rm -f "$GRUB_CANDIDATE"
        exit 1
    }
    SNAPSHOT_CANDIDATE=$(mktemp /tmp/arch-niri-dms-snapshots.XXXXXX.cfg)
    if ! awk -v esp_uuid="$ESP_UUID" '
        /^### BEGIN \/etc\/grub.d\/41_snapshots-btrfs ###$/ {
            print
            print "submenu \047Arch Linux snapshots\047 --class archive --class submenu {"
            print "    insmod part_gpt"
            print "    insmod fat"
            print "    search --no-floppy --fs-uuid --set=root " esp_uuid
            print "    configfile /grub/grub-btrfs.cfg"
            print "}"
            replacing=1
            next
        }
        replacing && /^### END \/etc\/grub.d\/41_snapshots-btrfs ###$/ {
            replacing=0
            print
            next
        }
        !replacing { print }
    ' "$GRUB_CANDIDATE" > "$SNAPSHOT_CANDIDATE"; then
        error "The Snapshot path could not be integrated into the GRUB candidate."
        restore_grub_state
        exit 1
    fi
    if ! mv -f "$SNAPSHOT_CANDIDATE" "$GRUB_CANDIDATE"; then
        error "The Snapshot-integrated GRUB candidate could not be committed."
        restore_grub_state
        exit 1
    fi
    SNAPSHOT_CANDIDATE=""
fi

# The distribution generators currently omit visual classes from the Advanced
# and UEFI entries. Add metadata only to the generated candidate, anchored by
# their stable entry IDs. This leaves package-managed generators, menu order,
# commands, and saved entry IDs unchanged. Snapshot is annotated above while
# its ESP path is integrated.
CLASS_CANDIDATE=$(mktemp /tmp/arch-niri-dms-grub-classes.XXXXXX.cfg)
if ! awk '
    /gnulinux-advanced-/ && !/--class advanced([[:space:]]|$)/ {
        sub(/[[:space:]]+\$menuentry_id_option/,
            " --class advanced --class submenu $menuentry_id_option")
    }
    /uefi-firmware/ && !/--class uefi([[:space:]]|$)/ {
        sub(/[[:space:]]+\$menuentry_id_option/,
            " --class uefi --class firmware $menuentry_id_option")
    }
    { print }
' "$GRUB_CANDIDATE" > "$CLASS_CANDIDATE"; then
    error "Visual classes could not be added to the GRUB candidate."
    restore_grub_state
    exit 1
fi
if ! mv -f "$CLASS_CANDIDATE" "$GRUB_CANDIDATE"; then
    error "The class-annotated GRUB candidate could not be committed."
    restore_grub_state
    exit 1
fi
CLASS_CANDIDATE=""

# 07a initially installs the safe four-item Senren layout. Refresh only its
# geometry after the final annotated menu count is known.
ACTIVE_THEME=$(sed -n -E \
    's|^[[:space:]]*GRUB_THEME="?([^"[:space:]]+)"?.*$|\1|p' \
    /etc/default/grub | head -n 1)
if [[ "$ACTIVE_THEME" == */senren-banka/theme.txt ]]; then
    SENREN_THEME_DIR=${ACTIVE_THEME%/theme.txt}
    if [ ! -f "$SENREN_THEME_DIR/update-layout.py" ]; then
        error "The Senren Banka layout helper is missing: $SENREN_THEME_DIR/update-layout.py"
        restore_grub_state
        exit 1
    fi
    if ! exe python3 "$SENREN_THEME_DIR/update-layout.py" "$GRUB_CANDIDATE" \
        --theme-dir "$SENREN_THEME_DIR"; then
        error "The Senren Banka menu geometry could not be refreshed."
        restore_grub_state
        exit 1
    fi
    if grep -qE '^[[:space:]]*icon_(width|height)[[:space:]]*=[[:space:]]*0([[:space:]]|$)' \
        "$ACTIVE_THEME"; then
        error "The Senren Banka theme contains a zero-sized icon dimension."
        restore_grub_state
        exit 1
    fi
    if grep -qE '^[[:space:]]*desktop-image-scale-method:[[:space:]]*"?stretch"?' \
        "$ACTIVE_THEME"; then
        error "The fixed-size Senren Banka background still requests runtime stretching."
        restore_grub_state
        exit 1
    fi
fi

validation_failed=false
grub-script-check "$GRUB_CANDIDATE" || validation_failed=true
grep -qE "^[[:space:]]*(linux|linuxefi)[[:space:]].*vmlinuz-linux-(zen|lts)" \
    "$GRUB_CANDIDATE" || validation_failed=true
grep -qE "^[[:space:]]*(initrd|initrdefi)[[:space:]].*initramfs-linux-(zen|lts)\.img" \
    "$GRUB_CANDIDATE" || validation_failed=true
grep -q "^submenu 'Advanced options for Arch Linux'" "$GRUB_CANDIDATE" || validation_failed=true
grep -qE "^submenu .*--class advanced --class submenu .*gnulinux-advanced-" \
    "$GRUB_CANDIDATE" || validation_failed=true
grep -qE "^[[:space:]]*menuentry .*--class uefi --class firmware .*uefi-firmware" \
    "$GRUB_CANDIDATE" || validation_failed=true
if grep -q 'chainloader /EFI/Linux/arch-linux-' "$GRUB_CANDIDATE"; then
    validation_failed=true
fi
grep -q '^menuentry "Reboot" --class restart {reboot}' "$GRUB_CANDIDATE" || \
    validation_failed=true
grep -q '^menuentry "Shutdown" --class shutdown {halt}' "$GRUB_CANDIDATE" || \
    validation_failed=true
if [ -x /etc/grub.d/41_snapshots-btrfs ]; then
    grep -q 'grub-btrfs.cfg' "$GRUB_CANDIDATE" || validation_failed=true
    grep -q "search --no-floppy --fs-uuid --set=root $ESP_UUID" \
        "$GRUB_CANDIDATE" || validation_failed=true
    grep -q 'configfile /grub/grub-btrfs.cfg' \
        "$GRUB_CANDIDATE" || validation_failed=true
    grep -q "^submenu 'Arch Linux snapshots' --class archive --class submenu" \
        "$GRUB_CANDIDATE" || validation_failed=true
fi

if [ "$validation_failed" = true ]; then
    error "The native GRUB candidate failed validation."
    restore_grub_state
    rm -f "$GRUB_CANDIDATE"
    exit 1
fi

exe install -m 0600 "$GRUB_CANDIDATE" "$GRUB_NEW_CONFIG"
rm -f "$GRUB_CANDIDATE"
GRUB_CANDIDATE=""
if ! grub-script-check "$GRUB_NEW_CONFIG"; then
    rm -f "$GRUB_NEW_CONFIG"
    restore_grub_state
    exit 1
fi
exe mv -f "$GRUB_NEW_CONFIG" /boot/grub/grub.cfg
GRUB_COMMITTED=true

success "The native GRUB configuration is installed."
info_kv "GRUB backup" "$GRUB_BACKUP_DIR" ""
log "Module 07b is complete."
