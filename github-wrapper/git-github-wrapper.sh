#!/usr/bin/env bash

set -euo pipefail

readonly real_git="/usr/bin/git"
readonly low_speed_limit="${GITHUB_DIRECT_SPEED_LIMIT:-40960}"
readonly low_speed_time="${GITHUB_DIRECT_SPEED_TIME:-20}"
readonly -a proxy_prefixes=(
    "https://gh-proxy.com/"
    "https://gh-proxy.org/"
)

args=("$@")
clone_index=-1
url_index=-1

for index in "${!args[@]}"; do
    [[ "${args[$index]}" == clone ]] && clone_index=$index
    if [[ "${args[$index]}" == https://github.com/* ]]; then
        url_index=$index
        break
    fi
done

# Only public HTTPS GitHub clones are routed. All other Git operations retain
# their normal behavior, including authenticated URLs and existing remotes.
if (( clone_index < 0 || url_index < 0 )); then
    exec "$real_git" "${args[@]}"
fi

original_url=${args[$url_index]}
if [[ "$original_url" == https://*'@'* || "$original_url" == *'?'* ]]; then
    exec "$real_git" "${args[@]}"
fi

destination=""
destination_existed=true
if (( url_index + 1 < ${#args[@]} )); then
    destination=${args[$((url_index + 1))]}
elif [[ "$original_url" == *.git ]]; then
    destination=${original_url##*/}
    destination=${destination%.git}
fi
if [[ -n "$destination" && ! -e "$destination" ]]; then
    destination_existed=false
fi

cleanup_new_destination() {
    if [[ "$destination_existed" == false && -n "$destination" && -e "$destination" ]]; then
        rm -rf -- "$destination"
    fi
}
trap cleanup_new_destination EXIT
trap 'exit 130' INT TERM

git_clone() {
    local candidate="$1"
    cleanup_new_destination
    args[$url_index]=$candidate
    GIT_HTTP_LOW_SPEED_LIMIT="$low_speed_limit" \
    GIT_HTTP_LOW_SPEED_TIME="$low_speed_time" \
        "$real_git" "${args[@]}"
}

printf '==> Try GitHub clone directly; fall back after %ss below %s B/s\n' \
    "$low_speed_time" "$low_speed_limit" >&2
if git_clone "$original_url"; then
    destination_existed=true
    exit 0
fi

for proxy_prefix in "${proxy_prefixes[@]}"; do
    printf '==> Retry Git clone through %s\n' "${proxy_prefix#https://}" >&2
    if git_clone "${proxy_prefix}${original_url}"; then
        destination_existed=true
        exit 0
    fi
done

printf '==> GitHub clone and all proxy fallbacks failed: %s\n' "$original_url" >&2
exit 1
