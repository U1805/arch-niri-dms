#!/bin/bash

export SHELL=$(command -v bash)

# ==============================================================================
# Shorin Arch Setup - Main Installer (v1.2)
# ==============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_FILE="$BASE_DIR/.install_progress"

# --- Source Visual Engine ---
if [ -f "$SCRIPTS_DIR/00-utils.sh" ]; then
    source "$SCRIPTS_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

# --- Global Cleanup on Exit ---
cleanup_on_exit() {
    rm -f "/tmp/shorin_install_user"
    tput cnorm
}
trap cleanup_on_exit EXIT

# --- Environment ---
export DEBUG=${DEBUG:-0}
export CN_MIRROR=${CN_MIRROR:-0}
export DESKTOP_ENV="shorindmsgit"
export DESKTOP_LABEL="Shorin_DMS_Niri"

# Personal fork preset: the installer is intentionally reduced to one route.
# Keep the order explicit so future changes do not depend on filename sorting.
MODULES=(
    "00-btrfs-init.sh"
    "01a-base.sh"
    "01b-nm-backend.sh"
    "02-musthave.sh"
    "02a-dualboot-fix.sh"
    "03a-user.sh"
    "03b-gpu-driver.sh"
    "03c-snapshot-before-desktop.sh"
    "04h-shorindms-quickshell.sh"
    "05-verify-desktop.sh"
    "07-grub-theme.sh"
    "99-apps.sh"
)

