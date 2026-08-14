#!/usr/bin/env bash

# ==============================================================================
# 99b-apps.sh - 配置条件软件包和外部资源
# ==============================================================================

apply_user_desktop_settings() {
  mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" \
    "$HOME/.local/share/themes" "$HOME/.local/bin"

  touch "$HOME/.config/gtk-3.0/dank-colors.css" "$HOME/.config/gtk-4.0/dank-colors.css"
  touch "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
  grep -q 'dank-colors.css' "$HOME/.config/gtk-3.0/gtk.css" || \
    echo '@import url("dank-colors.css");' >>"$HOME/.config/gtk-3.0/gtk.css"
  grep -q 'dank-colors.css' "$HOME/.config/gtk-4.0/gtk.css" || \
    echo '@import url("dank-colors.css");' >>"$HOME/.config/gtk-4.0/gtk.css"

  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true
  fi

  if command -v flatpak >/dev/null 2>&1; then
    flatpak override --user --filesystem=xdg-data/themes
    flatpak override --user --filesystem="$HOME/.themes"
    flatpak override --user --filesystem=xdg-config/gtk-4.0
    flatpak override --user --filesystem=xdg-config/gtk-3.0
    flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    flatpak override --user --filesystem=xdg-config/fontconfig
  fi

  if [[ -L "$HOME/.local/share/themes" ]]; then
    rm -f "$HOME/.local/share/themes"
    mkdir -p "$HOME/.local/share/themes"
  fi
  rm -rf "$HOME/.local/share/themes/gtk-3.0" "$HOME/.local/share/themes/gtk-4.0" \
    "$HOME/.local/share/themes/index.theme"
  for theme in adw-gtk3 adw-gtk3-dark; do
    if [[ -d "/usr/share/themes/$theme" ]]; then
      mkdir -p "$HOME/.local/share/themes/$theme"
      cp -au "/usr/share/themes/$theme"/. "$HOME/.local/share/themes/$theme/"
    fi
  done

  command -v kitty >/dev/null 2>&1 && ln -sfn /usr/bin/kitty "$HOME/.local/bin/xterm"
}

if [[ "${1:-}" == "--user-desktop-settings" ]]; then
  apply_user_desktop_settings
  exit
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
GITHUB_CURL_WRAPPER="${SHORIN_GITHUB_CURL_WRAPPER:-$PARENT_DIR/github-wrapper/curl-github-wrapper.sh}"
GITHUB_GIT_WRAPPER="${SHORIN_GITHUB_GIT_WRAPPER:-$PARENT_DIR/github-wrapper/git-github-wrapper.sh}"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
  source "$SCRIPT_DIR/00-utils.sh"
else
  echo "Error: 00-utils.sh is not available in $SCRIPT_DIR."
  exit 1
fi

# 配置

check_root

section "Phase 5" "Configure installed applications"

log "Identify the target user."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
  error "The target user is not valid, or the home directory does not exist."
  exit 1
fi
info_kv "Target user" "$TARGET_USER"

RIME_CLONE=""
EASYTIER_TMP=""
OCR_TMP=""
ACTIVE_DOWNLOAD_PART=""
XVFB_STATE_DIR=""
XVFB_TEMP_PACKAGES=()

