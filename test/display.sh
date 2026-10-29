# Display server helpers sourced by run.sh.
#
# start_display VARIANT fills display_env with the variables Vim needs to
# reach a private display server, or sets skip_reason and returns 1 when
# the variant cannot run here.  stop_display tears the servers down.
#
# Variants: none has no display; x11 is an Xvfb server; wayland is a
# headless sway compositor; xwayland is that compositor with Xwayland,
# reached through its X display only.
#
# A Wayland client exchanges the clipboard only while it has keyboard
# focus, and a headless seat has no keyboard, so the wayland variant keeps a
# virtual keyboard connected; display_keyboard tells whether it could.

display_env=()
skip_reason=
display_pids=()
display_keyboard=

wait_for() {
    local tries=0
    until "$@"; do
        tries=$((tries + 1))
        if [ "$tries" -ge 100 ]; then
            return 1
        fi
        sleep 0.1
    done
}

file_has_content() {
    [ -s "$1" ]
}

start_xvfb() {
    if ! command -v Xvfb >/dev/null 2>&1; then
        skip_reason="Xvfb not found"
        return 1
    fi
    local number_file="$scratch/xvfb.display"
    : >"$number_file"
    Xvfb -displayfd 3 -screen 0 1280x800x24 -nolisten tcp 3>"$number_file" >"$scratch/xvfb.log" 2>&1 &
    display_pids+=($!)
    if ! wait_for file_has_content "$number_file"; then
        skip_reason="Xvfb did not start, see $scratch/xvfb.log"
        return 1
    fi
    display_env=("DISPLAY=:$(tr -d '[:space:]' <"$number_file")" "GDK_BACKEND=x11")
}

start_sway() {
    local with_xwayland=$1
    if ! command -v sway >/dev/null 2>&1; then
        skip_reason="sway not found"
        return 1
    fi
    local config="$scratch/sway.conf"
    local env_file="$scratch/sway.env"
    local log="$scratch/sway.log"
    : >"$env_file"
    if [ "$with_xwayland" = yes ]; then
        if ! command -v Xwayland >/dev/null 2>&1; then
            skip_reason="Xwayland not found"
            return 1
        fi
        # sway binds the X socket itself and needs the directory present
        if [ ! -d /tmp/.X11-unix ]; then
            skip_reason="/tmp/.X11-unix is missing"
            return 1
        fi
        printf 'xwayland force\n' >"$config"
    else
        printf 'xwayland disable\n' >"$config"
    fi
    # sway names its sockets itself and exports them to the commands it runs
    printf 'exec printf "%%s\\n" "$WAYLAND_DISPLAY" "$DISPLAY" >"%s"\n' "$env_file" >>"$config"
    env -i "${base_env[@]}" WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 \
        sway -c "$config" >"$log" 2>&1 &
    display_pids+=($!)
    if ! wait_for file_has_content "$env_file"; then
        skip_reason="sway did not start, see $log"
        return 1
    fi
    if [ "$with_xwayland" = yes ]; then
        local display
        display=$(sed -n 2p "$env_file")
        if [ -z "$display" ]; then
            skip_reason="sway started without Xwayland, see $log"
            return 1
        fi
        display_env=("DISPLAY=$display" "GDK_BACKEND=x11")
    else
        display_env=("WAYLAND_DISPLAY=$(sed -n 1p "$env_file")" "GDK_BACKEND=wayland")
        start_virtual_keyboard
    fi
}

# wtype creates a virtual keyboard and keeps it while it waits to type, so
# a long delay gives the seat a keyboard for the whole variant
start_virtual_keyboard() {
    display_keyboard=
    if ! command -v wtype >/dev/null 2>&1; then
        return
    fi
    env -i "${base_env[@]}" "${display_env[@]}" wtype -d 2000000000 x >"$scratch/wtype.log" 2>&1 &
    display_pids+=($!)
    display_keyboard=yes
}

start_display() {
    local variant=$1
    display_env=()
    skip_reason=
    display_pids=()
    display_keyboard=
    case $variant in
        none)
            return 0
            ;;
        x11)
            start_xvfb || { stop_display; return 1; }
            ;;
        wayland)
            start_sway no || { stop_display; return 1; }
            ;;
        xwayland)
            start_sway yes || { stop_display; return 1; }
            ;;
        *)
            skip_reason="unknown display variant $variant"
            return 1
            ;;
    esac
}

stop_display() {
    local pid
    for pid in "${display_pids[@]}"; do
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
    done
    display_pids=()
    display_env=()
}
