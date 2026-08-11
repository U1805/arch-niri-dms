#!/bin/bash

# ==============================================================================
# 99a-apps.sh - 安装固定的 Pacman、AUR 和 Flatpak 应用
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
  source "$SCRIPT_DIR/00-utils.sh"
else
  echo "Error: 00-utils.sh is not available in $SCRIPT_DIR."
  exit 1
fi

# 配置

check_root

# ------------------------------------------------------------------------------
# 确定目标用户和 AUR 助手。
# ------------------------------------------------------------------------------
section "Phase 5" "Install common applications"

log "Identify the target user."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
  error "The target user is not valid, or the home directory does not exist."
  exit 1
fi
info_kv "Target user" "$TARGET_USER"

if ! enable_temporary_sudo; then
  exit 1
fi

# 以目标用户身份运行命令。
as_user() {
  runuser -u "$TARGET_USER" -- "$@"
}

AUR_HELPER="paru"
PARU_MAKEPKG_ARGS=()
if [[ -x "${SHORIN_MAKEPKG_WRAPPER:-}" ]]; then
  PARU_MAKEPKG_ARGS+=(--makepkg "$SHORIN_MAKEPKG_WRAPPER")
fi

if command -v "$AUR_HELPER" &>/dev/null; then
  info_kv "AUR helper" "$AUR_HELPER"
else
  AUR_HELPER=""
  warn "paru is not available. Install repository and Flatpak applications, but skip AUR applications."
fi

# ------------------------------------------------------------------------------
# 读取完整应用列表。
# ------------------------------------------------------------------------------
LIST_FILENAME="common-applist.txt"
LIST_FILE="$PARENT_DIR/$LIST_FILENAME"

REPO_APPS=()
AUR_APPS=()
FLATPAK_APPS=()
FAILED_PACKAGES=()

if [[ ! -f "$LIST_FILE" ]]; then
  warn "$LIST_FILENAME is not available. Skip common applications."
  APP_LIST_RAW=""
elif ! grep -q -vE "^\s*#|^\s*$" "$LIST_FILE"; then
  warn "The application list is empty. Skip common applications."
  APP_LIST_RAW=""
else
  log "Read the application list from $LIST_FILENAME."
  APP_LIST_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')
fi

# ------------------------------------------------------------------------------
# 按来源分类并删除来源前缀。
# ------------------------------------------------------------------------------
log "Sort the application list by source."

while IFS= read -r line; do
  raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
  [[ -z "$raw_pkg" ]] && continue

  if [[ "$raw_pkg" == flatpak:* ]]; then
    clean_name="${raw_pkg#flatpak:}"
    FLATPAK_APPS+=("$clean_name")
  elif [[ "$raw_pkg" == AUR:* ]]; then
    clean_name="${raw_pkg#AUR:}"
    AUR_APPS+=("$clean_name")
  else
    REPO_APPS+=("$raw_pkg")
  fi
done <<<"$APP_LIST_RAW"

info_kv "Scheduled" "Repository: ${#REPO_APPS[@]}" "AUR: ${#AUR_APPS[@]}, Flatpak: ${#FLATPAK_APPS[@]}"

# ------------------------------------------------------------------------------
# 安装应用。
# ------------------------------------------------------------------------------

# 批量安装仓库应用。
if [[ ${#REPO_APPS[@]} -gt 0 ]]; then
  section "Step 1/3" "Install repository packages"

  REPO_QUEUE=()
  for pkg in "${REPO_APPS[@]}"; do
    if pacman -Qi "$pkg" &>/dev/null; then
      log "$pkg is installed."
    else
      REPO_QUEUE+=("$pkg")
    fi
  done

  if [[ ${#REPO_QUEUE[@]} -gt 0 ]]; then
    info_kv "Install" "${#REPO_QUEUE[@]} pacman packages"

    if ! exe pacman -Syu --noconfirm --needed "${REPO_QUEUE[@]}"; then
      error "The package transaction failed. Some repository packages might not be installed."
      for pkg in "${REPO_QUEUE[@]}"; do
        FAILED_PACKAGES+=("repo:$pkg")
      done
    else
      success "The repository packages are installed."
    fi
  else
    log "All repository packages are installed."
  fi
fi

# 逐个安装 AUR 应用，并在失败后重试。
if [[ ${#AUR_APPS[@]} -gt 0 ]]; then
  section "Step 2/3" "Install AUR packages"

  if [[ -z "$AUR_HELPER" ]]; then
    error "No AUR helper is available. Skip AUR packages."
    for app in "${AUR_APPS[@]}"; do
      FAILED_PACKAGES+=("aur:$app")
    done
  else
    for app in "${AUR_APPS[@]}"; do
      if pacman -Qi "$app" &>/dev/null; then
        log "$app is installed."
        continue
      fi

      log "Install the AUR package: $app."
      install_success=false
      max_retries=1

      for ((i = 0; i <= max_retries; i++)); do
        if [[ $i -gt 0 ]]; then
          warn "Retry $app. Attempt $i of $max_retries."
        fi

        if as_user "$AUR_HELPER" "${PARU_MAKEPKG_ARGS[@]}" -Syu --noconfirm --needed "$app"; then
          install_success=true
          success "$app is installed."
          break
        else
          warn "Installation attempt $((i + 1)) failed for $app."
        fi
      done

      if [[ "$install_success" == false ]]; then
        error "$app failed to install after $((max_retries + 1)) attempts."
        FAILED_PACKAGES+=("aur:$app")
      fi
    done
  fi
fi

# 逐个安装 Flatpak 应用。
if [[ ${#FLATPAK_APPS[@]} -gt 0 ]]; then
  section "Step 3/3" "Install Flatpak applications"

  for app in "${FLATPAK_APPS[@]}"; do
    if flatpak info "$app" &>/dev/null; then
      log "$app is installed."
      continue
    fi

    log "Install the Flatpak application: $app."
    if ! exe flatpak install -y flathub "$app"; then
      error "$app failed to install."
      FAILED_PACKAGES+=("flatpak:$app")
    else
      success "$app is installed."
    fi
  done
fi


# ------------------------------------------------------------------------------
# 生成安装失败报告。
# ------------------------------------------------------------------------------
if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
  DOCS_DIR="$HOME_DIR/Documents"
  REPORT_FILE="$DOCS_DIR/installation-failures.txt"

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
  warn "Some applications failed to install."
  warn "The report is saved to this file:"
  echo -e " ${BOLD}$REPORT_FILE${NC}"
else
  success "All applications in the list were processed."
fi

log "Module 99a-apps is complete."
