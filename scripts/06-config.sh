#!/usr/bin/env bash

# ==============================================================================
# 06-config.sh - 部署仓库资源、用户设置并验证结果
# ==============================================================================

backup_and_copy_dotfiles() {
  local template_dir="$DMS_DOTFILES_DIR"
  local backup_dir="$HOME/.cache/arch-niri-dms-backup/$(date +%Y%m%d_%H%M%S)"
  local file rel_path destination backup_path

  [[ -d "$template_dir" ]] || {
    echo "Error: The repository configuration directory is not available: $template_dir." >&2
    return 1
  }

  mkdir -p "$backup_dir"
  while IFS= read -r -d '' file; do
    rel_path="${file#./}"
    destination="$HOME/$rel_path"
    mkdir -p "$(dirname "$destination")"

    if [[ -e "$destination" || -L "$destination" ]]; then
      backup_path="$backup_dir/$rel_path"
      mkdir -p "$(dirname "$backup_path")"
      cp -a "$destination" "$backup_path"
      rm -f "$destination"
    fi
    cp -a "$template_dir/$rel_path" "$destination"
  # 不部署仓库中与设备相关的链接和临时链接。
  done < <(cd "$template_dir" && find . -type f -print0)

  # The repository profile contains proxy defaults for an already configured
  # desktop.  A newly installed system does not have that proxy yet; enabling
  # these variables on its first login would also prevent the proxy client
  # itself from being downloaded.  Keep the settings visible, but disabled.
  if [[ -f "$HOME/.bash_profile" ]]; then
    sed -Ei \
      '/^[[:space:]]*export[[:space:]]+(http_proxy|https_proxy|HTTP_PROXY|HTTPS_PROXY|all_proxy|ALL_PROXY|no_proxy|NO_PROXY)=/ s/^/# disabled during installation: /' \
      "$HOME/.bash_profile"
  fi

  echo "The current user configuration is backed up to $backup_dir."
}

finalize_user_resources() {
  local tool
  local user_tools=(clean media-info pac pacd pacrrr preview timer change-grub-theme)
  local niri_runtime_files=(alttab.kdl colors.kdl cursor.kdl layout.kdl outputs.kdl)

  LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 xdg-user-dirs-update --force || true

  for tool in "${user_tools[@]}"; do
    if [[ ! -f "$HOME/.local/bin/$tool" ]]; then
      printf 'Error: The deployed user tool is missing: %s.\n' "$tool" >&2
      return 1
    fi
    chmod 755 "$HOME/.local/bin/$tool"
  done

  if [[ -f "$HOME/.config/gtk-3.0/bookmarks" ]]; then
    printf 'file://%s/Documents Documents\nfile://%s/Pictures Pictures\nfile://%s/Videos Videos\nfile://%s/Music Music\nfile://%s/Downloads Downloads\n' \
      "$HOME" "$HOME" "$HOME" "$HOME" "$HOME" >"$HOME/.config/gtk-3.0/bookmarks"
  fi

  mkdir -p "$HOME/Templates"
  touch "$HOME/Templates/new"
  printf '#!/usr/bin/env bash\n' >"$HOME/Templates/new.sh"
  chmod +x "$HOME/Templates/new.sh"

  mkdir -p "$HOME/.config/niri/dms"
  # DMS owns these device/theme-specific fragments at runtime. They are
  # intentionally ignored by Git, but every non-optional Niri include must
  # exist before the first graphical login.
  for file in "${niri_runtime_files[@]}"; do
    touch "$HOME/.config/niri/dms/$file"
  done

  if ! niri validate --config "$HOME/.config/niri/config.kdl"; then
    printf 'Error: The deployed Niri configuration is invalid.\n' >&2
    return 1
  fi

  if [[ -f "$DMS_DOC_FILE" ]]; then
    cp -n "$DMS_DOC_FILE" "$HOME/README-Shorin-DMS-Niri.txt" || true
  fi
}

if [[ "${1:-}" == "--user-phase" ]]; then
  shift
  : "${DMS_DOTFILES_DIR:?DMS_DOTFILES_DIR is required}"
  : "${DMS_DOC_FILE:?DMS_DOC_FILE is required}"
  case "${1:-}" in
    dotfiles) backup_and_copy_dotfiles ;;
    user-resources) finalize_user_resources ;;
    *) echo "Error: The DMS resource phase is not valid." >&2; exit 2 ;;
  esac
  exit
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"
check_root
detect_target_user

WALLPAPER_PART=""
cleanup_wallpaper_download() {
  [[ -z "$WALLPAPER_PART" ]] || rm -f -- "$WALLPAPER_PART"
}
trap cleanup_wallpaper_download EXIT
trap 'exit 130' INT TERM

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
  error "The target user is not valid, or the home directory does not exist."
  exit 1
fi

DMS_DOTFILES_DIR="$PARENT_DIR/dotfiles"
DMS_DOC_FILE="$PARENT_DIR/dms-shorin-docs.md"
USER_ENV=(env HOME="$HOME_DIR" USER="$TARGET_USER" DMS_DOTFILES_DIR="$DMS_DOTFILES_DIR" DMS_DOC_FILE="$DMS_DOC_FILE")

section "Shorin DMS" "Deploy repository resources"

