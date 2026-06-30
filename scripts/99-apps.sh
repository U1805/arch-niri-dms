#!/bin/bash

# ==============================================================================
# 99-apps.sh - Common Applications + Post-Install User Tooling
# ============================================================================== 

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found in $SCRIPT_DIR."
    exit 1
fi

# --- [CONFIGURATION] ---
# LazyVim 硬性依赖列表
LAZYVIM_DEPS=("neovim" "ripgrep" "fd" "ttf-jetbrains-mono-nerd" "git" "lazygit")

check_root

# Ensure FZF is installed for package selection.
if ! command -v fzf &>/dev/null; then
    log "Installing dependency: fzf..."
    pacman -S --noconfirm fzf >/dev/null 2>&1
fi

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

# Helper for commands that need the user's shell environment, e.g. bun global bin.
as_user_shell() {
   -u "$TARGET_USER" -- env HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" bash -lc "$*"
}

AUR_HELPER=""
if command -v paru &>/dev/null; then
    AUR_HELPER="paru"
elif command -v yay &>/dev/null; then
    AUR_HELPER="yay"
fi

if [[ -n "$AUR_HELPER" ]]; then
    info_kv "AUR Helper" "$AUR_HELPER"
else
    warn "No AUR helper found. Repo/Flatpak installs can still run, but AUR-only items will be skipped."
fi

SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_apps"
TEMP_SUDO_GRANTED=false

ensure_temp_sudo() {
    if [[ "$TEMP_SUDO_GRANTED" == true ]]; then
        return 0
    fi

    log "Configuring temporary NOPASSWD for post-install tasks..."
    echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
    chmod 440 "$SUDO_TEMP_FILE"
    TEMP_SUDO_GRANTED=true
}

cleanup_temp_sudo() {
    if [[ -f "$SUDO_TEMP_FILE" ]]; then
        log "Revoking temporary NOPASSWD..."
        rm -f "$SUDO_TEMP_FILE"
    fi
}

trap 'echo -e "\n ${H_YELLOW}>>> Operation cancelled by user (Ctrl+C). Cleaning up...${NC}"; cleanup_temp_sudo; exit 130' INT
trap 'cleanup_temp_sudo' EXIT

# ------------------------------------------------------------------------------
# 1. List Selection & User Prompt
# ------------------------------------------------------------------------------
LIST_FILENAME="common-applist.txt"
LIST_FILE="$PARENT_DIR/$LIST_FILENAME"

REPO_APPS=()
AUR_APPS=()
FLATPAK_APPS=()
FAILED_PACKAGES=()
INSTALL_LAZYVIM=false

if [[ ! -f "$LIST_FILE" ]]; then
    warn "File $LIST_FILENAME not found. Skipping common app selection."
    SELECTED_RAW=""
elif ! grep -q -vE "^\s*#|^\s*$" "$LIST_FILE"; then
    warn "App list is empty. Skipping common app selection."
    SELECTED_RAW=""
else
    echo ""
    echo -e " Selected List: ${BOLD}$LIST_FILENAME${NC}"
    echo -e " ${H_YELLOW}>>> Do you want to CUSTOMIZE the application installation?${NC}"
    echo ""

    read -t 60 -p " Please select[Y/n]: " choice
    READ_STATUS=$?
    SELECTED_RAW=""

    # Case 1: Timeout (Auto Install ALL - Default to N)
    if [[ $READ_STATUS -ne 0 ]]; then
        echo ""
        warn "Timeout reached (60s). Auto-installing ALL applications from list..."
        SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')
    else
        # Enter defaults to Y
        choice=${choice:-Y}

        if [[ "$choice" =~ ^[nN]$ ]]; then
            log "User chose to auto-install ALL applications without customization."
            SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')
        else
            clear
            echo -e "\n Loading application list..."
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

            if [[ -z "$SELECTED_RAW" ]]; then
                log "Skipping application installation (User cancelled selection in FZF)."
            fi
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 2. Categorize Selection & Strip Prefixes (Includes LazyVim Check)
# ------------------------------------------------------------------------------
log "Processing selection..."

