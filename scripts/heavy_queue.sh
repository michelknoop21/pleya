# shellcheck shell=sh
# Shared re-entry guard for shell entrypoints. No ambient flag can skip a lock.
pleya_queue_script() {
    if [ "$(uname -s)" != "Darwin" ] && [ -z "${PLEYA_HEAVY_QUEUE_DIR:-}" ]; then
        return
    fi
    pleya_script=$1
    pleya_shell=$2
    shift 2
    pleya_directory=$(CDPATH='' cd -- "$(dirname -- "$pleya_script")" && pwd -P) || exit 75
    pleya_script="$pleya_directory/$(basename -- "$pleya_script")"
    if [ "${PLEYA_QUEUE_SCRIPT:-}" = "$pleya_script" ]; then
        unset PLEYA_QUEUE_SCRIPT
        python3 "$pleya_directory/heavy_queue.py" owns || exit 75
        return
    fi
    exec python3 "$pleya_directory/heavy_queue.py" run \
        --label "$(basename -- "$pleya_script")" -- \
        env "PLEYA_QUEUE_SCRIPT=$pleya_script" "$pleya_shell" "$pleya_script" "$@"
}
