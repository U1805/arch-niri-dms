#!/bin/bash

# ==============================================================================
# 07a-grub-theme.sh - 选择并安装 GRUB 主题
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

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

MINEGRUB_OPTION_NAME="Minegrub"
SKIP_OPTION_NAME="No theme (skip or clear)"

MINEGRUB_IDX=$((${#THEME_NAMES[@]} + 1))
SKIP_IDX=$((${#THEME_NAMES[@]} + 2))

TITLE_TEXT="Select GRUB Theme (60s Timeout)"
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

echo -ne "   ${H_YELLOW}Select an option [1-$SKIP_IDX]: ${NC}"
read -t 60 USER_CHOICE || true
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
    
    if ! command -v git >/dev/null 2>&1; then
        error "git is not available. Minegrub cannot be cloned."
    else
        TEMP_MG_DIR=$(mktemp -d -t minegrub_install_XXXXXX)
        log "Clone Lxtharia/double-minegrub-menu."
        if exe git clone --depth 1 "https://github.com/Lxtharia/double-minegrub-menu.git" "$TEMP_MG_DIR"; then
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
        [ -n "$TEMP_MG_DIR" ] && rm -rf "$TEMP_MG_DIR"
    fi
    
else
    cleanup_minegrub
    
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
        
        if ! grep -q "^GRUB_GFXMODE=" "$GRUB_CONF"; then
            echo 'GRUB_GFXMODE=auto' >> "$GRUB_CONF"
        fi
        success "The GRUB theme is set to $THEME_NAME."
    else
        error "$GRUB_CONF is not available."
        exit 1
    fi
fi

log "Module 07a is complete."
