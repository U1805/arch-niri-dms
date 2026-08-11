function proxy_on --description "Enable the local HTTP proxy"
    set -l proxy_url "http://127.0.0.1:7900"
    set -l bypass "localhost,127.0.0.1,::1,.local"

    set -gx http_proxy "$proxy_url"
    set -gx https_proxy "$proxy_url"
    set -gx HTTP_PROXY "$proxy_url"
    set -gx HTTPS_PROXY "$proxy_url"
    set -gx all_proxy "$proxy_url"
    set -gx ALL_PROXY "$proxy_url"
    set -gx no_proxy "$bypass"
    set -gx NO_PROXY "$bypass"

    echo "Proxy ON: $proxy_url"
end

function proxy_off --description "Disable the local HTTP proxy"
    set -e http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
    set -e all_proxy ALL_PROXY no_proxy NO_PROXY
    echo "Proxy OFF"
end
