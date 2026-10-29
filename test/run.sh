#!/usr/bin/env bash
# Runs the vim9-buckler test suite in isolation from the user's session.
#
# Environment:
#   VIM_BIN    terminal Vim binaries separated by spaces, default: vim
#   GVIM_BIN   gVim binaries separated by spaces, default: gvim; empty skips GUI
#   DISPLAYS   display variants to run, default: none x11 wayland xwayland
#   CONFIGS    plugin configurations to run, see matrices.vim
#   CASES      Vim pattern selecting case ids
#   MATRICES   Vim pattern selecting matrix names
#   RESULTS    directory for reports, default: test/results
#   TIMEOUT    seconds per Vim process, default: 1800
#   VERBOSE    1 prints every report line, default prints failures and summaries

set -u

test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(dirname "$test_dir")
results=${RESULTS:-$test_dir/results}
vim_bins=${VIM_BIN-vim}
gvim_bins=${GVIM_BIN-gvim}
displays=${DISPLAYS:-none x11 wayland xwayland}
configs=${CONFIGS:-default nosync}
timeout_seconds=${TIMEOUT:-1800}
verbose=${VERBOSE:-0}

# shellcheck source=display.sh
. "$test_dir/display.sh"

scratch=$(mktemp -d)
mkdir -p "$scratch/home" "$scratch/runtime"
chmod 700 "$scratch/runtime"
trap 'stop_display; rm -rf "$scratch"' EXIT

total_pass=0
total_fail=0
total_skip=0
total_known=0
failed_runs=()
skipped_runs=()
clip_tool=
# The display server where a build and kind ran every case
declare -A full_servers=()

log() {
    printf '%s\n' "$*"
}

# Everything the user's session could leak in is dropped here
base_env=(
    "PATH=$PATH"
    "HOME=$scratch/home"
    "XDG_RUNTIME_DIR=$scratch/runtime"
    "TERM=xterm-256color"
    "LANG=C.UTF-8"
    "LC_ALL=C.UTF-8"
    "NO_AT_BRIDGE=1"
)

# Asks a Vim binary whether an expression holds, without a terminal.  The
# answer depends on the build alone, so each binary is asked each question
# once and later displays reuse the answer.
declare -A vim_answers=()

vim_has() {
    local question="$1 $2"
    if [ -z "${vim_answers[$question]+set}" ]; then
        env -i "${base_env[@]}" "$1" -v --clean --not-a-term -es \
            -c "if $2 | qall! | endif" -c 'cquit!' </dev/null >/dev/null 2>&1
        vim_answers[$question]=$?
    fi
    return "${vim_answers[$question]}"
}

has_gui() {
    vim_has "$1" 'has("gui")'
}

# The plugin needs Vim9 script and the patch its features rely on
supports_plugin() {
    vim_has "$1" 'has("vim9script") && has("patch-9.1.563")'
}

# Terminal Vim reaches a display only through the clipboard
has_clipboard() {
    vim_has "$1" 'has("clipboard")'
}

# A gVim that cannot use the display falls back to terminal mode, and one
# on a compositor without input devices crashes on the first clipboard write
gui_starts() {
    # The subshell exits normally after a crash, so bash reports no signal
    (timeout -s KILL "$timeout_seconds" env -i "${base_env[@]}" "${display_env[@]}" \
        "$1" -f -g --clean --not-a-term \
        -c 'silent! call setreg("+", "x")' \
        -c 'if has("gui_running") | qall! | endif' -c 'cquit!' </dev/null; exit $?) >/dev/null 2>&1
}

