#!/bin/bash

# ==============================================================================
# 99-apps.sh - Common Applications (FZF Menu + Split Repo/AUR + Retry Logic)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# Ensure FZF is installed
if ! command -v fzf &> /dev/null; then
    log "Installing dependency: fzf..."
    pacman -S --noconfirm fzf >/dev/null 2>&1
fi

trap 'echo -e "\n   ${H_YELLOW}>>> Operation cancelled by user (Ctrl+C). Skipping...${NC}"' INT

# ------------------------------------------------------------------------------
# 0. Identify Target User & Helper
# ------------------------------------------------------------------------------
section "Phase 5" "Common Applications"

log "Identifying target user..."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
    error "Target user invalid or home directory does not exist."
    exit 1
fi
info_kv "Target" "$TARGET_USER"

# Helper function for user commands
as_user() {
  runuser -u "$TARGET_USER" -- "$@"
}

# ------------------------------------------------------------------------------
# 1. List Selection & User Prompt
# ------------------------------------------------------------------------------
LIST_FILENAME="common-applist.txt"
LIST_FILE="$PARENT_DIR/$LIST_FILENAME"

REPO_APPS=()
FAILED_PACKAGES=()

if [ ! -f "$LIST_FILE" ]; then
    warn "File $LIST_FILENAME not found. Skipping."
    trap - INT
    exit 0
fi

if ! grep -q -vE "^\s*#|^\s*$" "$LIST_FILE"; then
    warn "App list is empty. Skipping."
    trap - INT
    exit 0
fi

echo ""
echo -e "   Selected List: ${BOLD}$LIST_FILENAME${NC}"
echo -e "   ${H_YELLOW}>>> Do you want to CUSTOMIZE the application installation?${NC}"
echo ""

read -t 60 -p "   Please select[Y/n]: " choice
READ_STATUS=$?

SELECTED_RAW=""

# Case 1: Timeout (Auto Install ALL - Default to N)
if [ $READ_STATUS -ne 0 ]; then
    echo "" 
    warn "Timeout reached (60s). Auto-installing ALL applications from list..."
    SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')

# Case 2: User Input
else
    # Enter defaults to Y
    choice=${choice:-Y}
    if [[ "$choice" =~ ^[nN]$ ]]; then
        log "User chose to auto-install ALL applications without customization."
        SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')
    else
        clear
        echo -e "\n  Loading application list..."
        
        SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | \
            sed -E 's/[[:space:]]+#/\t#/' | \
            fzf --multi \
                --layout=reverse \
                --border \
                --margin=1,2 \
                --prompt="Search App > " \
                --pointer=">>" \
                --marker="* " \
                --delimiter=$'\t' \
                --with-nth=1 \
                --bind 'load:select-all' \
                --bind 'ctrl-a:select-all,ctrl-d:deselect-all,j:down,k:up' \
                --info=inline \
                --header="[TAB] TOGGLE | [ENTER] INSTALL | [CTRL-D] DE-ALL | [CTRL-A] SE-ALL" \
                --preview "echo {} | cut -f2 -d$'\t' | sed 's/^# //'" \
                --preview-window=down:45%:wrap:border-up \
                --color=dark \
                --color=fg+:white,bg+:black \
                --color=hl:blue,hl+:blue:bold \
                --color=header:yellow:bold \
                --color=info:magenta \
                --color=prompt:cyan,pointer:cyan:bold,marker:green:bold \
                --color=spinner:yellow)
        
        clear
        
        if [ -z "$SELECTED_RAW" ]; then
            log "Skipping application installation (User cancelled selection in FZF)."
            trap - INT
            exit 0
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 2. Categorize Selection & Strip Prefixes
# ------------------------------------------------------------------------------
log "Processing selection..."

while IFS= read -r line; do
    raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
    [[ -z "$raw_pkg" ]] && continue

    REPO_APPS+=("$raw_pkg")
