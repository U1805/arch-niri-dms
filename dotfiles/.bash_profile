#
# ~/.bash_profile
# bash for pi agent

# bun 全局 bin 目录
export PATH="$HOME/.bun/bin:$PATH"
# bb-browser 连接 flatpak Chrome CDP
export BB_BROWSER_CDP_URL="http://127.0.0.1:9222"
# 系统代理环境变量（login shell 全局生效）
export http_proxy="http://127.0.0.1:7900"
export https_proxy="http://127.0.0.1:7900"
export HTTP_PROXY="http://127.0.0.1:7900"
export HTTPS_PROXY="http://127.0.0.1:7900"
export all_proxy="http://127.0.0.1:7900"
export ALL_PROXY="http://127.0.0.1:7900"
export no_proxy="localhost,127.0.0.1,::1,.local"
export NO_PROXY="localhost,127.0.0.1,::1,.local"

[[ -f ~/.bashrc ]] && . ~/.bashrc