# Terminal Vim draws its screen into the log, mostly as escape sequences
# around every fed key.  Only the text is kept, in the layout of the screen:
# a jump to the start of a line breaks the line, a cursor movement becomes
# a space, and a jump right after a line end continues the line it ended,
# which is how Vim writes the last column.  A string sequence ends at its
# terminator or at the end of its line, any other escape at its final byte,
# so a sequence cut short by a kill leaves no payload behind.  The log is
# filtered as one block after Vim exits, as Vim behaves differently when
# its output goes to a pipe.
screen_text() {
    LC_ALL=C sed -i -z 's#\n\(\x1b\[[0-9;]*[Hf]\)#\1#g; s#\x1b\[[0-9]*\(;1\{0,1\}\)\{0,1\}[Hf]#\n#g;
        s#\x1b\[[0-9]*[A-D]# #g; s#\x1b\[[0-9;?>=<]*[ -/]*[@-~]##g;
        s#\x1b[]P][^\x07\x1b\n]*\(\x07\|\x1b\\\)\{0,1\}\(\n\{0,1\}\)#\2#g;
        s#\x1b[ -/]*[0-~]##g; s#[\x01-\x08\x0b-\x1f\x7f]##g;
        s#^\([ \t]*\n\)\+##; s#\n\([ \t]*\n\)\+#\n#g; s#\n[ \t]\+$#\n#' "$1"
}

# Builds the plugin refuses must be left without its autocommands.  Without
# the eval feature every :if is skipped, so the exists() guard is harmless
# there and the listing is the only evidence.
degraded_check() {
    local bin=$1 run_dir=$2 out
    # Without 'nomore' the error list stops at a More prompt that never ends
    out=$(timeout -s KILL "$timeout_seconds" env -i "${base_env[@]}" "$bin" --clean --not-a-term \
        -c 'set nomore' -c "source $repo_dir/plugin/buckler.vim" -c 'augroup' -c 'autocmd' \
        -c 'if exists("g:vim9buckler_loaded") | cquit! | endif' -c 'qall!' \
        </dev/null 2>&1)
    local status=$?
    printf '%s\n' "$out" >"$run_dir/vim.log"
    screen_text "$run_dir/vim.log"
    if [ $status -eq 0 ] && ! printf '%s' "$out" | grep -q '\bbuckler_'; then
        log "SUMMARY $(basename "$bin") degraded: 1 passed, 0 failed, 0 skipped (plugin refused)"
        total_pass=$((total_pass + 1))
    else
        log "FAIL $(basename "$bin") degraded: plugin left autocommands or loaded, see $run_dir/vim.log"
        total_fail=$((total_fail + 1))
        failed_runs+=("$(basename "$bin")/degraded")
    fi
}

# A history length below the minimum must be refused like an unsupported
# build: the plugin reports the length, leaves no autocommands behind and
# does not mark itself loaded.
minimum_lengths="9 0 -1"

minimum_check() {
    local bin=$1 run_dir=$2 length out status pass=0 fail=0
    : >"$run_dir/vim.log"
    for length in $minimum_lengths; do
        out=$(timeout -s KILL "$timeout_seconds" env -i "${base_env[@]}" "$bin" --clean --not-a-term \
            -c 'set nomore' -c "let g:vim9buckler_history_length = $length" \
            -c "source $repo_dir/plugin/buckler.vim" -c 'augroup' -c 'autocmd' \
            -c 'if exists("g:vim9buckler_loaded") || v:errmsg !~# "history length" | cquit! | endif' -c 'qall!' \
            </dev/null 2>&1)
        status=$?
        printf 'history length %s\n%s\n' "$length" "$out" >>"$run_dir/vim.log"
        if [ $status -eq 0 ] && ! printf '%s' "$out" | grep -q '\bbuckler_'; then
            pass=$((pass + 1))
        else
            log "FAIL $(basename "$bin") minimum: length $length left autocommands, loaded or no error, see $run_dir/vim.log"
            fail=$((fail + 1))
        fi
    done
    screen_text "$run_dir/vim.log"
    log "SUMMARY $(basename "$bin") minimum: $pass passed, $fail failed, 0 skipped (plugin refused lengths below ten)"
    total_pass=$((total_pass + pass))
    total_fail=$((total_fail + fail))
    if [ $fail -gt 0 ]; then
        failed_runs+=("$(basename "$bin")/minimum")
    fi
}