done <<< "$SELECTED_RAW"

info_kv "Scheduled" "Repo: ${#REPO_APPS[@]}"

# ------------------------------------------------------------------------------
#[SETUP] GLOBAL SUDO CONFIGURATION
# ------------------------------------------------------------------------------
if [ ${#REPO_APPS[@]} -gt 0 ]; then
    log "Configuring temporary NOPASSWD for installation..."
    SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_apps"
    echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
    chmod 440 "$SUDO_TEMP_FILE"
fi

# ------------------------------------------------------------------------------
# 3. Install Applications
# ------------------------------------------------------------------------------

# --- A. Install Repo Apps (BATCH MODE) ---
if [ ${#REPO_APPS[@]} -gt 0 ]; then
    section "Step 1/3" "Official Repository Packages (Batch)"
    
    REPO_QUEUE=()
    for pkg in "${REPO_APPS[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            log "Skipping '$pkg' (Already installed)."
        else
            REPO_QUEUE+=("$pkg")
        fi
    done

    if [ ${#REPO_QUEUE[@]} -gt 0 ]; then
        BATCH_LIST="${REPO_QUEUE[*]}"
        info_kv "Installing" "${#REPO_QUEUE[@]} packages via Pacman/Paru"
        
        if ! exe as_user paru -Syu --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
            error "Batch installation failed. Some repo packages might be missing."
            for pkg in "${REPO_QUEUE[@]}"; do
                FAILED_PACKAGES+=("repo:$pkg")
            done
        else
            success "Repo batch installation completed."
        fi
    else
        log "All Repo packages are already installed."
    fi
fi


# ------------------------------------------------------------------------------
# 4. Environment & Additional Configs
# ------------------------------------------------------------------------------
section "Post-Install" "System & App Tweaks"

# --- [NEW] Virtualization Configuration (Virt-Manager) ---
if pacman -Qi virt-manager &>/dev/null && ! systemd-detect-virt -q; then
  info_kv "Config" "Virt-Manager detected"
  
  # 1. 安装完整依赖
  # iptables-nft 和 dnsmasq 是默认 NAT 网络必须的
  log "Installing QEMU/KVM dependencies..."
  pacman -S --noconfirm --needed qemu-full virt-manager swtpm dnsmasq virt-viewer

  # 2. 添加用户组 (需要重新登录生效)
  log "Adding $TARGET_USER to libvirt group..."
  usermod -a -G libvirt "$TARGET_USER"
  # 同时添加 kvm 和 input 组以防万一
  usermod -a -G kvm,input "$TARGET_USER"

  # 3. 开启服务
  log "Enabling libvirtd service..."
  systemctl enable --now libvirtd

  # 4. [修复] 强制设置 virt-manager 默认连接为 QEMU/KVM
  # 解决第一次打开显示 LXC 或无法连接的问题
  log "Setting default URI to qemu:///system..."
  
  # 编译 glib schemas (防止 gsettings 报错)
  glib-compile-schemas /usr/share/glib-2.0/schemas/

  # 强制写入 Dconf 配置
  # uris: 连接列表
  # autoconnect: 自动连接的列表
  as_user gsettings set org.virt-manager.virt-manager.connections uris "['qemu:///system']"
  as_user gsettings set org.virt-manager.virt-manager.connections autoconnect "['qemu:///system']"

  # 5. 配置网络 (Default NAT)
  log "Starting default network..."
  sleep 3
  virsh net-start default >/dev/null 2>&1 || warn "Default network might be already active."
  virsh net-autostart default >/dev/null 2>&1 || true
  
  success "Virtualization (KVM) configured."
fi

# --- [NEW] Wine Configuration & Fonts ---
if command -v wine &>/dev/null; then
  info_kv "Config" "Wine detected"
  
  # 1. 安装 Gecko 和 Mono
  log "Ensuring Wine Gecko/Mono are installed..."
  pacman -S --noconfirm --needed wine wine-gecko wine-mono 

  # 2. 初始化 Wine (使用 wineboot -u 在后台运行，不弹窗)
  WINE_PREFIX="$HOME_DIR/.wine"
  if [ ! -d "$WINE_PREFIX" ]; then
    log "Initializing wine prefix (This may take a minute)..."
    # WINEDLLOVERRIDES prohibits popups
    as_user env WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
    # Wait for completion
    as_user wineserver -w
  else
    log "Wine prefix already exists."
  fi

  # 3. 下载字体
  FONT_DEST="$WINE_PREFIX/drive_c/windows/Fonts"
  FONT_URLS=(
    "https://gh-proxy.org/https://github.com/SHORiN-KiWATA/shorin-arch-setup/raw/refs/heads/main/resources/windows-sim-fonts/simfang.ttf"
    "https://gh-proxy.org/https://github.com/SHORiN-KiWATA/shorin-arch-setup/raw/refs/heads/main/resources/windows-sim-fonts/simhei.ttf"
    "https://gh-proxy.org/https://github.com/SHORiN-KiWATA/shorin-arch-setup/raw/refs/heads/main/resources/windows-sim-fonts/simkai.ttf"
    "https://gh-proxy.org/https://github.com/SHORiN-KiWATA/shorin-arch-setup/raw/refs/heads/main/resources/windows-sim-fonts/simsun.ttc"
  )

  log "Downloading Windows fonts..."
  as_user mkdir -p "$FONT_DEST"
  font_ok=true
  for url in "${FONT_URLS[@]}"; do
    filename="${url##*/}"
    log "  -> $filename"
    if curl -fsSL --retry 3 -o "$FONT_DEST/$filename" "$url"; then
      chown "$TARGET_USER:" "$FONT_DEST/$filename"
    else
      warn "Failed to download $url"
      font_ok=false
    fi
  done
  if $font_ok; then
    success "Fonts downloaded successfully."
  fi

  # 强制刷新 Wine 字体缓存 (非常重要！)
  # 字体文件放进去了，但 Wine 不一定会立刻重修构建 fntdata.dat
  # 杀死 wineserver 会强制 Wine 下次启动时重新扫描系统和本地配置
  log "Refreshing Wine font cache..."
  if command -v wineserver &> /dev/null; then
    # 必须以目标用户身份执行 wineserver -k
    as_user env WINEPREFIX="$WINE_PREFIX" wineserver -k
  fi

  success "Wine fonts installed and cache refresh triggered."
fi

# --- hide desktop ---

section "Config" "Hiding useless .desktop files"
log "Hiding useless .desktop files"
run_hide_desktop_file

# ------------------------------------------------------------------------------
# [FIX] CLEANUP GLOBAL SUDO CONFIGURATION
# ------------------------------------------------------------------------------
if [ -f "$SUDO_TEMP_FILE" ]; then
    log "Revoking temporary NOPASSWD..."
    rm -f "$SUDO_TEMP_FILE"
fi

# ------------------------------------------------------------------------------
# 5. Generate Failure Report
# ------------------------------------------------------------------------------
if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    DOCS_DIR="$HOME_DIR/Documents"
    REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
    
    if [ ! -d "$DOCS_DIR" ]; then as_user mkdir -p "$DOCS_DIR"; fi
    
    echo -e "\n========================================================" >> "$REPORT_FILE"
    echo -e " Installation Failure Report - $(date)" >> "$REPORT_FILE"
    echo -e "========================================================" >> "$REPORT_FILE"
    printf "%s\n" "${FAILED_PACKAGES[@]}" >> "$REPORT_FILE"
    
    chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
    
    echo ""
    warn "Some applications failed to install."
    warn "A report has been saved to:"
    echo -e "   ${BOLD}$REPORT_FILE${NC}"
else
    success "All scheduled applications processed successfully."
fi

# Reset Trap
trap - INT

log "Module 99-apps completed."