check_root
chmod +x "$SCRIPTS_DIR"/*.sh

# --- ASCII Banners ---
banner1() {
cat << "EOF"
  ██████  ██   ██  ██████  ███████ ██ ███    ██
  ██      ██   ██ ██    ██ ██   ██   ██ ██  ██
  ███████ ███████ ██    ██ ██████  ██ ██ ██  ██
       ██ ██   ██ ██    ██ ██   ██ ██ ██  ██ ██
  ██████  ██   ██  ██████  ██   ██ ██ ██   ████
EOF
}

show_banner() {
    clear
    echo -e "${H_CYAN}"
    banner1
    echo -e "${NC}"
    echo -e "${DIM}   :: Arch Linux Automation ::${NC}"
    echo -e ""
}

sys_dashboard() {
    echo -e "${H_BLUE}╔════ SYSTEM DIAGNOSTICS ══════════════════════════════╗${NC}"
    echo -e "${H_BLUE}║${NC} ${BOLD}Kernel${NC}   : $(uname -r)"
    echo -e "${H_BLUE}║${NC} ${BOLD}User${NC}     : $(whoami)"
    echo -e "${H_BLUE}║${NC} ${BOLD}Desktop${NC}  : ${H_CYAN}${DESKTOP_LABEL}${NC}"
    echo -e "${H_BLUE}║${NC} ${BOLD}Modules${NC}  : ${#MODULES[@]} fixed module(s)"
    
    if [ "$CN_MIRROR" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_YELLOW}CN Optimized (Manual)${NC}"
    elif [ "$DEBUG" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_RED}DEBUG FORCE (CN Mode)${NC}"
    else
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : Global Default"
    fi
    
    if [ -f "$STATE_FILE" ]; then
        done_count=$(wc -l < "$STATE_FILE")
        echo -e "${H_BLUE}║${NC} ${BOLD}Progress${NC} : Resuming ($done_count steps recorded)"
    fi
    echo -e "${H_BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# --- Main Execution ---

clear
show_banner
sys_dashboard

if [ ! -f "$STATE_FILE" ]; then touch "$STATE_FILE"; fi

TOTAL_STEPS=${#MODULES[@]}
CURRENT_STEP=0

log "Initializing installer sequence..."
sleep 0.5

# --- Reflector Mirror Update (State Aware) ---
section "Pre-Flight" "Mirrorlist Optimization"

if grep -q "^REFLECTOR_DONE$" "$STATE_FILE"; then
    echo -e "   ${H_GREEN}✔${NC} Mirrorlist previously optimized."
    echo -e "   ${DIM}   Skipping Reflector steps (Resume Mode)...${NC}"
else
    CURRENT_TZ=$(readlink -f /etc/localtime)
    REFLECTOR_ARGS="--protocol https -a 12 -f 10 --sort rate --save /etc/pacman.d/mirrorlist --verbose"
    
    REFLECTOR_SUCCESS=0
    if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
        echo ""
        echo -e "${H_YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${H_YELLOW}║  DETECTED TIMEZONE: Asia/Shanghai                                ║${NC}"
        echo -e "${H_YELLOW}║  Refreshing mirrors in China can be slow.                        ║${NC}"
        echo -e "${H_YELLOW}║  Do you want to force refresh mirrors with Reflector?            ║${NC}"
        echo -e "${H_YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -t 60 -p "$(echo -e "   ${H_CYAN}Run Reflector?[y/N] (Default No in 60s): ${NC}")" choice
        if [ $? -ne 0 ]; then echo ""; fi
        choice=${choice:-N}
        
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            log "Checking Reflector..."
            if exe pacman -S --noconfirm --needed reflector; then
                log "Running Reflector for China..."
                if exe reflector $REFLECTOR_ARGS -c China; then
                    success "Mirrors updated."
                    REFLECTOR_SUCCESS=1
                else
                    warn "China mirror refresh failed. Trying latest 30 global mirrors..."
                    if exe reflector $REFLECTOR_ARGS --latest 30; then
                        success "Mirrors updated."
                        REFLECTOR_SUCCESS=1
                    else
                        warn "Reflector failed. Continuing with existing mirrors."
                    fi
                fi
            else
                warn "Could not install Reflector. Continuing with existing mirrors."
            fi
        else
            log "Skipping mirror refresh."
        fi
    else
        echo ""
        echo -e "${H_CYAN}Mirror refresh with Reflector is recommended outside China.${NC}"
        read -t 60 -p "$(echo -e "   ${H_CYAN}Run Reflector?[Y/n] (Default Yes in 60s): ${NC}")" choice
        if [ $? -ne 0 ]; then echo ""; fi
        choice=${choice:-Y}
        
        if [[ ! "$choice" =~ ^[Nn]$ ]]; then
            log "Checking Reflector..."
            if exe pacman -S --noconfirm --needed reflector; then
                log "Detecting location for optimization..."
                COUNTRY_CODE=$(curl -s --max-time 2 https://ipinfo.io/country)
                
                if [ -n "$COUNTRY_CODE" ]; then
                    info_kv "Country" "$COUNTRY_CODE" "(Auto-detected)"
                    log "Running Reflector for $COUNTRY_CODE..."
                    if exe reflector $REFLECTOR_ARGS -c "$COUNTRY_CODE"; then
                        success "Mirrors updated."
                        REFLECTOR_SUCCESS=1
                    else
                        warn "Country specific refresh failed. Trying latest 30 global mirrors..."
                        if exe reflector $REFLECTOR_ARGS --latest 30; then
                            success "Mirrors updated."
                            REFLECTOR_SUCCESS=1
                        else
                            warn "Reflector failed. Continuing with existing mirrors."
                        fi
                    fi
                else
                    warn "Could not detect country. Trying latest 30 global mirrors..."
                    if exe reflector $REFLECTOR_ARGS --latest 30; then
                        success "Mirrors updated."
                        REFLECTOR_SUCCESS=1
                    else
                        warn "Reflector failed. Continuing with existing mirrors."
                    fi
                fi
            else
                warn "Could not install Reflector. Continuing with existing mirrors."
            fi
        else
            log "Skipping mirror refresh."
        fi
    fi
    
    if [ "$REFLECTOR_SUCCESS" -eq 1 ]; then
        echo "REFLECTOR_DONE" >> "$STATE_FILE"
    fi
fi

# ---- update keyring-----
section "Pre-Flight" "Update Keyring"

exe pacman -Sy
exe pacman -S --noconfirm archlinux-keyring

# --- Global Update ---
section "Pre-Flight" "System update"
log "Ensuring system is up-to-date..."

if exe pacman -Syu --noconfirm; then
    success "System Updated."
else
    error "System update failed. Check your network."
    exit 1
fi

# --- Module Loop ---
for module in "${MODULES[@]}"; do
    [[ -z "$module" ]] && continue
    
    CURRENT_STEP=$((CURRENT_STEP + 1))
    script_path="$SCRIPTS_DIR/$module"
    
    if [ ! -f "$script_path" ]; then
        error "Module not found: $module"
        continue
    fi
    
    if grep -q "^${module}$" "$STATE_FILE"; then
        echo -e "   ${H_GREEN}✔${NC} Module ${BOLD}${module}${NC} already completed."
        echo -e "   ${DIM}   Skipping... (Delete .install_progress to force run)${NC}"
        continue
    fi
    
    section "Module ${CURRENT_STEP}/${TOTAL_STEPS}" "$module"
    
    bash "$script_path"
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "$module" >> "$STATE_FILE"
        success "Module $module completed."
    elif [ $exit_code -eq 130 ]; then
        echo ""
        warn "Script interrupted by user (Ctrl+C)."
        log "Exiting without rollback. You can resume later."
        exit 130
    else
        write_log "FATAL" "Module $module failed with exit code $exit_code"
        error "Module execution failed."
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# Final Cleanup
# ------------------------------------------------------------------------------
section "Completion" "System Cleanup"

clean_intermediate_snapshots() {
    local config_name="$1"
    local start_marker="Before Shorin Setup"
    
    local KEEP_MARKERS=(
        "Before Desktop Environments"
        "Before Niri Setup"
    )
    
    if ! snapper -c "$config_name" list &>/dev/null; then
        return
    fi
    
    log "Scanning junk snapshots in: $config_name..."
    
    local start_id
    start_id=$(snapper -c "$config_name" list --columns number,description | grep -F "$start_marker" | awk '{print $1}' | tail -n 1)
    
    if [ -z "$start_id" ]; then
        warn "Marker '$start_marker' not found in '$config_name'. Skipping cleanup."
        return
    fi
    
    local IDS_TO_KEEP=()
    for marker in "${KEEP_MARKERS[@]}"; do
        local found_id
        found_id=$(snapper -c "$config_name" list --columns number,description | grep -F "$marker" | awk '{print $1}' | tail -n 1)
        
        if [ -n "$found_id" ]; then
            IDS_TO_KEEP+=("$found_id")
            log "Found protected snapshot: '$marker' (ID: $found_id)"
        fi
    done
    
    local snapshots_to_delete=()
    
    while IFS= read -r line; do
        local id
        local type
        
        id=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{print $3}')
        
        if [[ "$id" =~ ^[0-9]+$ ]]; then
            if [ "$id" -gt "$start_id" ]; then
                
                local skip=false
                for keep in "${IDS_TO_KEEP[@]}"; do
                    if [[ "$id" == "$keep" ]]; then
                        skip=true
                        break
                    fi
                done
                
                if [ "$skip" = true ]; then
                    continue
                fi
                
                if [[ "$type" == "pre" || "$type" == "post" ]]; then
                    snapshots_to_delete+=("$id")
                fi
            fi
        fi
    done < <(snapper -c "$config_name" list --columns number,type)
    
    if [ ${#snapshots_to_delete[@]} -gt 0 ]; then
        log "Deleting ${#snapshots_to_delete[@]} junk snapshots in '$config_name'..."
        if exe snapper -c "$config_name" delete "${snapshots_to_delete[@]}"; then
            success "Cleaned $config_name."
        fi
    else
        log "No junk snapshots found in '$config_name'."
    fi
}

log "Cleaning Pacman/Yay cache..."
exe pacman -Sc --noconfirm

clean_intermediate_snapshots "root"
clean_intermediate_snapshots "home"

for dir in /var/cache/pacman/pkg/download-*/; do
    if [ -d "$dir" ]; then
        echo "Found residual directory: $dir, cleaning up..."
        rm -rf "$dir"
    fi
