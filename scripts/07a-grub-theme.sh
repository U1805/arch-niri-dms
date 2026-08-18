#!/bin/bash

# ==============================================================================
# 07a-grub-theme.sh - 选择并安装 GRUB 主题
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
GITHUB_GIT_WRAPPER="${SHORIN_GITHUB_GIT_WRAPPER:-$PARENT_DIR/github-wrapper/git-github-wrapper.sh}"
source "$SCRIPT_DIR/00-utils.sh"

check_root

TEMP_MG_DIR=""
cleanup_minegrub_source() {
    [[ -z "$TEMP_MG_DIR" ]] || rm -rf -- "$TEMP_MG_DIR"
}
trap cleanup_minegrub_source EXIT
trap 'exit 130' INT TERM

# ------------------------------------------------------------------------------
# 检查 GRUB。
# ------------------------------------------------------------------------------
if ! command -v grub-mkconfig >/dev/null 2>&1; then
    echo ""
    warn "grub-mkconfig is not available."
    log "Skip GRUB theme installation."
    exit 0
fi

section "Phase 7A" "Install a GRUB theme"

# 辅助函数

cleanup_minegrub() {
    local minegrub_found=false
    
    if [ -f "/etc/grub.d/05_twomenus" ] || [ -f "/boot/grub/mainmenu.cfg" ]; then
        minegrub_found=true
        log "Minegrub files were detected. Remove them."
        [ -f "/etc/grub.d/05_twomenus" ] && exe rm -f /etc/grub.d/05_twomenus
        [ -f "/boot/grub/mainmenu.cfg" ] && exe rm -f /boot/grub/mainmenu.cfg
    fi
    
    if command -v grub-editenv >/dev/null 2>&1; then
        if grub-editenv - list 2>/dev/null | grep -q "^config_file="; then
            minegrub_found=true
            log "Remove the Minegrub GRUB environment variable."
            exe grub-editenv - unset config_file
        fi
    fi
    
    if [ "$minegrub_found" == "true" ]; then
        success "The Minegrub double-menu configuration is removed."
    fi
}

SENREN_GFXMODE_STATE_DIR="/var/lib/arch-niri-dms"
SENREN_GFXMODE_STATE="$SENREN_GFXMODE_STATE_DIR/senren-banka-grub-gfxmode"

remember_pre_senren_gfxmode() {
    [ -f "$SENREN_GFXMODE_STATE" ] && return 0
    mkdir -p "$SENREN_GFXMODE_STATE_DIR"
    if grep -q '^GRUB_GFXMODE=' /etc/default/grub; then
        grep -m1 '^GRUB_GFXMODE=' /etc/default/grub > "$SENREN_GFXMODE_STATE"
    else
        printf '%s\n' '__ABSENT__' > "$SENREN_GFXMODE_STATE"
    fi
}

restore_pre_senren_gfxmode() {
    local saved
    [ -f "$SENREN_GFXMODE_STATE" ] || return 0
    saved=$(cat "$SENREN_GFXMODE_STATE")
    sed -i '/^GRUB_GFXMODE=/d' /etc/default/grub
    [ "$saved" = '__ABSENT__' ] || printf '%s\n' "$saved" >> /etc/default/grub
    rm -f -- "$SENREN_GFXMODE_STATE"
    log "Restore the GRUB_GFXMODE value from before Senren Banka was selected."
}

detect_grub_resolution() {
    if [[ "${SENREN_GRUB_RESOLUTION:-}" =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]]; then
        printf '%s\n' "$SENREN_GRUB_RESOLUTION"
        return
    fi
    printf '%s\n' '1920x1200'
}

