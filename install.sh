#!/bin/bash

export SHELL=$(command -v bash)

# ==============================================================================
# Shorin Arch 主安装程序（v1.2）
# ==============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_FILE="$BASE_DIR/.install_progress"
GITHUB_PROXY_PREFIX="https://gh-proxy.org/"
PROXY_RUNTIME_DIR=""
PROXY_GIT_CONFIG_INDEX=""
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

# 在本次安装中临时加速 GitHub 下载。
# Git 在用户配置之外读取这些环境变量。
# 子 Shell、runuser 和 paru 继承这些变量。此配置不修改用户的 Git 配置。
PROXY_GIT_CONFIG_INDEX="${GIT_CONFIG_COUNT:-0}"
export GIT_CONFIG_COUNT=$((PROXY_GIT_CONFIG_INDEX + 1))
export "GIT_CONFIG_KEY_${PROXY_GIT_CONFIG_INDEX}=url.${GITHUB_PROXY_PREFIX}https://github.com/.insteadOf"
export "GIT_CONFIG_VALUE_${PROXY_GIT_CONFIG_INDEX}=https://github.com/"

# PATH 中的包装脚本使 makepkg 使用临时配置。
# 包装脚本按 GitHub 域名和请求类型选择下载路径。
# 内容下载优先使用代理，API 请求优先直连。每条公开路径均有备用路径。
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
exec /usr/bin/makepkg --config "$PROXY_RUNTIME_DIR/makepkg.conf" "\$@"
EOF
chmod 0755 "$PROXY_RUNTIME_DIR/bin/makepkg"
export PATH="$PROXY_RUNTIME_DIR/bin:$PATH"
export SHORIN_MAKEPKG_WRAPPER="$PROXY_RUNTIME_DIR/bin/makepkg"

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

# 根据安装状态更新镜像列表。
section "Preflight" "Update the mirror list"

if grep -q "^REFLECTOR_DONE$" "$STATE_FILE"; then
    echo -e "   ${H_GREEN}✔${NC} The mirror list is current."
    echo -e "   ${DIM}   Skip Reflector in resume mode.${NC}"
else
    CURRENT_TZ=$(readlink -f /etc/localtime)
    REFLECTOR_ARGS="--protocol https -a 12 -f 10 --sort rate --save /etc/pacman.d/mirrorlist --verbose"
    
    REFLECTOR_SUCCESS=0
    if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
        echo ""
        echo -e "${H_YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${H_YELLOW}║  Time zone: Asia/Shanghai                                        ║${NC}"
        echo -e "${H_YELLOW}║  Reflector can be slow in China.                                 ║${NC}"
        echo -e "${H_YELLOW}║  Update mirrors with Reflector?                                  ║${NC}"
        echo -e "${H_YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -t 60 -p "$(echo -e "   ${H_CYAN}Run Reflector? [y/N]. Default after 60 seconds: N: ${NC}")" choice
        if [ $? -ne 0 ]; then echo ""; fi
        choice=${choice:-N}
        
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            log "Check Reflector."
            if exe pacman -S --noconfirm --needed reflector; then
                log "Find China mirrors with Reflector."
                if exe reflector $REFLECTOR_ARGS -c China; then
                    success "The mirror list is updated."
                    REFLECTOR_SUCCESS=1
                else
                    warn "The China mirror update failed. Try the 30 latest global mirrors."
                    if exe reflector $REFLECTOR_ARGS --latest 30; then
                        success "The mirror list is updated."
                        REFLECTOR_SUCCESS=1
                    else
                        warn "Reflector failed. Use the current mirrors."
                    fi
                fi
            else
                warn "Reflector installation failed. Use the current mirrors."
            fi
        else
            log "Skip the mirror update."
        fi
    else
        echo ""
        echo -e "${H_CYAN}The time zone is outside China. A Reflector update is recommended.${NC}"
        read -t 60 -p "$(echo -e "   ${H_CYAN}Run Reflector? [Y/n]. Default after 60 seconds: Y: ${NC}")" choice
        if [ $? -ne 0 ]; then echo ""; fi
        choice=${choice:-Y}
        
        if [[ ! "$choice" =~ ^[Nn]$ ]]; then
            log "Check Reflector."
            if exe pacman -S --noconfirm --needed reflector; then
                log "Detect the country."
                COUNTRY_CODE=$(curl -s --max-time 2 https://ipinfo.io/country)
                
                if [ -n "$COUNTRY_CODE" ]; then
                    info_kv "Country" "$COUNTRY_CODE" "(detected)"
                    log "Find mirrors for $COUNTRY_CODE with Reflector."
                    if exe reflector $REFLECTOR_ARGS -c "$COUNTRY_CODE"; then
                        success "The mirror list is updated."
                        REFLECTOR_SUCCESS=1
                    else
                        warn "The local mirror update failed. Try the 30 latest global mirrors."
                        if exe reflector $REFLECTOR_ARGS --latest 30; then
                            success "The mirror list is updated."
                            REFLECTOR_SUCCESS=1
                        else
                            warn "Reflector failed. Use the current mirrors."
                        fi
                    fi
                else
                    warn "Country detection failed. Try the 30 latest global mirrors."
                    if exe reflector $REFLECTOR_ARGS --latest 30; then
                        success "The mirror list is updated."
                        REFLECTOR_SUCCESS=1
                    else
                        warn "Reflector failed. Use the current mirrors."
                    fi
                fi
            else
                warn "Reflector installation failed. Use the current mirrors."
            fi
        else
            log "Skip the mirror update."
        fi
    fi
    
    if [ "$REFLECTOR_SUCCESS" -eq 1 ]; then
        echo "REFLECTOR_DONE" >> "$STATE_FILE"
    fi
fi

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
