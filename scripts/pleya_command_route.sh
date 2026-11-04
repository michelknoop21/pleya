# shellcheck shell=bash
# The installed paths are explicit; neither an alias nor a PATH change is needed.
pleya_route_command() {
    pleya_route_kind=$1
    pleya_route_launcher=$2
    pleya_route_mode=$3
    shift 3
    if python3 /Users/michelknoop/bin/pleya-heavy-route "$pleya_route_kind" "$@"; then
        return
    else
        pleya_route_result=$?
    fi
    if [ "$pleya_route_result" -ne 10 ]; then exit "$pleya_route_result"; fi
    if [ -n "${PLEYA_HEAVY_QUEUE_FDS:-}" ]; then
        if /Users/michelknoop/bin/pleya-heavy scope; then
            return
        else
            pleya_route_result=$?
        fi
        if [ "$pleya_route_result" -ne 10 ]; then exit "$pleya_route_result"; fi
    fi
    if [ "$pleya_route_mode" = shell ]; then
        exec /Users/michelknoop/bin/pleya-heavy run --label "route-$pleya_route_kind" -- bash "$pleya_route_launcher" "$@"
    fi
    if [ "$pleya_route_mode" = shell-fixed ]; then
        exec /Users/michelknoop/bin/pleya-heavy run --label "route-$pleya_route_kind" -- /bin/bash "$pleya_route_launcher" "$@"
    fi
    exec /Users/michelknoop/bin/pleya-heavy run --label "route-$pleya_route_kind" -- "$pleya_route_launcher" "$@"
}