prepare_senren_banka_theme() {
    local theme_dir="$1" resolution source_dir stage_dir old_dir generated
    resolution=$(detect_grub_resolution)
    [[ "$resolution" =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]] || resolution=1920x1200

    source_dir="$SOURCE_BASE/senren-banka"
    [ -d "$source_dir" ] || {
        error "The repository Senren Banka theme is missing: $source_dir"
        return 1
    }
    stage_dir=$(mktemp -d "${theme_dir%/*}/.senren-banka.new.XXXXXX") || return 1
    if ! cp -a "$source_dir/." "$stage_dir/"; then
        rm -rf -- "$stage_dir"
        return 1
    fi

    log "Generate the Senren Banka theme for $resolution."
    for helper in configure-resolution.py build-layout-variants.py build-fonts.py; do
        [ -f "$stage_dir/$helper" ] || {
            error "The Senren Banka helper is missing: $source_dir/$helper"
            rm -rf -- "$stage_dir"
            return 1
        }
    done
    if ! exe python3 "$stage_dir/configure-resolution.py" "$resolution" ||
        ! exe python3 "$stage_dir/build-layout-variants.py" ||
        ! exe python3 "$stage_dir/build-fonts.py"; then
        rm -rf -- "$stage_dir"
        return 1
    fi
    for generated in background.png title_logo.png theme.txt \
        SenrenMenuMain.pf2 SenrenMenuMessage.pf2 GRUBBlank.pf2; do
        [ -s "$stage_dir/$generated" ] || {
            error "The Senren Banka generated file is missing: $generated"
            rm -rf -- "$stage_dir"
            return 1
        }
    done

    old_dir="${theme_dir}.old.$$"
    rm -rf -- "$old_dir"
    if [ -e "$theme_dir" ]; then
        mv -- "$theme_dir" "$old_dir" || { rm -rf -- "$stage_dir"; return 1; }
    fi
    if ! mv -- "$stage_dir" "$theme_dir"; then
        [ ! -e "$old_dir" ] || mv -- "$old_dir" "$theme_dir"
        rm -rf -- "$stage_dir"
        return 1
    fi
    rm -rf -- "$old_dir"
    THEME_GFXMODE="$resolution"
    success "The Senren Banka assets and pinned Gentium Book fonts are ready."
}

# ------------------------------------------------------------------------------
# 同步主题到系统目录。
# ------------------------------------------------------------------------------
section "Step 1/3" "Synchronize themes to the system directory"

SOURCE_BASE="$PARENT_DIR/grub/themes"
# 【核心改变】使用 Arch Linux 官方标准的主题存放目录
DEST_DIR="/usr/share/grub/themes"

# 确保目标目录存在
if [ ! -d "$DEST_DIR" ]; then
    exe mkdir -p "$DEST_DIR"
fi