# The plugin installed as a package must load through Vim's own startup
# with the vimrc settings in place and record yanks after VimEnter, in
# terminal Vim and in gVim; see startup.vim for the checks.
startup_check() {
    local bin=$1 kind=$2 run_dir=$3 home out status
    local args=(--not-a-term -S "$test_dir/startup.vim")
    if [ "$kind" = gui ]; then
        args=(-f -g "${args[@]}")
    fi
    home=$(mktemp -d "$scratch/startup.XXXXXX")
    mkdir -p "$home/.vim/pack/buckler/start"
    ln -s "$repo_dir" "$home/.vim/pack/buckler/start/vim9-buckler"
    printf 'set clipboard=unnamed\nlet g:vim9buckler_history_length = 12\n' >"$home/.vimrc"
    out=$(timeout -s KILL "$timeout_seconds" env -i "${base_env[@]}" "${display_env[@]}" "HOME=$home" "BUCKLER_RESULTS=$run_dir" \
        "$bin" "${args[@]}" </dev/null 2>&1)
    status=$?
    printf '%s\n' "$out" >"$run_dir/vim.log"
    screen_text "$run_dir/vim.log"
    if [ $status -eq 0 ] && [ -f "$run_dir/failures.txt" ] && [ ! -s "$run_dir/failures.txt" ]; then
        log "SUMMARY $(basename "$bin") startup: 1 passed, 0 failed, 0 skipped (plugin loaded as a package)"
        total_pass=$((total_pass + 1))
    else
        log "FAIL $(basename "$bin") startup: $(paste -sd ';' "$run_dir/failures.txt" 2>/dev/null || echo "exit status $status"), see $run_dir/vim.log"
        total_fail=$((total_fail + 1))
        failed_runs+=("$(basename "$bin")/startup")
    fi
}

# The tool that reads and writes the system clipboard of a display variant
select_clip_tool() {
    clip_tool=
    case $1 in
        wayland)
            if command -v wl-copy >/dev/null 2>&1 && command -v wl-paste >/dev/null 2>&1; then
                clip_tool=wl
            fi
            ;;
        x11|xwayland)
            if command -v xclip >/dev/null 2>&1; then
                clip_tool=xclip
            fi
            ;;
    esac
}

# Turns the FAIL lines of a report into GitHub Actions error annotations
annotate() {
    local report=$1 run=$2
    sed -n 's/^FAIL \(.*\)/\1/p' "$report" | while IFS= read -r id; do
        printf '::error title=%s::%s\n' "$run" "$id"
    done
}

run_process() {
    local bin=$1 kind=$2 display=$3 config=$4 scope=$5
    local name
    name=$(basename "$bin")
    local run_dir="$results/$display/$config/$name-$kind"
    mkdir -p "$run_dir"
    rm -f "$run_dir"/report.txt "$run_dir"/junit.xml "$run_dir"/results.jsonl
    local args=(--clean -S "$test_dir/runner.vim")
    if [ "$kind" = gui ]; then
        args=(-f -g "${args[@]}")
    else
        args=(--not-a-term "${args[@]}")
    fi
    env -i "${base_env[@]}" "${display_env[@]}" \
        "BUCKLER_CONFIG=$config" "BUCKLER_DISPLAY=$display" "BUCKLER_RESULTS=$run_dir" \
        "BUCKLER_CASES=${CASES:-}" "BUCKLER_MATRICES=${MATRICES:-}" "BUCKLER_CLIP_TOOL=$clip_tool" \
        "BUCKLER_SCOPE=$scope" timeout -s KILL "$timeout_seconds" "$bin" "${args[@]}" </dev/null >"$run_dir/vim.log" 2>&1
    local status=$?
    screen_text "$run_dir/vim.log"
    if [ ! -f "$run_dir/report.txt" ]; then
        log "FAIL $display/$config/$name-$kind: no report, exit status $status, see $run_dir/vim.log"
        if [ -n "${GITHUB_ACTIONS:-}" ]; then
            printf '::error title=%s::no report, exit status %s\n' "$display/$config/$name-$kind" "$status"
        fi
        total_fail=$((total_fail + 1))
        failed_runs+=("$display/$config/$name-$kind")
        return
    fi
    if [ "$verbose" = 1 ]; then
        cat "$run_dir/report.txt"
    else
        grep -av '^    ' "$run_dir/report.txt"
    fi
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        annotate "$run_dir/report.txt" "$display/$config/$name-$kind"
    fi
    local summary
    summary=$(grep -a '^SUMMARY' "$run_dir/report.txt")
    local pass fail skip known
    pass=$(printf '%s' "$summary" | sed -n 's/.*: \([0-9]*\) passed.*/\1/p')
    fail=$(printf '%s' "$summary" | sed -n 's/.* \([0-9]*\) failed.*/\1/p')
    skip=$(printf '%s' "$summary" | sed -n 's/.* \([0-9]*\) skipped.*/\1/p')
    known=$(printf '%s' "$summary" | sed -n 's/.* \([0-9]*\) known.*/\1/p')
    total_pass=$((total_pass + ${pass:-0}))
    total_fail=$((total_fail + ${fail:-0}))
    total_skip=$((total_skip + ${skip:-0}))
    total_known=$((total_known + ${known:-0}))
    if [ "${fail:-0}" -gt 0 ] || [ -z "$summary" ]; then
        failed_runs+=("$display/$config/$name-$kind")
    fi
}

