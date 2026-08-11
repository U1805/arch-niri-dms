# ==============================================================================
# Function: apt (Smart Arch Package Manager Wrapper for Fish)
# Description: Maps common Debian 'apt' commands to Arch package operations.
# Features:
#   - Source-aware routing: official packages use pacman; AUR packages use paru.
#   - Safe privilege handling: pacman uses sudo; paru always runs as the user.
#   - Anti-partial-upgrade: update/upgrade begins with a complete pacman -Syu.
#   - Deep Clean Default: Merges remove/purge into -Rns for a pristine system.
#   - UI Integration: Progressive enhancement with 'shorin' for interactive modes.
#   - Safe orphan detection and i18n support.
#   - Highly readable, colorized, and column-aligned help output.
# Usage: apt {update|upgrade|install [ui]|remove [ui]|search|show|autoremove|clean|help|-h} [pkg...]
# ==============================================================================

function apt -d "Arch package wrapper routing official packages to pacman and AUR packages to paru"
    # 1. 极简的 Locale 探测
    set -l is_zh 0
    if string match -q -r "^zh_" "$LC_ALL" "$LC_MESSAGES" "$LANG"
        set is_zh 1
    end

    # 2. 探测 shorin UI 工具是否存在
    set -l has_shorin 0
    if command -q shorin
        set has_shorin 1
    end

    set -l action "help"
    set -l exit_code 0

    if test (count $argv) -eq 0
        set exit_code 1
    else
        set action $argv[1]
        set -e argv[1]
    end

    # 3. 帮助信息拦截与本地化 (重构的高颜值排版)
    switch $action
        case help -h --help
            set -l c_cmd (set_color cyan)
            set -l c_hl  (set_color yellow)
            set -l c_rst (set_color normal)

            if test $is_zh -eq 1
                echo "Arch 包管理器包装器 ("$c_hl"官方仓库: pacman；AUR: paru"$c_rst")"
                echo "用法: "$c_hl"apt"$c_rst" <命令> [软件包...]"
                echo ""
                echo "命令:"
                echo "  "$c_cmd"update(upgrade)"$c_rst"  同步数据库并更新系统 (-Syu)"
                echo "  "$c_cmd"install        "$c_rst"  安装软件包 (-S)"
                if test $has_shorin -eq 1
                    echo "  "$c_cmd"install ui     "$c_rst"  打开交互式界面安装 (依赖: shorin-contrib-git)"
                end
                echo "  "$c_cmd"remove         "$c_rst"  彻底卸载软件包、依赖及配置文件 (-Rns)"
                if test $has_shorin -eq 1
                    echo "  "$c_cmd"remove ui      "$c_rst"  打开交互式界面卸载 (依赖: shorin-contrib-git)"
                end
                echo "  "$c_cmd"search         "$c_rst"  搜索软件包 (-Ss)"
                echo "  "$c_cmd"show           "$c_rst"  显示软件包详细信息 (-Si)"
                echo "  "$c_cmd"autoremove     "$c_rst"  安全地清理系统中的孤立软件包"
                echo "  "$c_cmd"clean          "$c_rst"  清理下载缓存 (-Sc)"
                echo "  "$c_cmd"help, -h       "$c_rst"  显示此帮助信息"
            else
                echo "Smart Arch Package Wrapper ("$c_hl"official: pacman; AUR: paru"$c_rst")"
                echo "Usage: "$c_hl"apt"$c_rst" <command> [package...]"
                echo ""
                echo "Commands:"
                echo "  "$c_cmd"update(upgrade)"$c_rst"  Sync databases and update system (Safe -Syu)"
                echo "  "$c_cmd"install        "$c_rst"  Install packages (-S)"
                if test $has_shorin -eq 1
                    echo "  "$c_cmd"install ui     "$c_rst"  Open interactive installation UI (shorin pac)"
                end
                echo "  "$c_cmd"remove         "$c_rst"  Remove packages, unneeded dependencies, and configs (-Rns)"
                if test $has_shorin -eq 1
                    echo "  "$c_cmd"remove ui      "$c_rst"  Open interactive removal UI (shorin pacr)"
                end
                echo "  "$c_cmd"search         "$c_rst"  Search for packages (-Ss)"
                echo "  "$c_cmd"show           "$c_rst"  Show package details (-Si)"
                echo "  "$c_cmd"autoremove     "$c_rst"  Remove orphaned packages safely"
                echo "  "$c_cmd"clean          "$c_rst"  Clean package cache (-Sc)"
                echo "  "$c_cmd"help, -h       "$c_rst"  Show this help message"
            end
            return $exit_code
    end

    # 4. 预定义基础错误信息 (本地化)
    set -l msg_err_pkg "Error: Specify packages."
    set -l msg_err_search "Error: Specify search term."
    set -l msg_err_show "Error: Specify package to show."
    if test $is_zh -eq 1
        set msg_err_pkg "错误：请指定要操作的软件包。"
        set msg_err_search "错误：请指定搜索词。"
        set msg_err_show "错误：请指定要查看的软件包。"
    end

    # 5. 动作映射 (Action Mapping)
    switch $action
        case update upgrade
            sudo pacman -Syu; or return $status
            if command -q paru
                paru -Sua
            end
        case install
            if test (count $argv) -eq 0; echo $msg_err_pkg; return 1; end
            # 拦截 'install ui'，条件：且只输入了 ui 一个参数，且系统存在 shorin
            if test "$argv[1]" = "ui" -a (count $argv) -eq 1 -a $has_shorin -eq 1
                shorin pac
                return 0
            end

            set -l official_packages
            set -l aur_packages
            for package in $argv
                if pacman -Si -- "$package" >/dev/null 2>&1
                    set -a official_packages "$package"
                else
                    set -a aur_packages "$package"
                end
            end

            if test (count $official_packages) -gt 0
                sudo pacman -S --needed -- $official_packages; or return $status
            end
            if test (count $aur_packages) -gt 0
                if not command -q paru
                    echo "Error: paru is required for non-repository packages: $aur_packages" >&2
                    return 127
                end
                paru -S --needed -- $aur_packages
            end
        case remove
            if test (count $argv) -eq 0; echo $msg_err_pkg; return 1; end
            # 拦截 'remove ui'
            if test "$argv[1]" = "ui" -a (count $argv) -eq 1 -a $has_shorin -eq 1
                shorin pacr
                return 0
            end
            sudo pacman -Rns -- $argv
        case search
            if test (count $argv) -eq 0; echo $msg_err_search; return 1; end
            pacman -Ss $argv
        case show
            if test (count $argv) -eq 0; echo $msg_err_show; return 1; end
            if not pacman -Si -- $argv
                command -q paru; and paru -Si -- $argv
            end
        case autoremove
            set -l orphans (pacman -Qtdq)
            if test (count $orphans) -gt 0
                if test $is_zh -eq 1
                    echo "找到 "(count $orphans)" 个孤立的软件包。正在通过 pacman 卸载..."
                else
                    echo "Found "(count $orphans)" orphaned package(s). Removing via pacman..."
                end
                sudo pacman -Rns -- $orphans
            else
                if test $is_zh -eq 1
                    echo "系统很干净，没有需要清理的孤立软件包。"
                else
                    echo "System is clean. No orphaned packages to remove."
                end
            end
        case clean
            sudo pacman -Sc
        case '*'
            if test $is_zh -eq 1
                echo "错误：不支持的 apt 命令映射: $action"
                echo "运行 'apt -h' 查看可用命令。"
            else
                echo "Error: Unsupported apt command mapped: $action"
                echo "Run 'apt -h' for valid commands."
            end
            return 1
    end
end