while IFS= read -r line; do
    raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
    [[ -z "$raw_pkg" ]] && continue

    # Check for LazyVim explicitly (case-insensitive check).
    if [[ "${raw_pkg,,}" == "lazyvim" ]]; then
        INSTALL_LAZYVIM=true
        REPO_APPS+=("${LAZYVIM_DEPS[@]}")
        info_kv "Config" "LazyVim detected" "Setup deferred to Post-Install"
        continue
    fi

    if [[ "$raw_pkg" == flatpak:* ]]; then
        clean_name="${raw_pkg#flatpak:}"
        FLATPAK_APPS+=("$clean_name")
    elif [[ "$raw_pkg" == AUR:* ]]; then
        clean_name="${raw_pkg#AUR:}"
        AUR_APPS+=("$clean_name")
    else
        REPO_APPS+=("$raw_pkg")
    fi
done <<< "$SELECTED_RAW"

info_kv "Scheduled" "Repo: ${#REPO_APPS[@]}" "AUR: ${#AUR_APPS[@]}" "Flatpak: ${#FLATPAK_APPS[@]}"

if [[ ${#REPO_APPS[@]} -gt 0 || ${#AUR_APPS[@]} -gt 0 ]]; then
    ensure_temp_sudo
fi

# ------------------------------------------------------------------------------
# 3. Install Applications
# ------------------------------------------------------------------------------

# --- A. Install Repo Apps (BATCH MODE) ---
if [[ ${#REPO_APPS[@]} -gt 0 ]]; then
    section "Step 1/3" "Official Repository Packages (Batch)"

    REPO_QUEUE=()
    for pkg in "${REPO_APPS[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            log "Skipping '$pkg' (Already installed)."
        else
            REPO_QUEUE+=("$pkg")
        fi
    done

    if [[ ${#REPO_QUEUE[@]} -gt 0 ]]; then
        info_kv "Installing" "${#REPO_QUEUE[@]} packages via Pacman/AUR helper"

        if [[ -n "$AUR_HELPER" ]]; then
            if ! exe as_user "$AUR_HELPER" -Syu --noconfirm --needed --answerdiff=None --answerclean=None "${REPO_QUEUE[@]}"; then
                error "Batch installation failed. Some repo packages might be missing."
                for pkg in "${REPO_QUEUE[@]}"; do
                    FAILED_PACKAGES+=("repo:$pkg")
                done
            else
                success "Repo batch installation completed."
            fi
        else
            if ! exe pacman -Syu --noconfirm --needed "${REPO_QUEUE[@]}"; then
                error "Batch installation failed. Some repo packages might be missing."
                for pkg in "${REPO_QUEUE[@]}"; do
                    FAILED_PACKAGES+=("repo:$pkg")
                done
            else
                success "Repo batch installation completed."
            fi
        fi
    else
        log "All Repo packages are already installed."
    fi
fi

# --- B. Install AUR Apps (INDIVIDUAL MODE + RETRY) ---
if [[ ${#AUR_APPS[@]} -gt 0 ]]; then
    section "Step 2/3" "AUR Packages"

    if [[ -z "$AUR_HELPER" ]]; then
        error "No AUR helper available. Skipping AUR packages."
        for app in "${AUR_APPS[@]}"; do
            FAILED_PACKAGES+=("aur:$app")
        done
    else
        for app in "${AUR_APPS[@]}"; do
            if pacman -Qi "$app" &>/dev/null; then
                log "Skipping '$app' (Already installed)."
                continue
            fi

            log "Installing AUR: $app ..."
            install_success=false
            max_retries=1

            for ((i = 0; i <= max_retries; i++)); do
                if [[ $i -gt 0 ]]; then
                    warn "Retry $i/$max_retries for '$app' ..."
                fi

                if as_user "$AUR_HELPER" -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$app"; then
                    install_success=true
                    success "Installed $app"
                    break
                else
                    warn "Attempt $((i + 1)) failed for $app"
                fi
            done

            if [[ "$install_success" == false ]]; then
                error "Failed to install $app after $((max_retries + 1)) attempts."
                FAILED_PACKAGES+=("aur:$app")
            fi
        done
    fi
fi

# --- C. Install Flatpak Apps (INDIVIDUAL MODE) ---
if [[ ${#FLATPAK_APPS[@]} -gt 0 ]]; then
    section "Step 3/3" "Flatpak Packages (Individual)"

    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak info "$app" &>/dev/null; then
            log "Skipping '$app' (Already installed)."
            continue
        fi

        log "Installing Flatpak: $app ..."
        if ! exe flatpak install -y flathub "$app"; then
            error "Failed to install: $app"
            FAILED_PACKAGES+=("flatpak:$app")
        else
            success "Installed $app"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 4. Environment & Additional Configs
# ------------------------------------------------------------------------------
section "Post-Install" "System & App Tweaks"

# --- Virtualization Configuration (Virt-Manager) ---
if pacman -Qi virt-manager &>/dev/null && ! systemd-detect-virt -q; then
    info_kv "Config" "Virt-Manager detected"

    # iptables-nft 和 dnsmasq 是默认 NAT 网络必须的。
    log "Installing QEMU/KVM dependencies..."
    pacman -S --noconfirm --needed qemu-full virt-manager swtpm dnsmasq virt-viewer

    # 添加用户组，需要重新登录生效。
    log "Adding $TARGET_USER to libvirt group..."
    usermod -a -G libvirt "$TARGET_USER"
    usermod -a -G kvm,input "$TARGET_USER"

    log "Enabling libvirtd service..."
    systemctl enable --now libvirtd

    log "Setting default URI to qemu:///system..."
    glib-compile-schemas /usr/share/glib-2.0/schemas/ || true
    as_user gsettings set org.virt-manager.virt-manager.connections uris "['qemu:///system']" || true
    as_user gsettings set org.virt-manager.virt-manager.connections autoconnect "['qemu:///system']" || true

    log "Starting default network..."
    sleep 3
    virsh net-start default >/dev/null 2>&1 || warn "Default network might be already active."
    virsh net-autostart default >/dev/null 2>&1 || true

    success "Virtualization (KVM) configured."
fi

# --- Wine Configuration & Fonts ---
if command -v wine &>/dev/null; then
    info_kv "Config" "Wine detected"

    log "Ensuring Wine Gecko/Mono are installed..."
    pacman -S --noconfirm --needed wine wine-gecko wine-mono

    WINE_PREFIX="$HOME_DIR/.wine"
    if [[ ! -d "$WINE_PREFIX" ]]; then
        log "Initializing wine prefix (This may take a minute)..."
        as_user env WINEPREFIX="$WINE_PREFIX" WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
        as_user env WINEPREFIX="$WINE_PREFIX" wineserver -w
    else
        log "Wine prefix already exists."
    fi

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
        log " -> $filename"
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

    log "Refreshing Wine font cache..."
    if command -v wineserver &>/dev/null; then
        as_user env WINEPREFIX="$WINE_PREFIX" wineserver -k || true
    fi

    success "Wine fonts installed and cache refresh triggered."
fi

# --- LazyVim Configuration ---
if [[ "$INSTALL_LAZYVIM" == true ]]; then
    section "Config" "Applying LazyVim Overrides"

    NVIM_CFG="$HOME_DIR/.config/nvim"
    if [[ -d "$NVIM_CFG" ]]; then
        BACKUP_PATH="$HOME_DIR/.config/nvim.old.apps.$(date +%s)"
        warn "Collision detected. Moving existing nvim config to $BACKUP_PATH"
        mv "$NVIM_CFG" "$BACKUP_PATH"
        chown -R "$TARGET_USER:" "$BACKUP_PATH"
    fi

    log "Cloning LazyVim starter..."
    if as_user git clone https://github.com/LazyVim/starter "$NVIM_CFG"; then
        rm -rf "$NVIM_CFG/.git"

        log "Applying fcitx5-remote fix to init.lua..."
        as_user bash -c "cat >> '$NVIM_CFG/init.lua'" <<'LAZYVIM_FCITX_EOF'

-- fcitx5 状态切换与恢复
local fcitx_st = ""
vim.api.nvim_create_autocmd("InsertLeave", {
  callback = function()
    fcitx_st = vim.fn.system("fcitx5-remote")
    vim.fn.jobstart("fcitx5-remote -c")
  end,
})
vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    if fcitx_st:match("2") then
      vim.fn.jobstart("fcitx5-remote -o")
    end
  end,
})
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.fn.jobstart("fcitx5-remote -c")
  end,
})
LAZYVIM_FCITX_EOF

        success "LazyVim installed (Override) with Fcitx5 fix."
    else
        error "Failed to clone LazyVim."
    fi
fi

# ==============================================================================
# 5. Rime Schema
# ==============================================================================
section "Post-Install" "Rime Schema"

RIME_DIR="$HOME_DIR/.local/share/fcitx5/rime"
RIME_CLONE="/tmp/rime-schema-$TARGET_USER"
RIME_REPO="https://gh-proxy.org/https://github.com/U1805/rime.git"

# 体积较大的语法模型 / 语言模型文件，安装阶段跳过；模型单独通过包管理器安装。
RIME_SKIP_FILES=(
    "wanxiang-lts-zh-hans.gram"
)

log "Cloning U1805/rime schema from $RIME_REPO..."
rm -rf "$RIME_CLONE"

if git clone --depth 1 --filter=blob:none --no-checkout "$RIME_REPO" "$RIME_CLONE"; then
    (
        cd "$RIME_CLONE" || exit 1

        # 使用 non-cone 模式，才能写“包含全部，但排除指定文件”的规则。
        git sparse-checkout init --no-cone

        {
            echo "/*"
            for skip_file in "${RIME_SKIP_FILES[@]}"; do
                echo "!/$skip_file"
            done
        } > .git/info/sparse-checkout

        git checkout
    )

    if [[ $? -ne 0 ]]; then
        warn "Failed to checkout U1805/rime sparse files; Rime schema will use system defaults"
    else
        as_user mkdir -p "$RIME_DIR"

        # 不覆盖已有用户词库和同步配置。
        cp -n "$RIME_CLONE"/*.yaml "$RIME_DIR/" 2>/dev/null || true
        cp -n "$RIME_CLONE"/*.txt "$RIME_DIR/" 2>/dev/null || true
        cp -n "$RIME_CLONE"/*.txt.bak "$RIME_DIR/" 2>/dev/null || true
        cp -n "$RIME_CLONE"/*.json "$RIME_DIR/" 2>/dev/null || true

        if [[ -d "$RIME_CLONE/lua" ]]; then
            cp -rn "$RIME_CLONE/lua/" "$RIME_DIR/lua/" 2>/dev/null || true
        fi

        if [[ -d "$RIME_CLONE/opencc" ]]; then
            cp -rn "$RIME_CLONE/opencc/" "$RIME_DIR/opencc/" 2>/dev/null || true
        fi

        for sub in \
            cn_dicts \
            en_dicts \
            jp_dicts \
            cn_dicts_cell \
            cn_dicts_common \
            cn_dicts_xh \
            dicts_cn \
            dicts_en \
            dicts_jp \
            custom_phrase
        do
            if [[ -d "$RIME_CLONE/$sub" ]]; then
                cp -rn "$RIME_CLONE/$sub/" "$RIME_DIR/$sub/" 2>/dev/null || true
            fi
        done

        chown -R "$TARGET_USER:" "$RIME_DIR"
        success "U1805/rime schema deployed without large grammar model"
    fi
else
    warn "Failed to clone U1805/rime; Rime schema will use system defaults"
fi

rm -rf "$RIME_CLONE"

# --- Wanxiang Rime Grammar Model ---
log "Installing Wanxiang Rime grammar model..."

RIME_GRAM_PKG="rime-wanxiang-gram-zh-hans"
RIME_GRAM_FILE="wanxiang-lts-zh-hans.gram"
GRAM_INSTALLED=false

copy_wanxiang_gram_to_user() {
    local gram_src
    gram_src="$(pacman -Ql "$RIME_GRAM_PKG" 2>/dev/null | awk -v file="$RIME_GRAM_FILE" '$0 ~ file"$" {print $2; exit}')"

    if [[ -n "$gram_src" && -f "$gram_src" ]]; then
        install -Dm644 "$gram_src" "$RIME_DIR/$RIME_GRAM_FILE"
        chown "$TARGET_USER:" "$RIME_DIR/$RIME_GRAM_FILE"
        success "Wanxiang grammar model copied to user Rime directory"
    else
        warn "$RIME_GRAM_FILE was not found in installed package files"
    fi
}

if pacman -Qi "$RIME_GRAM_PKG" >/dev/null 2>&1; then
    GRAM_INSTALLED=true
    log "Wanxiang grammar model package is already installed."
elif pacman -Si "$RIME_GRAM_PKG" >/dev/null 2>&1; then
    if pacman -S --noconfirm --needed "$RIME_GRAM_PKG"; then
        GRAM_INSTALLED=true
        success "Wanxiang grammar model installed from pacman repo: $RIME_GRAM_PKG"
    else
        warn "Failed to install $RIME_GRAM_PKG from pacman repo"
        FAILED_PACKAGES+=("repo:$RIME_GRAM_PKG")
    fi
else
    warn "$RIME_GRAM_PKG not found in pacman repos; trying AUR..."

    if [[ -n "$AUR_HELPER" ]]; then
        ensure_temp_sudo
        if as_user "$AUR_HELPER" -S --noconfirm --needed --answerdiff=None --answerclean=None "$RIME_GRAM_PKG"; then
            GRAM_INSTALLED=true
            success "Wanxiang grammar model installed from AUR: $RIME_GRAM_PKG"
        else
            warn "Failed to install $RIME_GRAM_PKG from AUR"
            FAILED_PACKAGES+=("aur:$RIME_GRAM_PKG")
        fi
    else
        warn "No AUR helper found; skipping Wanxiang grammar model"
        FAILED_PACKAGES+=("aur:$RIME_GRAM_PKG")
    fi
fi

if [[ "$GRAM_INSTALLED" == true ]]; then
    as_user mkdir -p "$RIME_DIR"
    copy_wanxiang_gram_to_user
fi

# ==============================================================================
# 6. Additional Tooling
# ==============================================================================
section "Post-Install" "Additional Tooling"

# --- pi-coding-agent ---
log "Installing pi-coding-agent (AI assistant)..."

if as_user_shell 'command -v bun >/dev/null 2>&1'; then
    if as_user_shell 'bun add -g --ignore-scripts @earendil-works/pi-coding-agent'; then
        # bun add -g installs bin symlinks to ~/.bun/bin/;
        # link into ~/.local/bin which is already in fish PATH (config.fish).
        as_user mkdir -p "$HOME_DIR/.local/bin"
        as_user ln -sf "$HOME_DIR/.bun/bin/pi" "$HOME_DIR/.local/bin/pi" 2>/dev/null || true
        success "pi-coding-agent installed"
    else
        warn "Failed to install pi-coding-agent (network issue?)"
        FAILED_PACKAGES+=("bun:@earendil-works/pi-coding-agent")
    fi
else
    warn "bun not found for $TARGET_USER; skipping pi-coding-agent"
    FAILED_PACKAGES+=("bun:@earendil-works/pi-coding-agent")
fi

# --- EasyTier (内网穿透) ---
log "Installing EasyTier (P2P VPN)..."

EASYTIER_VER="2.4.5"
EASYTIER_ARCH="x86_64"
EASYTIER_ZIP="easytier-linux-${EASYTIER_ARCH}-v${EASYTIER_VER}.zip"
EASYTIER_URL="https://gh-proxy.org/https://github.com/EasyTier/EasyTier/releases/download/v${EASYTIER_VER}/${EASYTIER_ZIP}"
EASYTIER_TMP="/tmp/easytier_install"

rm -rf "$EASYTIER_TMP"
mkdir -p "$EASYTIER_TMP"

if curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 \
    -o "$EASYTIER_TMP/$EASYTIER_ZIP" "$EASYTIER_URL"; then

    # 防止代理站返回 HTML/错误页，但 curl 仍保存成 zip 文件。
    if unzip -tq "$EASYTIER_TMP/$EASYTIER_ZIP" >/dev/null 2>&1; then
        success "EasyTier archive downloaded and verified"

        if unzip -qo "$EASYTIER_TMP/$EASYTIER_ZIP" -d "$EASYTIER_TMP"; then
            # EasyTier 的 zip 解压后可能带有子目录，所以不能只检查解压根目录。
            EASYTIER_CLI="$(find "$EASYTIER_TMP" -type f -name easytier-cli -perm /111 | head -n 1)"
            EASYTIER_CORE="$(find "$EASYTIER_TMP" -type f -name easytier-core -perm /111 | head -n 1)"

            # 某些 zip 解压后权限可能没保留 executable bit，再宽松找一次。
            [[ -z "$EASYTIER_CLI" ]] && EASYTIER_CLI="$(find "$EASYTIER_TMP" -type f -name easytier-cli | head -n 1)"
            [[ -z "$EASYTIER_CORE" ]] && EASYTIER_CORE="$(find "$EASYTIER_TMP" -type f -name easytier-core | head -n 1)"

            if [[ -n "$EASYTIER_CLI" && -n "$EASYTIER_CORE" ]]; then
                install -Dm755 "$EASYTIER_CLI" /usr/bin/easytier-cli
                install -Dm755 "$EASYTIER_CORE" /usr/bin/easytier-core

                if command -v easytier-cli >/dev/null 2>&1 && command -v easytier-core >/dev/null 2>&1; then
                    success "EasyTier v${EASYTIER_VER} installed"
                else
                    warn "EasyTier install command completed, but binaries are not found in PATH"
                    FAILED_PACKAGES+=("manual:easytier")
                fi
            else
                warn "EasyTier binaries not found in archive; expected easytier-cli and easytier-core"
                warn "Archive content preview:"
                find "$EASYTIER_TMP" -maxdepth 3 -type f | sed 's#^#  - #' | head -n 30 || true
                FAILED_PACKAGES+=("manual:easytier")
            fi
        else
            warn "Failed to extract EasyTier archive"
            FAILED_PACKAGES+=("manual:easytier")
        fi
    else
        warn "Downloaded EasyTier archive is invalid; proxy may have returned an HTML/error page"
        FAILED_PACKAGES+=("manual:easytier")
    fi
else
    warn "Failed to download EasyTier from proxy: $EASYTIER_URL"
    FAILED_PACKAGES+=("manual:easytier")
fi

rm -rf "$EASYTIER_TMP"

# --- hide desktop ---

section "Config" "Hiding useless .desktop files"
log "Hiding useless .desktop files"
run_hide_desktop_file

# ------------------------------------------------------------------------------
# 7. Generate Failure Report
# ------------------------------------------------------------------------------
cleanup_temp_sudo

if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
    DOCS_DIR="$HOME_DIR/Documents"
    REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"

    if [[ ! -d "$DOCS_DIR" ]]; then
        as_user mkdir -p "$DOCS_DIR"
    fi

    {
        echo -e "\n========================================================"
        echo -e " Installation Failure Report - $(date)"
        echo -e "========================================================"
        printf "%s\n" "${FAILED_PACKAGES[@]}"
    } >> "$REPORT_FILE"

    chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"

    echo ""
    warn "Some applications failed to install."
    warn "A report has been saved to:"
    echo -e " ${BOLD}$REPORT_FILE${NC}"
else
    success "All scheduled applications processed successfully."
fi

# Reset Trap
trap - INT
trap - EXIT

log "Module 99-apps completed."