done

rm -f "/tmp/shorin_install_verify.list"

log "Regenerating final GRUB configuration..."
exe env LANG=en_US.UTF-8 grub-mkconfig -o /boot/grub/grub.cfg

# --- Completion ---
clear
show_banner
echo -e "${H_GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${H_GREEN}║               INSTALLATION  COMPLETE                 ║${NC}"
echo -e "${H_GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

if [ -f "$STATE_FILE" ]; then rm "$STATE_FILE"; fi

log "Archiving log..."
if [ -f "/tmp/shorin_install_user" ]; then
    FINAL_USER=$(cat /tmp/shorin_install_user)
else
    FINAL_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
fi

if [ -n "$FINAL_USER" ]; then
    FINAL_DOCS="/home/$FINAL_USER/Documents"
    mkdir -p "$FINAL_DOCS"
    if [ -f "${TEMP_LOG_FILE:-/tmp/shorin.log}" ]; then
        cp "${TEMP_LOG_FILE:-/tmp/shorin.log}" "$FINAL_DOCS/log-arch-niri-dms.txt"
        chown -R "$FINAL_USER:$FINAL_USER" "$FINAL_DOCS"
        echo -e "   ${H_BLUE}●${NC} Log Saved     : ${BOLD}$FINAL_DOCS/log-arch-niri-dms.txt${NC}"
    fi
fi

echo ""
echo -e "${H_YELLOW}>>> System requires a REBOOT.${NC}"

while read -r -t 0; do read -r; done

for i in {10..1}; do
    echo -ne "\r   ${DIM}Auto-rebooting in ${i}s... (Press 'n' to cancel)${NC}"
    
    read -t 1 -n 1 input
    if [ $? -eq 0 ]; then
        if [[ "$input" == "n" || "$input" == "N" ]]; then
            echo -e "\n\n   ${H_BLUE}>>> Reboot cancelled.${NC}"
            exit 0
        else
            break
        fi
    fi
done

echo -e "\n\n   ${H_GREEN}>>> Rebooting...${NC}"
systemctl reboot
