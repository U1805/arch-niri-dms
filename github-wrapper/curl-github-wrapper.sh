#!/usr/bin/env bash

set -euo pipefail

readonly proxy_prefix="https://gh-proxy.org/"

url_host() {
    local url="$1" authority
    authority=${url#https://}
    authority=${authority%%/*}
    authority=${authority##*@}
    printf '%s\n' "${authority%%:*}" | tr '[:upper:]' '[:lower:]'
}

is_sensitive_url() {
    local lower_url
    lower_url=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    [[ "$1" == https://*'@'* ]] ||
        [[ "$lower_url" =~ [\?\&](access_token|auth|jwt|key|signature|sig|token|x-amz-[^=]*)= ]]
}

routing_mode() {
    local url="$1" host
    if [[ "$url" != https://* ]] || is_sensitive_url "$url"; then
        printf 'direct\n'
        return
    fi
    host=$(url_host "$url")
    case "$host" in
        api.github.com)
            # 先使用本机的 API 限额，再尝试更容易受限的共享代理地址。
            printf 'direct-first\n'
            ;;
        uploads.github.com)
            printf 'direct\n'
            ;;
        github.com|*.github.com|githubusercontent.com|*.githubusercontent.com|githubassets.com|*.githubassets.com)
            printf 'proxy-first\n'
            ;;
        *)
            printf 'direct\n'
            ;;
    esac
}

proxy_target() {
    printf '%s%s\n' "$proxy_prefix" "$1"
}

if [[ "${1:-}" == "--classify" ]]; then
    url=${2:?URL is required}
    mode=$(routing_mode "$url")
    printf '%s\t%s\n' "$mode" "$url"
    exit 0
fi

output=${1:?makepkg output path is required}
url=${2:?makepkg source URL is required}
host=$(url_host "$url")

curl_download() {
    /usr/bin/curl -q -g -b "" -fL -C - \
        --retry 3 --retry-delay 3 --retry-connrefused --connect-timeout 15 \
        -o "$output" "$1"
}

mode=$(routing_mode "$url")
case "$mode" in
    proxy-first)
        printf '==> Use the GitHub proxy (%s)\n' "$host" >&2
        if curl_download "$(proxy_target "$url")"; then exit 0; fi
        printf '==> The GitHub proxy failed. Retry the original %s URL\n' "$host" >&2
        curl_download "$url"
        ;;
    direct-first)
        printf '==> Connect directly to the GitHub API (%s)\n' "$host" >&2
        if curl_download "$url"; then exit 0; fi
        printf '==> The direct GitHub API request failed. Retry through the proxy\n' >&2
        curl_download "$(proxy_target "$url")"
        ;;
    direct)
        curl_download "$url"
        ;;
esac
