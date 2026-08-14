#!/usr/bin/env bash

set -euo pipefail

readonly direct_speed_limit="${GITHUB_DIRECT_SPEED_LIMIT:-40960}"
readonly direct_speed_time="${GITHUB_DIRECT_SPEED_TIME:-20}"
readonly -a proxy_prefixes=(
    "https://gh-proxy.com/"
    "https://gh-proxy.org/"
)

url_host() {
    local url="$1" authority
    authority=${url#https://}
    authority=${authority%%/*}
    authority=${authority##*@}
    printf '%s\n' "${authority%%:*}" | tr '[:upper:]' '[:lower:]'
}

original_url() {
    local url="$1" prefix
    for prefix in "${proxy_prefixes[@]}"; do
        if [[ "$url" == "${prefix}"https://* ]]; then
            printf '%s\n' "${url#"$prefix"}"
            return
        fi
    done
    printf '%s\n' "$url"
}

is_sensitive_url() {
    local lower_url
    lower_url=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    [[ "$1" == https://*'@'* ]] ||
        [[ "$lower_url" =~ [\?\&](access_token|auth|jwt|key|signature|sig|token|x-amz-[^=]*)= ]]
}

is_public_github_url() {
    local url="$1" host
    [[ "$url" == https://* ]] || return 1
    is_sensitive_url "$url" && return 1
    host=$(url_host "$url")
    case "$host" in
        api.github.com|github.com|*.github.com|githubusercontent.com|*.githubusercontent.com|githubassets.com|*.githubassets.com)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

if [[ "${1:-}" == "--classify" ]]; then
    url=$(original_url "${2:?URL is required}")
    if is_public_github_url "$url"; then
        printf 'direct-proxy-chain\t%s\n' "$url"
    else
        printf 'direct\t%s\n' "$url"
    fi
    exit 0
fi

output=${1:?output path is required}
url=$(original_url "${2:?URL is required}")
host=$(url_host "$url")
download_complete=false

cleanup_incomplete_download() {
    if [[ "$download_complete" != true ]]; then
        rm -f -- "$output"
    fi
}
trap cleanup_incomplete_download EXIT
trap 'exit 130' INT TERM

curl_download() {
    local candidate="$1"
    rm -f -- "$output"
    /usr/bin/curl -q -g -b "" -fL \
        --retry 0 --connect-timeout 15 \
        --speed-limit "$direct_speed_limit" --speed-time "$direct_speed_time" \
        -o "$output" "$candidate"
}

if ! is_public_github_url "$url"; then
    /usr/bin/curl -q -g -b "" -fL \
        --retry 3 --retry-delay 3 --retry-connrefused --connect-timeout 15 \
        -o "$output" "$url"
    download_complete=true
    exit 0
fi

printf '==> Try GitHub directly (%s); fall back after %ss below %s B/s\n' \
    "$host" "$direct_speed_time" "$direct_speed_limit" >&2
if curl_download "$url"; then
    download_complete=true
    exit 0
fi

for proxy_prefix in "${proxy_prefixes[@]}"; do
    printf '==> Retry through %s\n' "${proxy_prefix#https://}" >&2
    if curl_download "${proxy_prefix}${url}"; then
        download_complete=true
        exit 0
    fi
done

printf '==> GitHub direct download and all proxy fallbacks failed: %s\n' "$url" >&2
exit 1
