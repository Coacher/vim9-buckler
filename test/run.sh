#!/bin/bash
# Run test/harness.vim for every 'clipboard' value with the X11 clipboard.
# Usage: test/run.sh vim|gvim [GUIOPTIONS-FLAGS]
#        test/run.sh startup (Vim starts without errors with the plugin)
# Env: VIM_BIN, GVIM_BIN (Vim and gVim commands), ONLY (scenario regexp).
# Needs an X11 display, xsel and python3. Tests overwrite the clipboard.
set -u
kind=$1 go=${2-}
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $kind == startup ]]; then
	# Install the plugin as a package, Vim exits with 1 on any error
	home=$(mktemp -d)
	trap 'rm -rf "$home"' EXIT
	mkdir -p "$home/.vim/pack/test/start"
	ln -s "$root" "$home/.vim/pack/test/start/vim9-buckler"
	: >"$home/.vimrc"
	HOME=$home timeout -k 5 30 "${VIM_BIN:-vim}" -es -i NONE -n -u "$home/.vimrc" -c 'qa!' </dev/null
	rc=$?
	echo "startup: exit code $rc"
	exit $rc
fi
out=$(mktemp)
trap 'rm -f "$out"' EXIT
# Use X11 even in a Wayland session, it does not need window focus
unset WAYLAND_DISPLAY
export GDK_BACKEND=x11 GO=$go OUT=$out
status=0
# Passes: 'clipboard' value;plugin settings (Ex command before loading);scenario
# name regexp. The first five passes run every scenario.
visual='^\(yank v\|yank V\|delete v\|delete V\|change v\|visual\|select\|mouse\|repeat visual\|option\)'
passes=('' 'unnamed' 'unnamedplus' 'unnamedplus,unnamed' 'unnamed,unnamedplus'
	"unnamed,autoselect;;$visual"
	"unnamedplus,autoselectplus;;$visual"
	'unnamedplus,exclude:.*;;^\(yank\|delete\|paste\|visual\|external\|sync\|option\)'
	'unnamedplus;let g:vim9buckler_sync_clipboard = 0;^\(external\|option\)'
	'unnamed;let g:vim9buckler_history_length = 3;^\(yank\|history\|sync\|delete "\)'
	'unnamedplus;let g:vim9buckler_history_length = 15;^\(history\|sync\)')
bin=${VIM_BIN:-vim}
[[ $kind == gvim ]] && bin=${GVIM_BIN:-gvim}
"$bin" --version | grep -qw '+clipboard' && has_clipboard=1 || has_clipboard=0
for pass in "${passes[@]}"; do
	IFS=';' read -r cb settings filter <<<"$pass"
	# Vim without clipboard support rejects these 'clipboard' values
	if [[ $has_clipboard == 0 && $cb =~ autoselect|exclude ]]; then
		echo "$kind clipboard=$cb guioptions+=$go: SKIPPED, $bin has no +clipboard"
		continue
	fi
	: >"$out"
	printf init-star | xsel -i -p >/dev/null 2>&1
	printf init-plus | xsel -i -b >/dev/null 2>&1
	# Vim connects to wayland-0 without WAYLAND_DISPLAY, force X11 in terminal Vim
	args=(-Nu NONE -i NONE -n --cmd "set rtp^=$root" --cmd "set clipboard=$cb"
		--cmd 'silent! set clipmethod=x11' --cmd "$settings"
		--cmd 'runtime plugin/buckler.vim' -S "$root/test/harness.vim")
	# The harness quits by itself after 240 s, kill Vim if it does not
	if [[ $kind == gvim ]]; then
		PASS_ONLY=$filter timeout -k 5 260 "${GVIM_BIN:-gvim}" -f "${args[@]}" </dev/null >/dev/null 2>&1
	else
		PASS_ONLY=$filter timeout -k 5 260 python3 -c 'import pty, sys; pty.spawn(sys.argv[1:])' \
			"${VIM_BIN:-vim}" "${args[@]}" </dev/null >/dev/null 2>&1
	fi
	rc=$?
	result=$(grep -a '^DONE' "$out" || echo "NOT DONE, exit code $rc")
	echo "$kind clipboard=$cb guioptions+=$go${settings:+ $settings}: $result"
	grep -a -v '^DONE' "$out"
	[[ $result == 'DONE | failures=0' ]] || status=1
done
exit $status