if [ -d "$SOURCE_BASE" ]; then
    log "Synchronize repository themes to $DEST_DIR."
    for dir in "$SOURCE_BASE"/*; do
        THEME_BASENAME=$(basename "$dir")
        # wuthering 是模板。每张背景图生成一个主题。
        if [ "$THEME_BASENAME" = "wuthering" ]; then
            if [ -d "$dir/backgrounds" ] && [ -f "$dir/theme.txt" ]; then
                for bg in "$dir/backgrounds"/*.jpg; do
                    [ -f "$bg" ] || continue
                    BG_NAME=$(basename "$bg" .jpg)
                    log "Create the $BG_NAME theme from the wuthering template."
                    exe mkdir -p "$DEST_DIR/$BG_NAME"
                    # 字体文件
                    for f in "$dir"/*.pf2; do [ -f "$f" ] && exe cp "$f" "$DEST_DIR/$BG_NAME/"; done
                    # 主题配置
                    exe cp "$dir/theme.txt" "$DEST_DIR/$BG_NAME/"
                    # 图标
                    exe mkdir -p "$DEST_DIR/$BG_NAME/icons"
                    exe cp -a "$dir/icons/." "$DEST_DIR/$BG_NAME/icons/"
                    # 界面图片
                    for f in "$dir"/*.png; do [ -f "$f" ] && exe cp "$f" "$DEST_DIR/$BG_NAME/"; done
                    # 背景图片
                    exe cp "$bg" "$DEST_DIR/$BG_NAME/background.jpg"
                done
            fi
        elif [ "$THEME_BASENAME" = "senren-banka" ] && [ -d "$dir" ] && [ -f "$dir/theme.txt" ]; then
            # An existing generated copy remains bootable until the selected
            # theme is rebuilt transactionally in Step 3.
            if [ ! -f "$DEST_DIR/$THEME_BASENAME/theme.txt" ]; then
                log "Synchronize the initial $THEME_BASENAME theme."
                exe mkdir -p "$DEST_DIR/$THEME_BASENAME"
                exe cp -a "$dir/." "$DEST_DIR/$THEME_BASENAME/"
            else
                log "Keep the current $THEME_BASENAME assets until regeneration succeeds."
            fi
        elif [ -d "$dir" ] && [ -f "$dir/theme.txt" ]; then
            log "Synchronize the $THEME_BASENAME theme."
            exe mkdir -p "$DEST_DIR/$THEME_BASENAME"
            exe cp -a "$dir/." "$DEST_DIR/$THEME_BASENAME/"
        fi
    done
    success "Local themes are installed in $DEST_DIR."
else
    warn "The repository does not contain grub/themes. Use an online or current theme."
fi

log "Find themes in $DEST_DIR."
THEME_PATHS=()
THEME_NAMES=()

# 直接扫描这个干净的系统级目录，无需任何额外处理
mapfile -t FOUND_DIRS < <(find "$DEST_DIR" -mindepth 1 -maxdepth 1 -type d | sort 2>/dev/null || true)

for dir in "${FOUND_DIRS[@]:-}"; do
    if [ -n "$dir" ] && [ -f "$dir/theme.txt" ]; then
        DIR_NAME=$(basename "$dir")
        if [[ "$DIR_NAME" != "minegrub" && "$DIR_NAME" != "minegrub-world-selection" ]]; then
            THEME_PATHS+=("$dir")
            THEME_NAMES+=("$DIR_NAME")
        fi
    fi
done

if [ ${#THEME_NAMES[@]} -eq 0 ]; then
    log "No valid local theme exists. Show only online options."
fi


# ------------------------------------------------------------------------------
# 显示主题选择菜单。
# ------------------------------------------------------------------------------
section "Step 2/3" "Select a theme"

INSTALL_MINEGRUB=false
SKIP_THEME=false
THEME_GFXMODE=""

MINEGRUB_OPTION_NAME="Minegrub"
SKIP_OPTION_NAME="No theme (skip or clear)"

MINEGRUB_IDX=$((${#THEME_NAMES[@]} + 1))
SKIP_IDX=$((${#THEME_NAMES[@]} + 2))

TITLE_TEXT="Select GRUB Theme (30s Timeout)"
LINE_STR="───────────────────────────────────────────────────────"

echo -e "\n${H_PURPLE}╭${LINE_STR}${NC}"
echo -e "${H_PURPLE}│${NC}   ${BOLD}${TITLE_TEXT}${NC}"
echo -e "${H_PURPLE}├${LINE_STR}${NC}"

for i in "${!THEME_NAMES[@]}"; do
    NAME="${THEME_NAMES[$i]}"
    DISPLAY_NAME=$(echo "$NAME" | sed -E 's/^[0-9]+//')
    DISPLAY_IDX=$((i+1))
    
    if [ "$i" -eq 0 ]; then
        COLOR_STR=" ${H_CYAN}[$DISPLAY_IDX]${NC} ${DISPLAY_NAME} - ${H_GREEN}Default${NC}"
    else
        COLOR_STR=" ${H_CYAN}[$DISPLAY_IDX]${NC} ${DISPLAY_NAME}"
    fi
    echo -e "${H_PURPLE}│${NC} ${COLOR_STR}"
done

MG_COLOR_STR=" ${H_CYAN}[$MINEGRUB_IDX]${NC} ${MINEGRUB_OPTION_NAME}"
echo -e "${H_PURPLE}│${NC} ${MG_COLOR_STR}"

SKIP_COLOR_STR=" ${H_CYAN}[$SKIP_IDX]${NC} ${H_YELLOW}${SKIP_OPTION_NAME}${NC}"
echo -e "${H_PURPLE}│${NC} ${SKIP_COLOR_STR}"

echo -e "${H_PURPLE}╰${LINE_STR}${NC}\n"

echo -ne "   ${H_YELLOW}Select an option [1-$SKIP_IDX]. Default: 1. Timeout: 30 seconds: ${NC}"
read -r -t 30 USER_CHOICE || true
if [ -z "${USER_CHOICE:-}" ]; then echo ""; fi
USER_CHOICE=${USER_CHOICE:-1}

if ! [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] || [ "$USER_CHOICE" -lt 1 ] || [ "$USER_CHOICE" -gt "$SKIP_IDX" ]; then
    log "The selection is not valid, or input timed out. Select the first option."
    USER_CHOICE=1
fi

if [ "$USER_CHOICE" -eq "$SKIP_IDX" ]; then
    SKIP_THEME=true
    info_kv "Selected" "No theme"
    elif [ "$USER_CHOICE" -eq "$MINEGRUB_IDX" ]; then
    INSTALL_MINEGRUB=true
    info_kv "Selected" "Minegrub (online repository)"
else
    SELECTED_INDEX=$((USER_CHOICE-1))
    if [ -n "${THEME_NAMES[$SELECTED_INDEX]:-}" ]; then
        THEME_PATH="${THEME_PATHS[$SELECTED_INDEX]}/theme.txt"
        THEME_NAME="${THEME_NAMES[$SELECTED_INDEX]}"
        info_kv "Selected" "Local theme: $THEME_NAME"
    else
        warn "The selected local theme does not exist. Use Minegrub."
        INSTALL_MINEGRUB=true
    fi
fi

# ------------------------------------------------------------------------------
# 安装并配置主题。
# ------------------------------------------------------------------------------
section "Step 3/3" "Configure the theme"

GRUB_CONF="/etc/default/grub"

if [ "$SKIP_THEME" == "true" ]; then
    log "Clear the GRUB theme configuration."
    cleanup_minegrub
    restore_pre_senren_gfxmode
    
    if [ -f "$GRUB_CONF" ]; then
        if grep -q "^GRUB_THEME=" "$GRUB_CONF"; then
            exe sed -i 's|^GRUB_THEME=|#GRUB_THEME=|' "$GRUB_CONF"
            success "The current GRUB_THEME setting is disabled."
        else
            log "No active GRUB_THEME setting exists."
        fi
    fi
    
    elif [ "$INSTALL_MINEGRUB" == "true" ]; then
    log "Prepare to install the Minegrub theme."
    restore_pre_senren_gfxmode
    
    if ! command -v git >/dev/null 2>&1; then
        error "git is not available. Minegrub cannot be cloned."
    else
        TEMP_MG_DIR=$(mktemp -d -t minegrub_install_XXXXXX)
        log "Clone Lxtharia/double-minegrub-menu."
        if exe "$GITHUB_GIT_WRAPPER" clone --depth 1 \
            "https://github.com/Lxtharia/double-minegrub-menu.git" "$TEMP_MG_DIR"; then
            if [ -f "$TEMP_MG_DIR/install.sh" ]; then
                log "Run the Minegrub install.sh script."
                (
                    cd "$TEMP_MG_DIR" || exit 1
                    exe chmod +x install.sh
                    exe ./install.sh
                )
                if [ $? -eq 0 ]; then
                    success "The Minegrub theme is installed."
                else
                    error "The Minegrub install.sh script failed."
                fi
            else
                error "The cloned repository does not contain install.sh."
            fi
        else
            error "The Minegrub repository clone failed."
        fi
        rm -rf -- "$TEMP_MG_DIR"
        TEMP_MG_DIR=""
    fi
    
else
    cleanup_minegrub
    
    if [ "$THEME_NAME" = "senren-banka" ]; then
        log "Install the Senren Banka font and asset generation dependencies."
        if ! exe pacman -S --noconfirm --needed \
            ttf-gentium-book python-fonttools; then
            error "The Senren Banka theme dependencies could not be installed."
            exit 1
        fi
        if ! python3 -c 'from PIL import Image' >/dev/null 2>&1; then
            error "python-pillow is required. Install phase 5.8 before the GRUB theme phase."
            exit 1
        fi
        remember_pre_senren_gfxmode
        prepare_senren_banka_theme "${THEME_PATH%/theme.txt}" || exit 1
    else
        restore_pre_senren_gfxmode
    fi

    if [ -f "$GRUB_CONF" ]; then
        if grep -q "^GRUB_THEME=" "$GRUB_CONF"; then
            exe sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" "$GRUB_CONF"
            elif grep -q "^#GRUB_THEME=" "$GRUB_CONF"; then
            exe sed -i "s|^#GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" "$GRUB_CONF"
        else
            echo "GRUB_THEME=\"$THEME_PATH\"" >> "$GRUB_CONF"
        fi
        
        if grep -q "^GRUB_TERMINAL_OUTPUT=\"console\"" "$GRUB_CONF"; then
            exe sed -i 's/^GRUB_TERMINAL_OUTPUT="console"/#GRUB_TERMINAL_OUTPUT="console"/' "$GRUB_CONF"
        fi
        
        if [ -n "$THEME_GFXMODE" ] && grep -q "^GRUB_GFXMODE=" "$GRUB_CONF"; then
            exe sed -i "s|^GRUB_GFXMODE=.*|GRUB_GFXMODE=\"$THEME_GFXMODE\"|" "$GRUB_CONF"
        elif [ -n "$THEME_GFXMODE" ]; then
            echo "GRUB_GFXMODE=\"$THEME_GFXMODE\"" >> "$GRUB_CONF"
        elif ! grep -q "^GRUB_GFXMODE=" "$GRUB_CONF"; then
            echo 'GRUB_GFXMODE=auto' >> "$GRUB_CONF"
        fi
        success "The GRUB theme is set to $THEME_NAME."
    else
        error "$GRUB_CONF is not available."
        exit 1
    fi
fi

log "Module 07a is complete."
