#!/bin/bash

# ==============================================================================
# 00-utils.sh - 终端界面和公共函数（v4.0）
# ==============================================================================

# ANSI 颜色和样式。echo -e 负责解析这些字面量。
export NC='\033[0m'
export BOLD='\033[1m'
export DIM='\033[2m'
export ITALIC='\033[3m'
export UNDER='\033[4m'
export H_MAGENTA='\033[1;35m'
# 高亮色
export H_RED='\033[1;31m'
export H_GREEN='\033[1;32m'
export H_YELLOW='\033[1;33m'
export H_BLUE='\033[1;34m'
export H_PURPLE='\033[1;35m'
export H_CYAN='\033[1;36m'
export H_WHITE='\033[1;37m'
export H_GRAY='\033[1;90m'

# 标题背景色
export BG_BLUE='\033[44m'
export BG_PURPLE='\033[45m'

# 状态符号
export TICK="${H_GREEN}✔${NC}"
export CROSS="${H_RED}✘${NC}"
export INFO="${H_BLUE}ℹ${NC}"
export WARN="${H_YELLOW}⚠${NC}"
export ARROW="${H_CYAN}➜${NC}"


check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${H_RED}   $CROSS Error: Run this script as root.${NC}"
        exit 1
    fi
}
check_root

# ==============================================================================
# detect_target_user - 选择或创建目标用户
# ==============================================================================
detect_target_user() {
    # 使用缓存中的目标用户。
    if [[ -f "/tmp/shorin_install_user" ]]; then
        TARGET_USER=$(cat "/tmp/shorin_install_user")
        HOME_DIR="/home/$TARGET_USER"
        export TARGET_USER HOME_DIR
        return 0
    fi
    
    log "Detect system users."
    
    # 获取 UID 在 1000 到 59999 之间的用户。
    mapfile -t HUMAN_USERS < <(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd)
    # 优先使用 UID 为 1000 的用户。
    local UID_1000_USER
    UID_1000_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd | head -n 1)
    
    # 如果普通用户存在，显示选择菜单。
    if [[ ${#HUMAN_USERS[@]} -gt 0 ]]; then
        echo -e "   ${H_YELLOW}Select a target user or create one:${NC}"
        
        local default_user=""
        local default_idx=""
        
        # 显示从 1 开始的用户序号。
        for i in "${!HUMAN_USERS[@]}"; do
            local mark=""
            local display_idx=$((i + 1))
            
            # 将 UID 1000 或 SUDO_USER 对应的用户设为默认用户。
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
        
        # 如果没有匹配项，则将列表中的第一个用户设为默认用户。
        if [[ -z "$default_user" ]]; then
            default_user="${HUMAN_USERS[0]}"
            default_idx="1"
        fi
        
        echo -e "       [0] ${H_GREEN}Create a user${NC}"
        
        while true; do
            echo -ne "   ${H_CYAN}Select a user [0-${#HUMAN_USERS[@]}]. Default: ${default_idx}. Timeout: 30 seconds: ${NC}"
            
            # 等待输入 30 秒。
            if ! read -t 30 -r idx; then
                echo # 超时后补充换行。
                TARGET_USER="$default_user"
                log "Input timed out. Select the default user: ${H_CYAN}${TARGET_USER}${NC}."
                break
            fi
            
            # 如果用户直接按回车，则选择默认用户。
            if [[ -z "$idx" && -n "$default_user" ]]; then
                TARGET_USER="$default_user"
                log "Select the default user: ${H_CYAN}${TARGET_USER}${NC}."
                break
            fi
            
            # 检查输入。
            if [[ "$idx" == "0" ]]; then
                TARGET_USER=""
                break
                elif [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#HUMAN_USERS[@]}" ]; then
                TARGET_USER="${HUMAN_USERS[$((idx - 1))]}"
                break
            else
                warn "The selection is not valid. Enter a number from the list."
            fi
        done
    else
        if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
            TARGET_USER="$SUDO_USER"
        else
            echo -e "   ${H_YELLOW}No standard user exists.${NC}"
            TARGET_USER=""
        fi
    fi
    
    # 如果没有目标用户，则读取新用户名。
    if [[ -z "$TARGET_USER" ]]; then
        while true; do
            echo -ne "   ${H_GREEN}Enter the new user name: ${NC}"
            read -r NEW_USER
            
            # 用户名只能包含小写字母、数字、连字符和下划线。
            if [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                TARGET_USER="$NEW_USER"
                break
            else
                warn "The user name is not valid. Use lowercase letters, numbers, hyphens, or underscores."
            fi
        done
    fi
    
    # 保存目标用户。
    echo "$TARGET_USER" > "/tmp/shorin_install_user"
    HOME_DIR="/home/$TARGET_USER"
    export TARGET_USER HOME_DIR
}

enable_temporary_sudo() {
    local sudo_file="/etc/sudoers.d/99-shorin-installer-temp"
    local sudo_rule="$TARGET_USER ALL=(ALL:ALL) NOPASSWD: ALL"

    if [[ -f "$sudo_file" ]] && grep -Fqx -- "$sudo_rule" "$sudo_file"; then
        return 0
    fi

    log "Configure a temporary NOPASSWD rule."
    install -d -m 0750 /etc/sudoers.d
    rm -f -- "$sudo_file"
    printf '%s\n' "$sudo_rule" >"$sudo_file"
    chmod 0440 "$sudo_file"

    if ! visudo -cf "$sudo_file" >/dev/null; then
        rm -f -- "$sudo_file"
        error "The temporary NOPASSWD rule is not valid."
        return 1
    fi

    success "The temporary NOPASSWD rule is active. The installer will remove it on exit."
}

# 日志文件
export TEMP_LOG_FILE="/tmp/log-arch-niri-dms.txt"
[ ! -f "$TEMP_LOG_FILE" ] && touch "$TEMP_LOG_FILE" && chmod 666 "$TEMP_LOG_FILE"

# 日志函数
write_log() {
    # 删除日志文本中的 ANSI 颜色代码。
    local clean_msg=$(echo -e "$2" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date '+%H:%M:%S')] [$1] $clean_msg" >> "$TEMP_LOG_FILE"
}

# 终端界面函数

# 绘制分割线
hr() {
    printf "${H_GRAY}%*s${NC}\n" "${COLUMNS:-80}" '' | tr ' ' '─'
}

# 显示章节标题。
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

# 显示警告。
warn() {
    echo -e "   $WARN ${H_YELLOW}${BOLD}Warning:${NC}${H_YELLOW} $1${NC}"
    write_log "WARN" "$1"
}

# 显示错误。
error() {
    echo -e ""
    echo -e "${H_RED}   ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${H_RED}   ┃  Error: $1${NC}"
    echo -e "${H_RED}   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e ""
    write_log "ERROR" "$1"
}

# 运行命令并显示结果。
exe() {
    local full_command="$*"
    
    echo -e "   ${H_GRAY}┌──[ ${H_MAGENTA}EXEC${H_GRAY} ]────────────────────────────────────────────────────${NC}"
    echo -e "   ${H_GRAY}│${NC} ${H_CYAN}$ ${NC}${BOLD}$full_command${NC}"
    
    write_log "EXEC" "$full_command"
    
    "$@"
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo -e "   ${H_GRAY}└──────────────────────────────────────────────────────── ${H_GREEN}OK${H_GRAY} ─┘${NC}"
    else
        echo -e "   ${H_GRAY}└────────────────────────────────────────────────────── ${H_RED}FAIL${H_GRAY} ─┘${NC}"
        write_log "FAIL" "Exit code: $status"
        return $status
    fi
}

# 静默执行
exe_silent() {
    "$@" > /dev/null 2>&1
}

as_user() {
    runuser -u "$TARGET_USER" -- "$@"
}