if [[ ! -d "$DMS_DOTFILES_DIR" ]]; then
  error "The repository configuration directory does not exist."
  exit 1
fi

log "Back up current files and deploy the user configuration."
if ! as_user "${USER_ENV[@]}" bash "$0" --user-phase dotfiles; then
  error "DMS user configuration deployment failed."
  exit 1
fi

log "Deploy the repository system configuration to /etc."
ETC_SOURCE="$PARENT_DIR/etc"
ETC_BACKUP_DIR="/var/backups/arch-niri-dms/$(date +%Y%m%d_%H%M%S)"
if [[ -d "$ETC_SOURCE" ]]; then
  while IFS= read -r -d '' file; do
    rel_path="${file#./}"
    destination="/etc/$rel_path"
    if [[ -e "$destination" || -L "$destination" ]]; then
      backup_path="$ETC_BACKUP_DIR/$rel_path"
      install -d "$(dirname "$backup_path")"
      cp -a "$destination" "$backup_path"
      rm -f "$destination"
    fi
    install -d "$(dirname "$destination")"
    cp -a "$ETC_SOURCE/$rel_path" "$destination"
  done < <(cd "$ETC_SOURCE" && find . -type f -print0)
fi

log "Download wallpapers."
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"
WALLPAPER_ENTRIES=()
if [[ -f "$PARENT_DIR/wallpapers.txt" ]]; then
  while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    WALLPAPER_ENTRIES+=("$entry")
  done <"$PARENT_DIR/wallpapers.txt"
else
  warn "wallpapers.txt is not available. Skip wallpaper downloads."
fi

install -d "$WALLPAPER_DIR"
chown "$TARGET_USER:" "$WALLPAPER_DIR"
for entry in "${WALLPAPER_ENTRIES[@]}"; do
  if [[ "$entry" == *"|"* ]]; then
    url="${entry%%|*}"
    filename="${entry#*|}"
  else
    url="$entry"
    filename="${url##*/}"
  fi
  if [[ -z "$filename" || "$filename" == */* ]]; then
    warn "The wallpaper entry has an invalid target file name: $entry."
    continue
  fi
  wallpaper_target="$WALLPAPER_DIR/$filename"
  wallpaper_part="$wallpaper_target.part"
  if [[ -s "$wallpaper_target" ]]; then
    log "$filename is already downloaded."
    continue
  fi
  WALLPAPER_PART="$wallpaper_part"
  rm -f -- "$wallpaper_part"
  if curl --fail --location --show-error --progress-bar \
      --retry 3 --retry-delay 2 --connect-timeout 15 \
      -o "$wallpaper_part" "$url"; then
    mv -f -- "$wallpaper_part" "$wallpaper_target"
    WALLPAPER_PART=""
    chown "$TARGET_USER:" "$WALLPAPER_DIR/$filename"
  else
    rm -f -- "$wallpaper_part"
    WALLPAPER_PART=""
    warn "The download failed: $url."
  fi
done

log "Complete user resource configuration."
if ! as_user "${USER_ENV[@]}" bash "$0" --user-phase user-resources; then
  error "DMS user resource configuration failed."
  exit 1
fi

section "Verification" "Check the desktop installation"

VERIFY_LIST="/tmp/shorin_install_verify.list"
if [[ -f "$VERIFY_LIST" ]]; then
  mapfile -t CHECK_PKGS < <(tr ' ' '\n' <"$VERIFY_LIST" | sed '/^[[:space:]]*$/d' | sort -u)
  if [[ ${#CHECK_PKGS[@]} -gt 0 ]]; then
    log "Check ${#CHECK_PKGS[@]} explicit packages."
    MISSING_PKGS="$(pacman -T "${CHECK_PKGS[@]}" 2>/dev/null || true)"
    if [[ -n "$MISSING_PKGS" ]]; then
      error "These desktop packages are not installed:"
      while IFS= read -r package; do
        [[ -n "$package" ]] && echo "  - $package"
      done <<<"$MISSING_PKGS"
      declare -f write_log >/dev/null && \
        write_log "FATAL" "Packages not installed: $(tr '\n' ' ' <<<"$MISSING_PKGS")"
      exit 1
    fi
  fi
  rm -f "$VERIFY_LIST"
  success "All explicit desktop packages are installed."
fi

if [[ ! -e "$HOME_DIR/.config/niri/dms" ]]; then
  error "The required Niri configuration is not available: $HOME_DIR/.config/niri/dms."
  declare -f write_log >/dev/null && \
    write_log "FATAL" "Niri configuration not available: $HOME_DIR/.config/niri/dms."
  exit 1
fi

for required_niri_file in alttab.kdl colors.kdl cursor.kdl layout.kdl outputs.kdl; do
  if [[ ! -f "$HOME_DIR/.config/niri/dms/$required_niri_file" ]]; then
    error "A required generated Niri configuration is missing: $HOME_DIR/.config/niri/dms/$required_niri_file."
    exit 1
  fi
done

for tool in clean media-info pac pacd pacrrr preview timer change-grub-theme; do
  if [[ ! -x "$HOME_DIR/.local/bin/$tool" ]]; then
    error "The user tool is not executable: $HOME_DIR/.local/bin/$tool."
    exit 1
  fi
done

success "Repository resources, user settings, and the desktop state are valid."
