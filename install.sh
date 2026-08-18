#!/bin/bash

export SHELL=$(command -v bash)

# ==============================================================================
# Shorin Arch 主安装程序（v1.2）
# ==============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_FILE="$BASE_DIR/.install_progress"
PROXY_RUNTIME_DIR=""
TEMP_SUDO_FILE="/etc/sudoers.d/99-shorin-installer-temp"

# 加载公共函数。
if [ -f "$SCRIPTS_DIR/00-utils.sh" ]; then
    source "$SCRIPTS_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh is not available."
    exit 1
fi

# 脚本退出时删除临时文件。
cleanup_on_exit() {
    if [[ -f "$TEMP_SUDO_FILE" ]]; then
        rm -f -- "$TEMP_SUDO_FILE"
    fi
    if [[ -n "$PROXY_RUNTIME_DIR" && -d "$PROXY_RUNTIME_DIR" ]]; then
        rm -rf -- "$PROXY_RUNTIME_DIR"
    fi
    rm -f "/tmp/shorin_install_user"
    tput cnorm
}
trap cleanup_on_exit EXIT

# 运行环境
export DEBUG=${DEBUG:-0}
export CN_MIRROR=${CN_MIRROR:-0}
export DESKTOP_ENV="shorindms"
export DESKTOP_LABEL="Shorin_DMS_Niri"

# 此分支只提供一条安装路径。
# 显式列出模块顺序，不要依赖文件名排序。
MODULES=(
    "01-btrfs.sh"
    "02-fonts.sh"
    "03-driver.sh"
    "04-dualboot-fix.sh"
    "05a-dms-niri.sh"
    "05b-dms-tools.sh"
    "06-config.sh"
    "07a-grub-theme.sh"
    "07b-grub-config.sh"
    "99a-apps.sh"
    "99b-apps.sh"
)

