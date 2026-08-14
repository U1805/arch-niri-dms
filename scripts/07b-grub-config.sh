#!/bin/bash

# 07b-grub-config.sh - 生成并验证 GRUB 启动菜单

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"
check_root

if ! command -v grub-mkconfig >/dev/null 2>&1; then
    warn "grub-mkconfig is not available. Skip GRUB boot configuration."
    exit 0
fi

section "Phase 7B" "Generate and validate the GRUB configuration"

set_grub_value() {
    local key="$1" value="$2" conf_file="/etc/default/grub" escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed 's,[\/&],\\&,g')
    if grep -q -E "^#\s*$key=" "$conf_file"; then
        exe sed -i -E "s,^#\s*$key=.*,$key=\"$escaped_value\"," "$conf_file"
    elif grep -q -E "^$key=" "$conf_file"; then
        exe sed -i -E "s,^$key=.*,$key=\"$escaped_value\"," "$conf_file"
    else
        echo "$key=\"$escaped_value\"" >> "$conf_file"
    fi
}

manage_kernel_param() {
    local action="$1" param="$2" conf_file="/etc/default/grub" line params param_key
    line=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$conf_file" || true)
    params=$(echo "$line" | sed -e 's/GRUB_CMDLINE_LINUX_DEFAULT=//' -e 's/"//g')
    if [[ "$param" == *"="* ]]; then param_key="${param%%=*}"; else param_key="$param"; fi
    params=$(echo "$params" | sed -E "s/\b${param_key}(=[^ ]*)?\b//g")
    [ "$action" == "add" ] && params="$params $param"
    params=$(echo "$params" | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    exe sed -i "s,^GRUB_CMDLINE_LINUX_DEFAULT=.*,GRUB_CMDLINE_LINUX_DEFAULT=\"$params\"," "$conf_file"
}

section "Step 1/3" "Check and back up the current configuration"

if [ ! -L /boot/grub ] || [ "$(readlink -f /boot/grub)" != "$(readlink -f /efi/grub)" ]; then
    error "/boot/grub does not point to /efi/grub. Do not change the boot configuration."
    exit 1
fi
for required_command in objdump grub-script-check; do
    command -v "$required_command" >/dev/null 2>&1 || {
        error "A required GRUB validation command is not available: $required_command."
        exit 1
    }
done

PRIMARY_KERNEL=""
for kernel_name in linux-zen linux linux-lts linux-hardened; do
    candidate_path="/efi/EFI/Linux/arch-$kernel_name.efi"
    [ -f "$candidate_path" ] || continue
    candidate_sections=$(objdump -h "$candidate_path" 2>/dev/null || true)
    candidate_complete=true
    for section_name in .linux .initrd .osrel .cmdline; do
        printf '%s\n' "$candidate_sections" | awk -v wanted="$section_name" \
            '$2 == wanted && $3 != "00000000" { found=1 } END { exit !found }' || \
            candidate_complete=false
    done
    [ "$candidate_complete" = true ] || {
        warn "Skip the incomplete $kernel_name UKI: $candidate_path."
        continue
    }
    PRIMARY_KERNEL="$kernel_name"
    UKI_PATH="$candidate_path"
    UKI_SECTIONS="$candidate_sections"
    break
done
[ -n "$PRIMARY_KERNEL" ] || {
    error "No supported UKI was found. Expected linux-zen, linux, linux-lts, or linux-hardened."
    exit 1
}
success "Use $PRIMARY_KERNEL as the primary GRUB entry."
for package_generator in /etc/grub.d/10_linux /etc/grub.d/30_uefi-firmware; do
    [ -f "$package_generator" ] || { error "A GRUB generator is not available: $package_generator."; exit 1; }
done

GRUB_BACKUP_ROOT="/var/backups/arch-niri-dms/grub"
exe install -d -m 0700 "$GRUB_BACKUP_ROOT"
GRUB_BACKUP_DIR=$(mktemp -d "$GRUB_BACKUP_ROOT/$(date +%Y%m%d_%H%M%S).XXXXXX")
exe cp -a /etc/grub.d "$GRUB_BACKUP_DIR/grub.d"
exe cp -a /etc/default/grub "$GRUB_BACKUP_DIR/grub.default"
[ ! -f /boot/grub/grub.cfg ] || exe cp -a /boot/grub/grub.cfg "$GRUB_BACKUP_DIR/grub.cfg"

GRUB_CANDIDATE=""
GRUB_NEW_CONFIG="/boot/grub/grub.cfg.arch-niri-dms-new"
GRUB_COMMITTED=false
restore_grub_state() {
    rm -f /etc/grub.d/09_arch_niri_dms_uki /etc/grub.d/30_uefi_firmware_icon \
        /etc/grub.d/11_arch_advanced /etc/grub.d/31_arch_advanced \
        /etc/grub.d/32_uefi_firmware_icon \
        /etc/grub.d/42_uefi_firmware_icon
    cp -a "$GRUB_BACKUP_DIR/grub.d/." /etc/grub.d/
    cp -a "$GRUB_BACKUP_DIR/grub.default" /etc/default/grub
}
cleanup_grub_attempt() {
    [[ -z "$GRUB_CANDIDATE" ]] || rm -f -- "$GRUB_CANDIDATE"
    if [[ "$GRUB_COMMITTED" != true ]]; then
        rm -f -- "$GRUB_NEW_CONFIG"
        restore_grub_state
    fi
}
trap cleanup_grub_attempt EXIT
trap 'exit 130' INT TERM

section "Step 2/3" "Configure generators, parameters, and menu entries"

set_grub_value "GRUB_DEFAULT" "saved"
set_grub_value "GRUB_SAVEDEFAULT" "true"
exe install -m 0755 "$PARENT_DIR/grub/config/09_arch_niri_dms_uki" /etc/grub.d/09_arch_niri_dms_uki
exe rm -f /etc/grub.d/31_arch_advanced
exe install -m 0755 "$PARENT_DIR/grub/config/11_arch_advanced" /etc/grub.d/11_arch_advanced
exe rm -f /etc/grub.d/30_uefi_firmware_icon
exe rm -f /etc/grub.d/32_uefi_firmware_icon
exe rm -f /etc/grub.d/42_uefi_firmware_icon
exe install -m 0755 "$PARENT_DIR/grub/config/32_uefi_firmware_icon" /etc/grub.d/32_uefi_firmware_icon
exe chmod a-x /etc/grub.d/10_linux /etc/grub.d/30_uefi-firmware
[ ! -e /etc/grub.d/15_uki ] || exe chmod a-x /etc/grub.d/15_uki

# grub-btrfs does not assign a class to its top-level submenu. GRUB themes use
# this class to select submenu.png, so add it without changing snapshot entries.
if grep -q "^submenu '\${submenuname}' \${protection_authorized_users}\${unrestricted_access_submenu}{" \
    /etc/grub.d/41_snapshots-btrfs 2>/dev/null; then
    exe sed -i \
        "s|^submenu '\${submenuname}' \${protection_authorized_users}\${unrestricted_access_submenu}{|submenu '\${submenuname}' --class submenu --class snapshots \${protection_authorized_users}\${unrestricted_access_submenu}{|" \
        /etc/grub.d/41_snapshots-btrfs
fi

manage_kernel_param "remove" "quiet"
manage_kernel_param "remove" "splash"
manage_kernel_param "add" "loglevel=5"
manage_kernel_param "add" "nowatchdog"
CPU_VENDOR=$(LC_ALL=C lscpu 2>/dev/null | awk '/Vendor ID:/ {print $3}' || true)
if [ "$CPU_VENDOR" == "GenuineIntel" ]; then
    manage_kernel_param "add" "modprobe.blacklist=iTCO_wdt"
elif [ "$CPU_VENDOR" == "AuthenticAMD" ]; then
    manage_kernel_param "add" "modprobe.blacklist=sp5100_tco"
fi

exe cp /etc/grub.d/40_custom /etc/grub.d/99_custom
echo 'menuentry "Reboot" --class restart {reboot}' >> /etc/grub.d/99_custom
echo 'menuentry "Shutdown" --class shutdown {halt}' >> /etc/grub.d/99_custom

section "Step 3/3" "Generate and validate a candidate configuration"

GRUB_CANDIDATE=$(mktemp /tmp/arch-niri-dms-grub.XXXXXX.cfg)
[ -w /efi/grub ] || exe mount -o remount,rw /efi
if ! grub-mkconfig -o "$GRUB_CANDIDATE"; then
    restore_grub_state; rm -f "$GRUB_CANDIDATE"; exit 1
fi

validation_failed=false
grub-script-check "$GRUB_CANDIDATE" || validation_failed=true
PRIMARY_ENTRY_ID=${PRIMARY_KERNEL#linux-}
[ "$PRIMARY_KERNEL" != linux ] || PRIMARY_ENTRY_ID=linux
grep -q "menuentry 'Arch Linux' --class arch.*--id 'arch-uki-$PRIMARY_ENTRY_ID'" "$GRUB_CANDIDATE" || validation_failed=true
grep -q "chainloader /EFI/Linux/arch-$PRIMARY_KERNEL.efi" "$GRUB_CANDIDATE" || validation_failed=true
grep -q "menuentry 'UEFI Firmware Settings' --class efi" "$GRUB_CANDIDATE" || validation_failed=true
grep -q '^menuentry "Reboot" --class restart' "$GRUB_CANDIDATE" || validation_failed=true
grep -q '^menuentry "Shutdown" --class shutdown' "$GRUB_CANDIDATE" || validation_failed=true
grep -qE 'gnulinux-simple-|^[[:space:]]*uki[[:space:]]*$' "$GRUB_CANDIDATE" && validation_failed=true

menu_line() { grep -n -m1 "$1" "$GRUB_CANDIDATE" | cut -d: -f1; }
ARCH_LINE=$(menu_line "menuentry 'Arch Linux' --class arch.*arch-uki-$PRIMARY_ENTRY_ID")
WINDOWS_LINE=$(menu_line "menuentry 'Windows Boot Manager" || true)
UEFI_LINE=$(menu_line "menuentry 'UEFI Firmware Settings'" || true)
ADVANCED_LINE=$(menu_line "^submenu 'Advanced options for Arch Linux'" || true)
SNAPSHOTS_LINE=$(menu_line "^submenu 'Arch Linux snapshots'" || true)
REBOOT_LINE=$(menu_line '^menuentry "Reboot"' || true)
SHUTDOWN_LINE=$(menu_line '^menuentry "Shutdown"' || true)

if [ -z "$ARCH_LINE" ] || [ -z "$UEFI_LINE" ] || [ -z "$REBOOT_LINE" ] || [ -z "$SHUTDOWN_LINE" ]; then
    validation_failed=true
else
    PREVIOUS_LINE=$ARCH_LINE
    if [ -n "$ADVANCED_LINE" ]; then
        [ "$PREVIOUS_LINE" -lt "$ADVANCED_LINE" ] || validation_failed=true
        PREVIOUS_LINE=$ADVANCED_LINE
    fi
    if [ -n "$WINDOWS_LINE" ]; then
        [ "$PREVIOUS_LINE" -lt "$WINDOWS_LINE" ] || validation_failed=true
        PREVIOUS_LINE=$WINDOWS_LINE
    else
        log "No Windows entry was detected. Keep the single-system menu."
    fi
    [ "$PREVIOUS_LINE" -lt "$UEFI_LINE" ] || validation_failed=true
    PREVIOUS_LINE=$UEFI_LINE
    if [ -n "$SNAPSHOTS_LINE" ]; then
        [ "$PREVIOUS_LINE" -lt "$SNAPSHOTS_LINE" ] || validation_failed=true
        PREVIOUS_LINE=$SNAPSHOTS_LINE
    fi
    [ "$PREVIOUS_LINE" -lt "$REBOOT_LINE" ] || validation_failed=true
    [ "$REBOOT_LINE" -lt "$SHUTDOWN_LINE" ] || validation_failed=true
fi

if [ "$validation_failed" = true ]; then
    error "The candidate GRUB configuration failed validation."
    restore_grub_state; rm -f "$GRUB_CANDIDATE"; exit 1
fi
exe install -m 0600 "$GRUB_CANDIDATE" "$GRUB_NEW_CONFIG"
rm -f "$GRUB_CANDIDATE"
GRUB_CANDIDATE=""
if ! grub-script-check "$GRUB_NEW_CONFIG"; then
    rm -f "$GRUB_NEW_CONFIG"; restore_grub_state; exit 1
fi
exe mv -f "$GRUB_NEW_CONFIG" /boot/grub/grub.cfg
GRUB_COMMITTED=true
success "The validated GRUB configuration is installed."
info_kv "GRUB backup" "$GRUB_BACKUP_DIR" ""
log "Module 07b is complete."