cleanup_temporary_xvfb() {
  if [[ ${#XVFB_TEMP_PACKAGES[@]} -eq 0 ]]; then
    return 0
  fi

  log "Remove packages introduced for the temporary Xvfb session."
  if pacman -Rns --noconfirm "${XVFB_TEMP_PACKAGES[@]}"; then
    XVFB_TEMP_PACKAGES=()
    return 0
  fi

  warn "The temporary Xvfb packages could not be removed automatically."
  return 1
}

cleanup_app_temporary_files() {
  cleanup_temporary_xvfb || true
  [[ -z "$RIME_CLONE" ]] || rm -rf -- "$RIME_CLONE"
  [[ -z "$EASYTIER_TMP" ]] || rm -rf -- "$EASYTIER_TMP"
  [[ -z "$OCR_TMP" ]] || rm -rf -- "$OCR_TMP"
  [[ -z "$ACTIVE_DOWNLOAD_PART" ]] || rm -f -- "$ACTIVE_DOWNLOAD_PART"
  [[ -z "$XVFB_STATE_DIR" ]] || rm -rf -- "$XVFB_STATE_DIR"
}
trap cleanup_app_temporary_files EXIT
trap 'exit 130' INT TERM

as_user() {
  runuser -u "$TARGET_USER" -- "$@"
}

as_user_shell() {
  runuser -u "$TARGET_USER" -- env HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" bash -lc "$*"
}

hide_desktop_file() {
  local source_file="$1"
  local filename
  local user_dir="$HOME_DIR/.local/share/applications"
  local target_file

  if [[ ! -f "$source_file" ]]; then
    return 1
  fi

  filename=$(basename "$source_file")
  target_file="$user_dir/$filename"
  mkdir -p "$user_dir"

  # 根据 Desktop Entry 规范，同名用户条目中的 Hidden=true 会隐藏系统条目。
  # 不要复制完整的系统文件。软件包更新后，副本中的元数据会过期。
  # 如果在文件末尾追加 NoDisplay，该键可能进入 Desktop Action 组。
  printf '[Desktop Entry]\nHidden=true\n' >"$target_file"
  chown "$TARGET_USER:" "$target_file"
}

run_hide_desktop_file() {
  local hidden_count=0
  local skipped_count=0
  local apps_to_hide=(
    # 依赖项安装的发现和采集工具。
    "avahi-discover.desktop"
    "qv4l2.desktop"
    "qvidcap.desktop"
    "bssh.desktop"
    "bvnc.desktop"

    # Fcitx 运行和迁移工具。保留常用配置工具。
    "org.fcitx.Fcitx5.desktop"
    "org.fcitx.fcitx5-migrator.desktop"
    "kbd-layout-viewer5.desktop"

    # 不需要出现在图形菜单中的命令行和后端程序。
    "yazi.desktop"
    "btop.desktop"
    "nvtop.desktop"
    "mpv.desktop"

    # Thunar 和构建依赖项带来的次要工具。
    "thunar-settings.desktop"
    "thunar-bulk-rename.desktop"
    "thunar-volman-settings.desktop"
    "xfce4-about.desktop"
    "cmake-gui.desktop"

    # 间接安装的 GNOME 和硬件管理程序。
    "org.freedesktop.MalcontentControl.desktop"
    "org.gnome.Nautilus.desktop"
    "lstopo.desktop"
  )

  log "Hide auxiliary desktop entries for $TARGET_USER."

  for app in "${apps_to_hide[@]}"; do
    if hide_desktop_file "/usr/share/applications/$app"; then
      hidden_count=$((hidden_count + 1))
    else
      skipped_count=$((skipped_count + 1))
    fi
  done

  success "Hidden entries: $hidden_count. Entries not found: $skipped_count."
}

FAILED_PACKAGES=()

section "Post-install" "Configure the system and applications"

# 配置 Virt-Manager 虚拟化。
if pacman -Qi virt-manager &>/dev/null && ! systemd-detect-virt -q; then
  info_kv "Configuration" "Virt-Manager detected"

  # iptables-nft 和 dnsmasq 是默认 NAT 网络必须的。
  log "Install QEMU and KVM dependencies."
  pacman -S --noconfirm --needed qemu-full virt-manager swtpm dnsmasq virt-viewer

  # 添加用户组，需要重新登录生效。
  log "Add $TARGET_USER to the libvirt group."
  usermod -a -G libvirt "$TARGET_USER"
  usermod -a -G kvm,input "$TARGET_USER"

  log "Enable the libvirtd service."
  systemctl enable --now libvirtd

  log "Set the default URI to qemu:///system."
  glib-compile-schemas /usr/share/glib-2.0/schemas/ || true
  as_user gsettings set org.virt-manager.virt-manager.connections uris "['qemu:///system']" || true
  as_user gsettings set org.virt-manager.virt-manager.connections autoconnect "['qemu:///system']" || true

  log "Start the default virtual network."
  sleep 3
  virsh net-start default >/dev/null 2>&1 || warn "The default virtual network might already be active."
  virsh net-autostart default >/dev/null 2>&1 || true

  success "KVM virtualization is configured."
fi

# 配置 Wine 和字体。
if command -v wine &>/dev/null; then
  info_kv "Configuration" "Wine detected"

  log "Check Wine Gecko and Mono."
  pacman -S --noconfirm --needed wine wine-gecko wine-mono

  WINE_PREFIX="$HOME_DIR/.wine"
  WINE_MARKER="$WINE_PREFIX/.arch-niri-dms-initialized"
  WINE_PREFIX_CREATED=false
  WINE_READY=false
  if [[ -f "$WINE_MARKER" ]]; then
    log "The Wine prefix is already initialized."
    WINE_READY=true
  else
    [[ -d "$WINE_PREFIX" ]] || WINE_PREFIX_CREATED=true
    WINEBOOT_SUCCESS=false
    XVFB_AVAILABLE=false

    if pacman -Qq xorg-server-xvfb >/dev/null 2>&1; then
      log "Use the installed Xvfb package for Wine initialization."
      XVFB_AVAILABLE=true
    else
      log "Temporarily install Xvfb for headless Wine initialization."
      XVFB_STATE_DIR=$(mktemp -d /tmp/arch-niri-dms-xvfb.XXXXXX)
      pacman -Qq | LC_ALL=C sort >"$XVFB_STATE_DIR/packages.before"

      if pacman -S --noconfirm --needed xorg-server-xvfb; then
        XVFB_AVAILABLE=true
      else
        warn "The temporary Xvfb installation failed."
      fi

      pacman -Qq | LC_ALL=C sort >"$XVFB_STATE_DIR/packages.after"
      mapfile -t XVFB_TEMP_PACKAGES < <(
        comm -13 "$XVFB_STATE_DIR/packages.before" "$XVFB_STATE_DIR/packages.after"
      )
    fi

    if [[ "$XVFB_AVAILABLE" == true ]] && ! command -v xvfb-run >/dev/null 2>&1; then
      warn "xorg-server-xvfb is installed, but xvfb-run is unavailable."
      XVFB_AVAILABLE=false
    fi

    if [[ "$XVFB_AVAILABLE" == true ]]; then
      log "Initialize or repair the Wine prefix in a temporary Xvfb display."
      if as_user env \
          HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
          WINEPREFIX="$WINE_PREFIX" WINEDLLOVERRIDES="mscoree,mshtml=" \
          xvfb-run -a -s "-screen 0 1024x768x24" \
          bash -c 'wineboot -u && wineserver -w'; then
        WINEBOOT_SUCCESS=true
      fi
    fi

    if ! cleanup_temporary_xvfb; then
      FAILED_PACKAGES+=("cleanup:xorg-server-xvfb")
    fi
    [[ -z "$XVFB_STATE_DIR" ]] || rm -rf -- "$XVFB_STATE_DIR"
    XVFB_STATE_DIR=""

    if [[ "$WINEBOOT_SUCCESS" == true ]]; then
      touch "$WINE_MARKER"
      chown "$TARGET_USER:" "$WINE_MARKER"
      WINE_READY=true
    else
      if [[ "$WINE_PREFIX_CREATED" == true ]]; then
        rm -rf -- "$WINE_PREFIX"
        warn "Wine prefix initialization failed. Remove the newly created incomplete prefix."
      else
        warn "Wine prefix initialization failed. Keep the existing prefix unchanged."
      fi
      FAILED_PACKAGES+=("config:wine-prefix")
    fi
  fi

  if [[ "$WINE_READY" == true ]]; then
    FONT_DEST="$WINE_PREFIX/drive_c/windows/Fonts"
  FONT_URLS=(
    "https://github.com/SHORiN-KiWATA/shorin-arch-setup/raw/refs/heads/main/resources/windows-sim-fonts/simfang.ttf"
    "https://github.com/SHORiN-KiWATA/shorin-arch-setup/raw/refs/heads/main/resources/windows-sim-fonts/simhei.ttf"
    "https://github.com/SHORiN-KiWATA/shorin-arch-setup/raw/refs/heads/main/resources/windows-sim-fonts/simkai.ttf"
    "https://github.com/SHORiN-KiWATA/shorin-arch-setup/raw/refs/heads/main/resources/windows-sim-fonts/simsun.ttc"
  )

  log "Download Windows fonts."
  as_user mkdir -p "$FONT_DEST"
  font_ok=true

  for url in "${FONT_URLS[@]}"; do
    filename="${url##*/}"
    font_target="$FONT_DEST/$filename"
    font_part="$font_target.part"
    log " -> $filename"
    if [[ -s "$font_target" ]]; then
      log "$filename is already installed."
      continue
    fi
    ACTIVE_DOWNLOAD_PART="$font_part"
    rm -f -- "$font_part"
    if "$GITHUB_CURL_WRAPPER" "$font_part" "$url"; then
      mv -f -- "$font_part" "$font_target"
      ACTIVE_DOWNLOAD_PART=""
      chown "$TARGET_USER:" "$font_target"
    else
      rm -f -- "$font_part"
      ACTIVE_DOWNLOAD_PART=""
      warn "The download failed: $url."
      font_ok=false
    fi
  done

  if $font_ok; then
    success "The Windows fonts are downloaded."
  fi

  log "Refresh the Wine font cache."
  if command -v wineserver &>/dev/null; then
    as_user env WINEPREFIX="$WINE_PREFIX" wineserver -k || true
  fi

    if $font_ok; then
      success "The Wine fonts are installed. The font cache is refreshed."
    fi
  fi
fi

# ==============================================================================
# 5. Rime Schema
# ==============================================================================
section "Post-install" "Configure the Rime schema"

RIME_DIR="$HOME_DIR/.local/share/fcitx5/rime"
RIME_REPO="https://github.com/U1805/rime.git"
WANXIANG_URL="https://cnb.cool/amzxyz/rime-wanxiang/-/releases/download/model/wanxiang-lts-zh-hans.gram"
RIME_MARKER="$RIME_DIR/.arch-niri-dms-installed"

if [[ -f "$RIME_MARKER" && -s "$RIME_DIR/wanxiang-lts-zh-hans.gram" ]]; then
  success "The U1805/rime schema and grammar model are already installed."
else
  RIME_CLONE=$(mktemp -d "/tmp/rime-schema-$TARGET_USER.XXXXXX")
  log "Clone the U1805/rime schema from $RIME_REPO."

  if "$GITHUB_GIT_WRAPPER" clone --depth 1 --filter=blob:none \
      "$RIME_REPO" "$RIME_CLONE/source"; then
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 \
      -o "$RIME_CLONE/wanxiang-lts-zh-hans.gram.part" "$WANXIANG_URL"; then
      mv "$RIME_CLONE/wanxiang-lts-zh-hans.gram.part" \
        "$RIME_CLONE/source/wanxiang-lts-zh-hans.gram"
      success "The grammar model is downloaded."
    else
      rm -f -- "$RIME_CLONE/wanxiang-lts-zh-hans.gram.part"
      warn "The Wanxiang grammar model download failed. Keep the current Rime directory unchanged."
      FAILED_PACKAGES+=("manual:wanxiang-lts-zh-hans.gram")
    fi

    if [[ -s "$RIME_CLONE/source/wanxiang-lts-zh-hans.gram" ]]; then
      as_user mkdir -p "$RIME_DIR"
      # 仅部署运行数据。不要将仓库元数据、文档和维护脚本部署到 Rime 目录。
      for runtime_dir in dicts lua opencc; do
        if [[ -d "$RIME_CLONE/source/$runtime_dir" ]]; then
          cp -a "$RIME_CLONE/source/$runtime_dir" "$RIME_DIR/"
        fi
      done
      find "$RIME_CLONE/source" -maxdepth 1 -type f \
        \( -name '*.yaml' -o -name '*.txt' -o -name '*.gram' \) \
        -exec cp -a -t "$RIME_DIR" -- {} +
      touch "$RIME_MARKER"
      chown -R "$TARGET_USER:" "$RIME_DIR"
      success "The U1805/rime schema is deployed."
    fi
  else
    warn "The U1805/rime clone failed. Keep the current Rime directory unchanged."
  fi
fi

[[ -z "$RIME_CLONE" ]] || rm -rf -- "$RIME_CLONE"
RIME_CLONE=""

# ==============================================================================
# 6. Additional Tooling
# ==============================================================================
section "Post-install" "Install additional tools"

# --- mark-shot ocr ---
log "Install mark-shot OCR."
OCR_VENV="$HOME_DIR/.local/share/mark-shot/ocr-venv"
if [[ -x "$OCR_VENV/bin/python" ]] && as_user "$OCR_VENV/bin/python" -c 'import rapidocr, onnxruntime' 2>/dev/null; then
  success "mark-shot OCR is already installed."
else
  OCR_PARENT="$HOME_DIR/.local/share/mark-shot"
  as_user mkdir -p "$OCR_PARENT"
  OCR_TMP=$(runuser -u "$TARGET_USER" -- mktemp -d "$OCR_PARENT/ocr-venv.new.XXXXXX")
  if as_user uv venv "$OCR_TMP" && \
     as_user uv pip install --python "$OCR_TMP/bin/python" \
       --default-index https://pypi.tuna.tsinghua.edu.cn/simple \
       -U pip rapidocr onnxruntime && \
     as_user "$OCR_TMP/bin/python" -c 'import rapidocr, onnxruntime'; then
    rm -rf -- "$OCR_VENV"
    mv "$OCR_TMP" "$OCR_VENV"
    OCR_TMP=""
    chown -R "$TARGET_USER:" "$OCR_VENV"
    success "mark-shot OCR is installed."
  else
    rm -rf -- "$OCR_TMP"
    OCR_TMP=""
    warn "mark-shot OCR installation failed. Keep the previous environment unchanged."
    FAILED_PACKAGES+=("uv:mark-shot-ocr")
  fi
fi

# --- pi-coding-agent ---
log "Install pi-coding-agent."

if [[ -x "$HOME_DIR/.local/bin/pi" ]]; then
  success "pi-coding-agent is already installed."
elif as_user_shell 'command -v bun >/dev/null 2>&1'; then
  if as_user_shell 'bun add -g --ignore-scripts --registry=https://registry.npmmirror.com @earendil-works/pi-coding-agent'; then
    # bun add -g 在 ~/.bun/bin 中创建程序链接。
    # 再链接到 fish PATH 已包含的 ~/.local/bin。
    as_user mkdir -p "$HOME_DIR/.local/bin"
    as_user ln -sf "$HOME_DIR/.bun/bin/pi" "$HOME_DIR/.local/bin/pi" 2>/dev/null || true
    success "pi-coding-agent is installed."
  else
    as_user_shell 'bun remove -g @earendil-works/pi-coding-agent >/dev/null 2>&1 || true'
    warn "pi-coding-agent installation failed. Check the network connection."
    FAILED_PACKAGES+=("bun:@earendil-works/pi-coding-agent")
  fi
else
  warn "bun is not available for $TARGET_USER. Skip pi-coding-agent."
  FAILED_PACKAGES+=("bun:@earendil-works/pi-coding-agent")
fi

# --- EasyTier (内网穿透) ---
log "Install EasyTier (P2P VPN)."

EASYTIER_ARCH="x86_64"
EASYTIER_API="https://api.github.com/repos/EasyTier/EasyTier/releases/latest"
EASYTIER_READY=false

if [[ -x "$HOME_DIR/.local/bin/easytier-cli" && -x "$HOME_DIR/.local/bin/easytier-core" ]]; then
  success "EasyTier is already installed."
  EASYTIER_INSTALLED=true
else
  EASYTIER_INSTALLED=false
  EASYTIER_TMP=$(mktemp -d /tmp/easytier-install.XXXXXX)
fi

if [ "$EASYTIER_INSTALLED" = false ]; then
log "Get the latest stable EasyTier release."
EASYTIER_RELEASE_FILE="$EASYTIER_TMP/release.json"
if "$GITHUB_CURL_WRAPPER" "$EASYTIER_RELEASE_FILE" "$EASYTIER_API"; then
  EASYTIER_RELEASE_JSON=$(<"$EASYTIER_RELEASE_FILE")
  EASYTIER_TAG=$(jq -r '.tag_name // empty' <<< "$EASYTIER_RELEASE_JSON")
  if [[ "$EASYTIER_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    EASYTIER_VER="${EASYTIER_TAG#v}"
    EASYTIER_ZIP="easytier-linux-${EASYTIER_ARCH}-${EASYTIER_TAG}.zip"
    EASYTIER_ASSET_URL=$(jq -r --arg name "$EASYTIER_ZIP" \
      '.assets[]? | select(.name == $name) | .browser_download_url' \
      <<< "$EASYTIER_RELEASE_JSON" | head -n 1)

    if [[ "$EASYTIER_ASSET_URL" == https://github.com/EasyTier/EasyTier/releases/download/* ]]; then
      EASYTIER_URL="$EASYTIER_ASSET_URL"
      EASYTIER_READY=true
      info_kv "EasyTier release" "$EASYTIER_TAG"
    else
      warn "The EasyTier release does not contain $EASYTIER_ZIP."
    fi
  else
    warn "GitHub returned an invalid EasyTier release tag: ${EASYTIER_TAG:-<empty>}."
  fi
else
  warn "The EasyTier release query failed through all GitHub routes."
fi

if [ "$EASYTIER_READY" = true ] && \
  "$GITHUB_CURL_WRAPPER" "$EASYTIER_TMP/$EASYTIER_ZIP" "$EASYTIER_URL"; then

  # 防止代理站返回 HTML/错误页，但 curl 仍保存成 zip 文件。
  if unzip -tq "$EASYTIER_TMP/$EASYTIER_ZIP" >/dev/null 2>&1; then
    success "The EasyTier archive is downloaded and valid."

    if unzip -qo "$EASYTIER_TMP/$EASYTIER_ZIP" -d "$EASYTIER_TMP"; then
      # EasyTier 的 zip 解压后可能带有子目录，所以不能只检查解压根目录。
      EASYTIER_CLI="$(find "$EASYTIER_TMP" -type f -name easytier-cli -perm /111 | head -n 1)"
      EASYTIER_CORE="$(find "$EASYTIER_TMP" -type f -name easytier-core -perm /111 | head -n 1)"

      # 某些 zip 解压后权限可能没保留 executable bit，再宽松找一次。
      [[ -z "$EASYTIER_CLI" ]] && EASYTIER_CLI="$(find "$EASYTIER_TMP" -type f -name easytier-cli | head -n 1)"
      [[ -z "$EASYTIER_CORE" ]] && EASYTIER_CORE="$(find "$EASYTIER_TMP" -type f -name easytier-core | head -n 1)"

      if [[ -n "$EASYTIER_CLI" && -n "$EASYTIER_CORE" ]]; then
        as_user install -Dm755 "$EASYTIER_CLI" "$HOME_DIR/.local/bin/easytier-cli"
        as_user install -Dm755 "$EASYTIER_CORE" "$HOME_DIR/.local/bin/easytier-core"

        if [[ -x "$HOME_DIR/.local/bin/easytier-cli" && -x "$HOME_DIR/.local/bin/easytier-core" ]]; then
          success "EasyTier v${EASYTIER_VER} is installed."
        else
          rm -f -- "$HOME_DIR/.local/bin/easytier-cli" "$HOME_DIR/.local/bin/easytier-core"
          warn "The EasyTier command completed, but its executables are not in PATH."
          FAILED_PACKAGES+=("manual:easytier")
        fi
      else
        warn "The archive does not contain easytier-cli and easytier-core."
        warn "Archive contents:"
        find "$EASYTIER_TMP" -maxdepth 3 -type f | sed 's#^#  - #' | head -n 30 || true
        FAILED_PACKAGES+=("manual:easytier")
      fi
    else
      warn "The EasyTier archive extraction failed."
      FAILED_PACKAGES+=("manual:easytier")
    fi
  else
    warn "The EasyTier archive is not valid. The proxy might have returned an HTML error page."
    FAILED_PACKAGES+=("manual:easytier")
  fi
else
  if [ "$EASYTIER_READY" = true ]; then
    warn "The EasyTier download failed through all GitHub routes: $EASYTIER_URL."
  fi
  FAILED_PACKAGES+=("manual:easytier")
fi

rm -rf -- "$EASYTIER_TMP"
EASYTIER_TMP=""
fi

# 配置用户桌面。
section "Post-install" "Configure GTK, the terminal, and Flatpak"
if as_user env HOME="$HOME_DIR" USER="$TARGET_USER" bash "$0" --user-desktop-settings; then
  success "The user GTK, terminal, and Flatpak settings are applied."
else
  error "The user GTK, terminal, and Flatpak settings failed."
  FAILED_PACKAGES+=("config:user-desktop-settings")
fi

# 隐藏辅助桌面条目。

section "Application configuration" "Hide auxiliary desktop entries"
log "Hide auxiliary desktop entries."
run_hide_desktop_file

# --- keyd keyboard remapping ---
if pacman -Q keyd >/dev/null 2>&1; then
  section "Post-install" "Configure keyd keyboard mappings"
  log "Enable and start the keyd service."
  if systemctl enable --now keyd; then
    log "Reload the keyd configuration."
    if keyd reload; then
      success "The keyd service is enabled. The configuration is reloaded."
    else
      error "The keyd configuration reload failed."
      FAILED_PACKAGES+=("config:keyd-reload")
    fi
  else
    error "keyd.service could not be enabled or started."
    FAILED_PACKAGES+=("config:keyd-service")
  fi
else
  warn "keyd is not installed. Skip service configuration."
fi

# ------------------------------------------------------------------------------
# 生成安装后任务失败报告。
# ------------------------------------------------------------------------------
if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
  DOCS_DIR="$HOME_DIR/Documents"
  REPORT_FILE="$DOCS_DIR/post-install-failures.txt"

  if [[ ! -d "$DOCS_DIR" ]]; then
    as_user mkdir -p "$DOCS_DIR"
  fi

  {
    echo -e "\n========================================================"
    echo -e " Installation failure report - $(date)"
    echo -e "========================================================"
    printf "%s\n" "${FAILED_PACKAGES[@]}"
  } >>"$REPORT_FILE"

  chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"

  echo ""
  warn "Some post-install tasks failed."
  warn "The report is saved to this file:"
  echo -e " ${BOLD}$REPORT_FILE${NC}"
else
  success "All post-install tasks were processed."
fi

log "Module 99b-apps is complete."