check_root
chmod +x "$SCRIPTS_DIR"/*.sh "$BASE_DIR/github-wrapper"/*.sh

# PATH 中的包装脚本使 makepkg 使用临时配置。
# GitHub HTTP(S) 和 Git clone 均先直连，再依次回退到两个代理。
# 签名 URL 和认证 URL 始终直连。脚本不修改持久配置。
PROXY_RUNTIME_DIR="$(mktemp -d /tmp/shorin-github-proxy.XXXXXX)"
chmod 0755 "$PROXY_RUNTIME_DIR"
install -d -m 0755 "$PROXY_RUNTIME_DIR/bin"
cp /etc/makepkg.conf "$PROXY_RUNTIME_DIR/makepkg.conf"
cat >>"$PROXY_RUNTIME_DIR/makepkg.conf" <<EOF

# arch-niri-dms 使用的临时 GitHub 下载配置。
DLAGENTS=(
  'file::/usr/bin/curl -qgC - -o %o %u'
  'ftp::/usr/bin/curl -qgfC - --ftp-pasv --retry 3 --retry-delay 3 -o %o %u'
  'http::/usr/bin/curl -qgb "" -fLC - --retry 3 --retry-delay 3 -o %o %u'
  'https::$BASE_DIR/github-wrapper/curl-github-wrapper.sh %o %u'
  'rsync::/usr/bin/rsync --no-motd -z %u %o'
  'scp::/usr/bin/scp -C %u %o'
)
EOF
chmod 0644 "$PROXY_RUNTIME_DIR/makepkg.conf"
cat >"$PROXY_RUNTIME_DIR/bin/makepkg" <<EOF
#!/usr/bin/env bash
export PATH="$PROXY_RUNTIME_DIR/bin:\$PATH"
exec /usr/bin/makepkg --config "$PROXY_RUNTIME_DIR/makepkg.conf" "\$@"
EOF
chmod 0755 "$PROXY_RUNTIME_DIR/bin/makepkg"
cp "$BASE_DIR/github-wrapper/git-github-wrapper.sh" "$PROXY_RUNTIME_DIR/bin/git"
chmod 0755 "$PROXY_RUNTIME_DIR/bin/git"
export PATH="$PROXY_RUNTIME_DIR/bin:$PATH"
export SHORIN_MAKEPKG_WRAPPER="$PROXY_RUNTIME_DIR/bin/makepkg"
export SHORIN_GITHUB_CURL_WRAPPER="$BASE_DIR/github-wrapper/curl-github-wrapper.sh"
export SHORIN_GITHUB_GIT_WRAPPER="$BASE_DIR/github-wrapper/git-github-wrapper.sh"

# 标题图案
banner1() {
cat << "EOF"
  ██████  ██   ██  ██████  ███████ ██ ███    ██
  ██      ██   ██ ██    ██ ██   ██   ██ ██  ██
  ███████ ███████ ██    ██ ██████  ██ ██ ██  ██
       ██ ██   ██ ██    ██ ██   ██ ██ ██  ██ ██
  ██████  ██   ██  ██████  ██   ██ ██ ██   ████
EOF
}

show_banner() {
    clear
    echo -e "${H_CYAN}"
    banner1
    echo -e "${NC}"
    echo -e "${DIM}   :: Arch Linux Installer ::${NC}"
    echo -e ""
}

sys_dashboard() {
    echo -e "${H_BLUE}╔════ SYSTEM INFORMATION ══════════════════════════════╗${NC}"
    echo -e "${H_BLUE}║${NC} ${BOLD}Kernel${NC}   : $(uname -r)"
    echo -e "${H_BLUE}║${NC} ${BOLD}User${NC}     : $(whoami)"
    echo -e "${H_BLUE}║${NC} ${BOLD}Desktop${NC}  : ${H_CYAN}${DESKTOP_LABEL}${NC}"
    echo -e "${H_BLUE}║${NC} ${BOLD}Modules${NC}  : ${#MODULES[@]}"
    
    if [ "$CN_MIRROR" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_YELLOW}China mirrors (manual)${NC}"
    elif [ "$DEBUG" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_RED}China mirrors (debug)${NC}"
    else
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : Global mirrors"
    fi
    
    if [ -f "$STATE_FILE" ]; then
        done_count=$(wc -l < "$STATE_FILE")
        echo -e "${H_BLUE}║${NC} ${BOLD}Progress${NC} : Resume after $done_count modules"
    fi
    echo -e "${H_BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 主流程

clear
show_banner
sys_dashboard

if [ ! -f "$STATE_FILE" ]; then touch "$STATE_FILE"; fi

TOTAL_STEPS=${#MODULES[@]}
CURRENT_STEP=0

log "Initialize the installer."
sleep 0.5

# 基础工具和开发环境
section "Preflight" "Update the system and install base tools"

# Archinstall may configure mkinitcpio to write unified kernel images directly
# to the ESP. Keep kernel updates independent of /efi by restoring the native
# GRUB layout under /boot before the first full system upgrade.
log "Verify mkinitcpio uses the native GRUB /boot layout."
CONFIGURED_KERNELS=()
REBUILD_INITRAMFS=false
for preset in /etc/mkinitcpio.d/linux*.preset; do
    [ -f "$preset" ] || continue
    kernel_name=${preset##*/}
    kernel_name=${kernel_name%.preset}
    CONFIGURED_KERNELS+=("$kernel_name")

    if ! grep -Eq "^PRESETS=.*'default'.*'fallback'" "$preset" ||
       ! grep -Fxq "default_image=\"/boot/initramfs-$kernel_name.img\"" "$preset" ||
       ! grep -Fxq "fallback_image=\"/boot/initramfs-$kernel_name-fallback.img\"" "$preset"; then
        log "Convert the $kernel_name preset from UKI-only or incomplete output."
        if ! exe sed -i -E \
            -e '/^PRESETS=/d' \
            -e '/^default_(uki|image|options)=/d' \
            -e '/^fallback_(uki|image|options)=/d' \
            "$preset"; then
            error "Failed to configure the mkinitcpio preset: $preset"
            exit 1
        fi
        if ! {
            printf '\n'
            printf "PRESETS=('default' 'fallback')\n"
            printf 'default_image="/boot/initramfs-%s.img"\n' "$kernel_name"
            printf 'fallback_image="/boot/initramfs-%s-fallback.img"\n' "$kernel_name"
            printf 'fallback_options="-S autodetect"\n'
        } >> "$preset"; then
            error "Failed to finish the mkinitcpio preset: $preset"
            exit 1
        fi
        REBUILD_INITRAMFS=true
    fi

    for image in "/boot/vmlinuz-$kernel_name" \
        "/boot/initramfs-$kernel_name.img" \
        "/boot/initramfs-$kernel_name-fallback.img"; do
        [ -s "$image" ] || REBUILD_INITRAMFS=true
    done
done

