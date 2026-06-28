if status is-interactive
    # Commands to run in interactive sessions can go here
end
set fish_greeting ""
set -p PATH ~/.local/bin
starship init fish | source
zoxide init fish --cmd cd | source
# 111
function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

function cat
    command bat $argv
end
function ls
    command eza --icons $argv
end

function lt
    command eza --icons --tree $argv
end
# grub
abbr grub 'LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 sudo grub-mkconfig -o /boot/grub/grub.cfg'
# fa运行fastfetch
abbr fa fastfetch
abbr reboot 'systemctl reboot'
function sl
    command sl | lolcat
end
function 滚
    sysup
end

function 安装
    command yay -S $argv
end

function 卸载
    command yay -Rns $argv
end

# 系统代理开关 (http://127.0.0.1:7900)
function proxy_on
    export http_proxy="http://127.0.0.1:7900"
    export https_proxy="http://127.0.0.1:7900"
    export HTTP_PROXY="http://127.0.0.1:7900"
    export HTTPS_PROXY="http://127.0.0.1:7900"
    export all_proxy="http://127.0.0.1:7900"
    export ALL_PROXY="http://127.0.0.1:7900"
    export no_proxy="localhost,127.0.0.1,::1,.local"
    export NO_PROXY="localhost,127.0.0.1,::1,.local"
    echo "Proxy ON: http://127.0.0.1:7900"
end

function proxy_off
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    echo "Proxy OFF"
end