run_binary() {
    local bin=$1 kind=$2 display=$3 config
    if ! command -v "$bin" >/dev/null 2>&1; then
        log "SKIP $bin: binary not found"
        skipped_runs+=("$bin: not found")
        return
    fi
    if [ "$kind" = gui ] && ! has_gui "$bin"; then
        log "SKIP $bin: no GUI support"
        skipped_runs+=("$bin: no GUI")
        return
    fi
    if ! supports_plugin "$bin"; then
        if [ "$display" = none ]; then
            local run_dir="$results/$display/degraded/$(basename "$bin")-$kind"
            mkdir -p "$run_dir"
            degraded_check "$bin" "$run_dir"
        fi
        return
    fi
    if [ "$display" = none ]; then
        local run_dir="$results/$display/minimum/$(basename "$bin")-$kind"
        mkdir -p "$run_dir"
        minimum_check "$bin" "$run_dir"
        run_dir="$results/$display/startup/$(basename "$bin")-$kind"
        mkdir -p "$run_dir"
        rm -f "$run_dir/failures.txt"
        startup_check "$bin" "$kind" "$run_dir"
    fi
    if [ "$kind" = term ] && [ "$display" != none ] && ! has_clipboard "$bin"; then
        log "SKIP $bin: no clipboard feature, display $display runs the same cases as display none"
        skipped_runs+=("$bin: no clipboard on $display")
        return
    fi
    if [ "$kind" = gui ] && [ "$display" = wayland ] && [ "$display_keyboard" != yes ]; then
        log "SKIP $bin: no virtual keyboard for the GUI clipboard on display $display, wtype not found"
        skipped_runs+=("$bin: no virtual keyboard on $display")
        return
    fi
    if [ "$kind" = gui ] && ! gui_starts "$bin"; then
        log "SKIP $bin: GUI cannot run on display $display"
        skipped_runs+=("$bin: no GUI on $display")
        return
    fi
    if [ "$kind" = gui ]; then
        local run_dir="$results/$display/startup/$(basename "$bin")-$kind"
        mkdir -p "$run_dir"
        rm -f "$run_dir/failures.txt"
        startup_check "$bin" "$kind" "$run_dir"
    fi
    # Only the clipboard cases reach a different state under another
    # display server, so a build runs every case on none and on the first
    # server it reaches, and the clipboard cases on the other servers
    local scope=all
    if [ "$display" != none ]; then
        if [ -n "${full_servers[$bin $kind]:-}" ]; then
            scope=clipboard
        else
            full_servers[$bin $kind]=$display
        fi
    fi
    for config in $configs; do
        run_process "$bin" "$kind" "$display" "$config" "$scope"
    done
}

mkdir -p "$results"
for display in $displays; do
    if ! start_display "$display"; then
        log "SKIP display $display: $skip_reason"
        skipped_runs+=("display $display: $skip_reason")
        continue
    fi
    select_clip_tool "$display"
    for bin in $vim_bins; do
        run_binary "$bin" term "$display"
    done
    if [ "$display" != none ]; then
        for bin in $gvim_bins; do
            run_binary "$bin" gui "$display"
        done
    fi
    stop_display
done

log "TOTAL: $total_pass passed, $total_fail failed, $total_skip skipped, $total_known known"
for run in "${skipped_runs[@]}"; do
    log "  skipped: $run"
done
for run in "${failed_runs[@]}"; do
    log "  failed: $run"
done
[ "$total_fail" -eq 0 ] && [ "${#failed_runs[@]}" -eq 0 ]
