set fish_greeting ""
if not contains -- "$HOME/.local/bin" $PATH
    set -gx PATH "$HOME/.local/bin" $PATH
end

if status is-interactive
    command -q starship; and starship init fish | source
    command -q zoxide; and zoxide init fish --cmd cd | source

    abbr grub 'LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 sudo grub-mkconfig -o /boot/grub/grub.cfg'
    abbr fa fastfetch
    abbr reboot 'systemctl reboot'
end

function y
    if not command -q yazi
        echo "yazi is not installed." >&2
        return 127
    end

    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

function cat
    if command -q bat
        command bat $argv
    else
        command cat $argv
    end
end

function ls
    if command -q eza
        command eza --icons $argv
    else
        command ls $argv
    end
end

function lt
    if command -q eza
        command eza --icons --tree $argv
    else
        set -l target .
        test (count $argv) -gt 0; and set target $argv[1]
        command find "$target" -maxdepth 2 -print
    end
end
