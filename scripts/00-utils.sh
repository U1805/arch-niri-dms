#!/bin/bash

# ==============================================================================
# 00-utils.sh - The "TUI" Visual Engine (v4.0)
# ==============================================================================

# --- 1. 颜色与样式定义 (ANSI) ---
# 注意：这里定义的是字面量字符串，需要 echo -e 来解析
export NC='\033[0m'
export BOLD='\033[1m'
export DIM='\033[2m'
export ITALIC='\033[3m'
export UNDER='\033[4m'
export H_MAGENTA='\033[1;35m'
# 常用高亮色
export H_RED='\033[1;31m'
export H_GREEN='\033[1;32m'
export H_YELLOW='\033[1;33m'
export H_BLUE='\033[1;34m'
export H_PURPLE='\033[1;35m'
export H_CYAN='\033[1;36m'
export H_WHITE='\033[1;37m'
export H_GRAY='\033[1;90m'

# 背景色 (用于标题栏)
export BG_BLUE='\033[44m'
export BG_PURPLE='\033[45m'

# 符号定义
export TICK="${H_GREEN}✔${NC}"
export CROSS="${H_RED}✘${NC}"
export INFO="${H_BLUE}ℹ${NC}"
export WARN="${H_YELLOW}⚠${NC}"
export ARROW="${H_CYAN}➜${NC}"


check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${H_RED}   $CROSS CRITICAL ERROR: Script must be run as root.${NC}"
        exit 1
    fi
}
check_root

