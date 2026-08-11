#!/bin/bash

# 04-dualboot-fix.sh 的内部组件：配置用户账户

# ==============================================================================
# 配置用户账户和环境。此脚本使用 detect_target_user。
# ==============================================================================

# 1. 加载工具集
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

# 2. 检查 Root 权限
check_root

# ==============================================================================
# 阶段 1：识别用户并同步账户。
# ==============================================================================
section "Phase 3" "Configure the user account"


# 清理缓存
if [ -f "/tmp/shorin_install_user" ]; then
    rm "/tmp/shorin_install_user"
fi
# 调用全局函数，确定目标用户
detect_target_user

# 安全检查：检查系统是否已经拥有这个账户 (无论它是选出来的还是准备新建的)
if id "$TARGET_USER" &>/dev/null; then
    success "The target user $TARGET_USER exists."
    SKIP_CREATION=true
else
    # 语境改变：这里不再是发现它不存在，而是明确准备去创建它
    log "Prepare to create the user: ${H_CYAN}${TARGET_USER}${NC}."
    SKIP_CREATION=false
fi

# ==============================================================================
# 阶段 2：创建账户并配置权限和密码。
# ==============================================================================
section "Step 2/4" "Configure the account and permissions"

if [ "$SKIP_CREATION" = true ]; then
    log "Check the wheel group membership for $TARGET_USER."
    if groups "$TARGET_USER" | grep -q "\bwheel\b"; then
        success "The user is in the wheel group."
    else
        log "Add the user to the wheel group."
        exe usermod -aG wheel "$TARGET_USER"
    fi
else
    log "Create the user $TARGET_USER."
    # 使用 -m 创建家目录，-g wheel 加入特权组
    exe useradd -m -G wheel -s /bin/bash "$TARGET_USER"
    
    log "Set the password for $TARGET_USER."
    echo -e "   ${H_GRAY}--------------------------------------------------${NC}"
    # passwd 必须交互运行
    passwd "$TARGET_USER"
    PASSWORD_STATUS=$?
    echo -e "   ${H_GRAY}--------------------------------------------------${NC}"
    
    if [ $PASSWORD_STATUS -eq 0 ]; then
        success "The password is set."
    else
        error "Password configuration failed. Stop the script."
        exit 1
    fi
fi

# 1. 配置 Sudoers
log "Configure sudo access."

# A. 确保 wheel 组具备基础 sudo 权限 (需要密码)
if grep -q "^# %wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    exe sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    success "The %wheel rule in /etc/sudoers is enabled."
    elif grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    success "sudo access is enabled."
else
    log "Add the %wheel rule to /etc/sudoers."
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
    success "sudo access is configured."
fi

# 删除旧版安装程序创建的永久免密规则。
LEGACY_NOPASSWD_FILE="/etc/sudoers.d/10-shorin-nopasswd"
if [ -f "$LEGACY_NOPASSWD_FILE" ]; then
    log "Remove the old persistent NOPASSWD rule."
    exe rm -f -- "$LEGACY_NOPASSWD_FILE"
    success "The old NOPASSWD rule is removed."
fi

if ! enable_temporary_sudo; then
    exit 1
fi

# 配置用户访问 I2C 设备的权限，并在启动时加载用户态设备接口模块。
log "Configure I2C access for $TARGET_USER."
if getent group i2c >/dev/null; then
    if groups "$TARGET_USER" | grep -qw i2c; then
        success "The user is in the i2c group."
    else
        exe usermod -aG i2c "$TARGET_USER"
        success "$TARGET_USER is added to the i2c group."
    fi
else
    warn "The i2c group does not exist. Skip I2C group membership."
fi

I2C_MODULE_CONF="/etc/modules-load.d/i2c-dev.conf"
if [ ! -f "$I2C_MODULE_CONF" ] || ! grep -qx 'i2c-dev' "$I2C_MODULE_CONF"; then
    printf 'i2c-dev\n' > "$I2C_MODULE_CONF"
fi
success "The system will load the I2C device interface at boot."

# 2. 配置 Faillock (防止输错密码锁定)
log "Configure the password lockout policy."
FAILLOCK_CONF="/etc/security/faillock.conf"
if [ -f "$FAILLOCK_CONF" ]; then
    exe sed -i 's/^#\?\s*deny\s*=.*/deny = 0/' "$FAILLOCK_CONF"
    success "Account lockout is disabled (deny=0)."
fi

# ==============================================================================
# 阶段 3：生成 XDG 用户目录。
# ==============================================================================
section "Step 3/4" "Create user directories"

exe pacman -S --noconfirm --needed xdg-user-dirs

log "Create XDG user directories."
# 获取目标用户最新的家目录路径
REAL_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

# 强制以该用户身份运行更新
if exe runuser -u "$TARGET_USER" -- env LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 HOME="$REAL_HOME" xdg-user-dirs-update --force; then
    success "The user directories are created in $REAL_HOME."
else
    warn "XDG user directory creation failed."
fi

# ==============================================================================
# 阶段 4：配置 PATH 和 .local/bin。
# ==============================================================================
section "Step 4/4" "Configure the user environment"

LOCAL_BIN_PATH="$REAL_HOME/.local/bin"
log "Create the user executable directory: $LOCAL_BIN_PATH."

if exe runuser -u "$TARGET_USER" -- mkdir -p "$LOCAL_BIN_PATH"; then
    success "The user executable directory is ready."
else
    error "The ~/.local/bin directory could not be created."
fi

# 配置全局 PATH
PROFILE_SCRIPT="/etc/profile.d/user_local_bin.sh"
cat << 'EOF' > "$PROFILE_SCRIPT"
# 如果 ~/.local/bin 存在，则将其加入 PATH。
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
EOF
exe chmod 644 "$PROFILE_SCRIPT"
success "The PATH configuration script is installed."

# ==============================================================================
# 完成
# ==============================================================================
hr
success "User $TARGET_USER is configured."
echo ""