if (( ${#CONFIGURED_KERNELS[@]} == 0 )); then
    error "No Linux mkinitcpio preset was found. Install a kernel before running this installer."
    exit 1
fi

if [[ "$REBUILD_INITRAMFS" == true ]]; then
    if ! exe mkinitcpio -P; then
        error "The native initramfs images could not be generated. Do not update the system."
        exit 1
    fi
fi

for kernel_name in "${CONFIGURED_KERNELS[@]}"; do
    for image in "/boot/vmlinuz-$kernel_name" \
        "/boot/initramfs-$kernel_name.img" \
        "/boot/initramfs-$kernel_name-fallback.img"; do
        if [ ! -s "$image" ]; then
            error "A required native GRUB boot file is missing: $image"
            exit 1
        fi
    done
done

log "Synchronize package databases and update the system."
if ! exe pacman -Syu --noconfirm; then
    error "The system update failed. Check the network and repository configuration."
    exit 1
fi

BASE_TOOLS=(bash curl wget tar unzip git jq vim)
log "Install base tools."
exe pacman -S --noconfirm --needed "${BASE_TOOLS[@]}"

if grep -q '^EDITOR=' /etc/environment; then
    exe sed -i 's/^EDITOR=.*/EDITOR=vim/' /etc/environment
else
    echo 'EDITOR=vim' >> /etc/environment
fi
export EDITOR=vim

DEV_ENV_PKGS=(nodejs bun uv rust go)
log "Install development tools."
exe pacman -S --noconfirm --needed "${DEV_ENV_PKGS[@]}"

# README 中的 Arch 基础安装阶段已经为中国网络配置镜像。
# 主安装程序不再重复询问或运行 Reflector，避免增加等待和下载时间。
section "Preflight" "Use the existing China mirror configuration"
log "Assume the installation is running in China. Keep the current pacman mirror list."

# 更新密钥环。
section "Preflight" "Update the keyring"

exe pacman -S --noconfirm --needed archlinux-keyring

# 启用 32 位软件仓库。
section "Preflight" "Enable the multilib repository"

if grep -q "^\[multilib\]" /etc/pacman.conf; then
    success "[multilib] is enabled."
else
    log "Enable [multilib]."
    exe sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
    success "[multilib] is enabled."
fi

# 更新系统。
section "Preflight" "Update the system"
log "Check for system updates."

if exe pacman -Syu --noconfirm; then
    success "The system is updated."
else
    error "The system update failed. Check the network connection."
    exit 1
fi

# 依次运行安装模块。
for module in "${MODULES[@]}"; do
    [[ -z "$module" ]] && continue
    
    CURRENT_STEP=$((CURRENT_STEP + 1))
    script_path="$SCRIPTS_DIR/$module"
    
    if [ ! -f "$script_path" ]; then
        error "Module not found: $module."
        continue
    fi
    
    if grep -q "^${module}$" "$STATE_FILE"; then
        echo -e "   ${H_GREEN}✔${NC} Module ${BOLD}${module}${NC} is complete."
        echo -e "   ${DIM}   Skip it. Delete .install_progress to run it again.${NC}"
        continue
    fi
    
    section "Module ${CURRENT_STEP}/${TOTAL_STEPS}" "$module"
    
    bash "$script_path"
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "$module" >> "$STATE_FILE"
        success "Module $module is complete."
    elif [ $exit_code -eq 130 ]; then
        echo ""
        warn "The user interrupted the script with Ctrl+C."
        log "Exit without rollback. Run the installer again to resume."
        exit 130
    else
        write_log "FATAL" "Module $module failed with exit code $exit_code."
        error "The module failed."
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# 清理安装文件。
# ------------------------------------------------------------------------------
section "Completion" "Clean installation files"

log "Clean the pacman cache."
exe pacman -Sc --noconfirm

for dir in /var/cache/pacman/pkg/download-*/; do
    if [ -d "$dir" ]; then
        echo "Remove the residual directory: $dir."
        rm -rf "$dir"
    fi
done

rm -f "/tmp/shorin_install_verify.list"

if [[ -f "$TEMP_SUDO_FILE" ]]; then
    log "Remove the temporary NOPASSWD rule."
    rm -f -- "$TEMP_SUDO_FILE"
    success "The temporary NOPASSWD rule is removed."
fi

# 显示安装结果。
clear
show_banner
echo -e "${H_GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${H_GREEN}║                INSTALLATION COMPLETE                 ║${NC}"
echo -e "${H_GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

if [ -f "$STATE_FILE" ]; then rm "$STATE_FILE"; fi

log "Save the log."
if [ -f "/tmp/shorin_install_user" ]; then
    FINAL_USER=$(cat /tmp/shorin_install_user)
else
    FINAL_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
fi

if [ -n "$FINAL_USER" ]; then
    FINAL_DOCS="/home/$FINAL_USER/Documents"
    mkdir -p "$FINAL_DOCS"
    if [ -f "${TEMP_LOG_FILE:-/tmp/shorin.log}" ]; then
        cp "${TEMP_LOG_FILE:-/tmp/shorin.log}" "$FINAL_DOCS/log-arch-niri-dms.txt"
        chown -R "$FINAL_USER:$FINAL_USER" "$FINAL_DOCS"
        echo -e "   ${H_BLUE}●${NC} Log file: ${BOLD}$FINAL_DOCS/log-arch-niri-dms.txt${NC}"
    fi
fi

echo ""
echo -e "${H_YELLOW}The installation is complete. The system did not restart.${NC}"
echo -e "${H_YELLOW}Review the GRUB validation log. Restart the system when it is safe.${NC}"