# ==============================================================================
# detect_target_user - 识别目标用户 (支持 1-based 序号、回车默认、及新建用户)
# ==============================================================================
detect_target_user() {
    # 1. 缓存检查
    if [[ -f "/tmp/shorin_install_user" ]]; then
        TARGET_USER=$(cat "/tmp/shorin_install_user")
        HOME_DIR="/home/$TARGET_USER"
        export TARGET_USER HOME_DIR
        return 0
    fi
    
    log "Detecting system users..."
    
    # 2. 提取系统中所有普通用户 (UID 1000-60000)
    mapfile -t HUMAN_USERS < <(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd)
    # 获取 UID 为 1000 的用户（绝大多数系统的主力普通用户）
    local UID_1000_USER
    UID_1000_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd | head -n 1)
    
    # 3. 核心决策逻辑
    if [[ ${#HUMAN_USERS[@]} -gt 0 ]]; then
        echo -e "   ${H_YELLOW}>>> Existing users detected. Select target or create new:${NC}"
        
        local default_user=""
        local default_idx=""
        
        # 遍历用户，生成 1 开始的序号 (先打印已有用户列表)
        for i in "${!HUMAN_USERS[@]}"; do
            local mark=""
            local display_idx=$((i + 1))
            
            # 将 UID 1000 的用户设为默认（如果不存在则回退保留原 SUDO_USER 逻辑）
            if [[ "${HUMAN_USERS[$i]}" == "$UID_1000_USER" ]]; then
                mark="${H_CYAN}*${NC}"
                default_user="${HUMAN_USERS[$i]}"
                default_idx="$display_idx"
                elif [[ -z "$default_user" && "${HUMAN_USERS[$i]}" == "${SUDO_USER:-}" ]]; then
                mark="${H_CYAN}*${NC}"
                default_user="${HUMAN_USERS[$i]}"
                default_idx="$display_idx"
            fi
            
            echo -e "       [${display_idx}] ${mark}${HUMAN_USERS[$i]}"
        done
        
        # 如果既没有 UID 1000 也没有 SUDO_USER 匹配，安全兜底选择列表第一个用户为默认
        if [[ -z "$default_user" ]]; then
            default_user="${HUMAN_USERS[0]}"
            default_idx="1"
        fi
        
        # 将 [0] 选项放在列表的最下面
        echo -e "       [0] ${H_GREEN}Create a NEW user ++${NC}"
        
        while true; do
            echo -ne "   ${H_CYAN}Select user ID [0-${#HUMAN_USERS[@]}] (Default ${default_idx}, 30s timeout): ${NC}"
            
            # 增加 -t 30 实现 30 秒超时机制
            if ! read -t 30 -r idx; then
                # 超时处理
                echo # 补充一个换行符，因为超时不会输入回车
                TARGET_USER="$default_user"
                log "Timeout (30s). Auto-selecting default user: ${H_CYAN}${TARGET_USER}${NC}"
                break
            fi
            
            # 处理直接回车：如果有默认用户，直接采纳
            if [[ -z "$idx" && -n "$default_user" ]]; then
                TARGET_USER="$default_user"
                log "Defaulting to user: ${H_CYAN}${TARGET_USER}${NC}"
                break
            fi
            
            # 验证输入
            if [[ "$idx" == "0" ]]; then
                # 用户选择了创建新账户
                TARGET_USER=""
                break
                elif [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#HUMAN_USERS[@]}" ]; then
                TARGET_USER="${HUMAN_USERS[$((idx - 1))]}"
                break
            else
                warn "Invalid selection. Please enter a valid number."
            fi
        done
    else
        # 0 个普通用户的情况
        if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
            TARGET_USER="$SUDO_USER"
        else
            echo -e "   ${H_YELLOW}No standard user found in the system.${NC}"
            TARGET_USER=""
        fi
    fi
    
    # 如果此时 TARGET_USER 为空，说明系统无用户，或者用户手动选择了 [0]
    if [[ -z "$TARGET_USER" ]]; then
        while true; do
            echo -ne "   ${H_GREEN}Please enter a username to CREATE:${NC} "
            read -r NEW_USER
            
            # 基础正则校验：以小写字母开头，只能包含小写字母、数字、破折号和下划线
            if [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                TARGET_USER="$NEW_USER"
                break
            else
                warn "Invalid username format. Use lowercase letters, numbers, '-' or '_'."
            fi
        done
    fi
    
    # 4. 最终验证与持久化
    echo "$TARGET_USER" > "/tmp/shorin_install_user"
    HOME_DIR="/home/$TARGET_USER"
    export TARGET_USER HOME_DIR
}

# 日志文件
export TEMP_LOG_FILE="/tmp/log-arch-niri-dms.txt"
[ ! -f "$TEMP_LOG_FILE" ] && touch "$TEMP_LOG_FILE" && chmod 666 "$TEMP_LOG_FILE"

# --- 2. 基础工具 ---
write_log() {
    # Strip ANSI colors for log file
    local clean_msg=$(echo -e "$2" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date '+%H:%M:%S')] [$1] $clean_msg" >> "$TEMP_LOG_FILE"
}

# --- 3. 视觉组件 (TUI Style) ---

# 绘制分割线
hr() {
    printf "${H_GRAY}%*s${NC}\n" "${COLUMNS:-80}" '' | tr ' ' '─'
}

# 绘制大标题 (Section)
section() {
    local title="$1"
    local subtitle="$2"
    echo ""
    echo -e "${H_PURPLE}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${H_PURPLE}│${NC} ${BOLD}${H_WHITE}$title${NC}"
    echo -e "${H_PURPLE}│${NC} ${H_CYAN}$subtitle${NC}"
    echo -e "${H_PURPLE}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
    write_log "SECTION" "$title - $subtitle"
}

# 绘制键值对信息
info_kv() {
    local key="$1"
    local val="$2"
    local extra="$3"
    printf "   ${H_BLUE}●${NC} %-15s : ${BOLD}%s${NC} ${DIM}%s${NC}\n" "$key" "$val" "$extra"
    write_log "INFO" "$key=$val"
}

# 普通日志
log() {
    echo -e "   $ARROW $1"
    write_log "LOG" "$1"
}

# 成功日志
success() {
    echo -e "   $TICK ${H_GREEN}$1${NC}"
    write_log "SUCCESS" "$1"
}

# 警告日志 (突出显示)
warn() {
    echo -e "   $WARN ${H_YELLOW}${BOLD}WARNING:${NC} ${H_YELLOW}$1${NC}"
    write_log "WARN" "$1"
}

# 错误日志 (非常突出)
error() {
    echo -e ""
    echo -e "${H_RED}   ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${H_RED}   ┃  ERROR: $1${NC}"
    echo -e "${H_RED}   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e ""
    write_log "ERROR" "$1"
}

# --- 4. 核心：命令执行器 (Command Exec) ---
exe() {
    local full_command="$*"
    
    # Visual: 显示正在运行的命令
    echo -e "   ${H_GRAY}┌──[ ${H_MAGENTA}EXEC${H_GRAY} ]────────────────────────────────────────────────────${NC}"
    echo -e "   ${H_GRAY}│${NC} ${H_CYAN}$ ${NC}${BOLD}$full_command${NC}"
    
    write_log "EXEC" "$full_command"
    
    # Run the command
    "$@"
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo -e "   ${H_GRAY}└──────────────────────────────────────────────────────── ${H_GREEN}OK${H_GRAY} ─┘${NC}"
    else
        echo -e "   ${H_GRAY}└────────────────────────────────────────────────────── ${H_RED}FAIL${H_GRAY} ─┘${NC}"
        write_log "FAIL" "Exit Code: $status"
        return $status
    fi
}

# 静默执行
exe_silent() {
    "$@" > /dev/null 2>&1
}

# --- 5. 可复用逻辑块 ---

as_user() {
    runuser -u "$TARGET_USER" -- "$@"
}


hide_desktop_file() {
    local source_file="$1"
    local filename=$(basename "$source_file")
    local user_dir="$HOME_DIR/.local/share/applications"
    local target_file="$user_dir/$filename"
    
    mkdir -p "$user_dir"
    
    if [[ -f "$source_file" ]]; then
        cp -fv "$source_file" "$target_file"
        if grep -q "^NoDisplay=" "$target_file"; then
            sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$target_file"
        else
            echo "NoDisplay=true" >> "$target_file"
        fi
        chown "$TARGET_USER:" "$target_file"
    fi
}

# 批量执行
run_hide_desktop_file() {
    
    local apps_to_hide=(
        "avahi-discover.desktop"
        "qv4l2.desktop"
        "qvidcap.desktop"
        "bssh.desktop"
        "org.fcitx.Fcitx5.desktop"
        "org.fcitx.fcitx5-migrator.desktop"
        "xgps.desktop"
        "xgpsspeed.desktop"
        "gvim.desktop"
        "kbd-layout-viewer5.desktop"
        "bvnc.desktop"
        "yazi.desktop"
        "btop.desktop"
        "vim.desktop"
        "nvtop.desktop"
        "mpv.desktop"
        "org.gnome.Settings.desktop"
        "thunar-settings.desktop"
        "thunar-bulk-rename.desktop"
        "thunar-volman-settings.desktop"
        "clipse-gui.desktop"
        "waypaper.desktop"
        "xfce4-about.desktop"
        "cmake-gui.desktop"
        "assistant.desktop"
        "qdbusviewer.desktop"
        "linguist.desktop"
        "designer.desktop"
        "org.kde.drkonqi.coredump.gui.desktop"
        "org.kde.kwrite.desktop"
        "org.freedesktop.MalcontentControl.desktop"
        "org.gnome.Nautilus.desktop"
        "lstopo.desktop"
    )
    
    echo "正在隐藏不需要的桌面图标..."
    
    # 用一个 for 循环搞定所有调用
    for app in "${apps_to_hide[@]}"; do
        hide_desktop_file "/usr/share/applications/$app"
    done
    chown -R "$TARGET_USER:" "$HOME_DIR/.local/share/applications"
    
    echo "图标隐藏完成！"
}

# ==============================================================================
# check_dm_conflict - 检测现有的显示管理器冲突，并让用户选择是否启用新 DM
# ==============================================================================
# 使用方法: check_dm_conflict
# 结果: 设置全局变量 $SKIP_DM (true/false)
check_dm_conflict() {
    local KNOWN_DMS=(
        "lemurs" "ly"
        "gdm" "lightdm" "lxdm" "plasma-login-manager" "sddm"
        "greetd"
    )
    export SKIP_DM=false
    local DM_FOUND=""
    
    for dm in "${KNOWN_DMS[@]}"; do
        if pacman -Q "$dm" &>/dev/null; then
            DM_FOUND="$dm"
            break
        fi
    done
    
    if [ -n "$DM_FOUND" ]; then
        info_kv "Conflict" "${H_RED}$DM_FOUND${NC}"
        export SKIP_DM=true
    else
        
        if read -t 20 -p "$(echo -e "   ${H_CYAN}Enable Display Manager ? [Y/n] (Default Y): ${NC}")" choice </dev/tty; then
            
            if [[ "$choice" =~ ^[[:space:]]*[Nn](o|O)?[[:space:]]*$ ]]; then
                export SKIP_DM=true
            else
                export SKIP_DM=false
            fi
        else
            
            echo " Y (Auto-default)"
            export SKIP_DM=false
        fi
    fi
}

# ==============================================================================
# setup_ly - 安装并配置 ly 显示管理器
# ==============================================================================
setup_ly() {
    log "Installing ly display manager..."
    exe pacman -S --noconfirm --needed ly
    
    # 启用服务
    log "Enabling ly service..."
    systemctl enable ly@tty1
    
    success "ly display manager has been successfully configured!"
}