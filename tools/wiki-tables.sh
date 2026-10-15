#!/bin/bash
# Print the tables from https://github.com/Coacher/vim9-buckler/wiki measured
# on this machine.  Needs Wayland and wl-clipboard.  Overwrites the clipboard.

vim_bin=${VIM_BIN:-vim}
gvim_bin=${GVIM_BIN:-gvim}

copy() { wl-copy "$@" </dev/null >/dev/null 2>&1; }
ask() { read -rp "$1, then press Enter... " </dev/tty; }

# Print which of the selection (*) and the clipboard (+) the command changes.
changed() {
	copy --primary "old $RANDOM"
	copy "old $RANDOM"
	sleep 0.5
	local sel clip result=
	sel=$(wl-paste --primary 2>&1)
	clip=$(wl-paste 2>&1)
	"$@"
	sleep 0.5
	[[ $(wl-paste --primary 2>&1) != "$sel" ]] && result='*'
	[[ $(wl-paste 2>&1) != "$clip" ]] && result=${result:+$result, }+
	echo "$result"
}

export SEL DESEL DECOPY
SEL=$(changed ask 'Select some text with the mouse in this terminal')
DESEL=$(changed ask 'Select some text in another application')
DECOPY=$(changed ask 'Copy some text in another application')

script=$(mktemp)
trap 'rm -f "$script" "$script.out"' EXIT
cat >"$script" <<'EOF'
" Return lines of a Markdown table with the given column widths.
function Table(widths, rows)
  let lines = []
  for row in a:rows
    call add(lines, '| ' . join(map(row, 'v:val . repeat(" ", a:widths[v:key] - strchars(v:val))'), ' | ') . ' |')
  endfor
  return insert(lines, '|' . join(map(copy(a:widths), 'repeat("-", v:val + 2)'), '|') . '|', 1) + ['']
endfunction

let g:events = []
autocmd TextYankPost * call add(g:events, [v:operator, v:register, v:event.operator, v:event.regname])

" Return registers changed by typing keys, or by the user selecting with the
" mouse if empty.
function Changed(keys)
  %delete _
  call setline(1, ['alpha beta gamma', 'delta'])
  for r in ['0', '1', '*', '+', 'z']
    call setreg(r, 'old')
  endfor
  sleep 200m
  let before = map(['0', '1', '"', '*', '+'], 'getreg(v:val)')
  let g:events = []
  if empty(a:keys)
    redraw!
    call input('guioptions=' . &guioptions . ': select some text with the mouse, then press Enter')
  else
    " Moving first makes v:register follow 'clipboard'.
    call feedkeys('gg0' . a:keys, 'xt')
  endif
  sleep 300m
  let after = map(['0', '1', '"', '*', '+'], 'getreg(v:val)')
  return join(filter(['0', '1', 'unnamed', '*', '+'], 'before[v:key] != after[v:key]'), ', ')
endfunction

if has('gui_running')
  set clipboard= mouse=
  let rows = [['', 'Visual mode selection changes', 'Select mode selection changes', 'Modeless selection changes']]
  let visual_events = {}
  for go in ['a', 'A', 'P', 'aA', 'aP', 'AP', 'aAP', '']
    let &guioptions = go
    let visual = Changed("ve\<Esc>")
    let visual_events[go] = g:events
    call add(rows, ['set guioptions=' . go, visual, Changed("gh\<Right>\<Right>\<Right>\<Esc>"), Changed('')])
  endfor
  let rows2 = [['', 'v:event.operator', 'v:event.regname']]
  for go in ['a', 'aA', 'P', 'AP', 'aP', 'aAP']
    call add(rows2, ['guioptions=' . go, join(uniq(map(copy(visual_events[go]), 'v:val[2]')), ' AND '), join(map(copy(visual_events[go]), 'v:val[3]'), ' AND ')])
  endfor
  let lines = Table([14, 16, 15], rows2) + Table([18, 29, 29, 26], rows)
else
  let rows = [['', 'Yank changes', 'Delete changes', 'Visual paste† changes', 'Select* changes', 'DE select* changes', 'DE copy changes']]
  for cb in ['autoselect', 'autoselectplus', 'unnamed', 'unnamedplus', 'unnamedplus,unnamed', '']
    let &clipboard = cb
    call add(rows, ['set clipboard=' . cb, Changed('yy'), Changed('dd'), Changed('Vp'), $SEL, $DESEL, $DECOPY])
  endfor
  let lines = Table([33, 16, 14, 21, 15, 18, 15], rows)
  let rows = [['', 'v:operator', 'v:register', 'v:event.operator', 'v:event.regname']]
  for [name, keys] in [['Yank*', 'yy'], ['Delete*', 'dd'], ['Visual paste†*', 'Vp']]
    " Values for clipboard=, clipboard=unnamed and clipboard=unnamedplus.
    let values = []
    for cb in ['', 'unnamed', 'unnamedplus']
      let &clipboard = cb
      call Changed(keys)
      call add(values, map(g:events[-1], 'empty(v:val) ? "(empty)" : v:val'))
    endfor
    let row = [name]
    for i in range(4)
      let column = map(copy(values), 'v:val[i]')
      call add(row, len(uniq(copy(column))) == 1 ? column[0] : join(column, '/'))
    endfor
    call add(rows, row)
  endfor
  let lines += Table([14, 10, 10, 16, 15], rows)
endif
call writefile(lines, $OUT, 'a')
qall!
EOF

echo 'Follow the prompts in the gVim window when it appears.'
for v in "$vim_bin" "$gvim_bin"; do
	OUT=$script.out "$v" -f -Nu NONE -i NONE -n --not-a-term -S "$script" </dev/null >/dev/null 2>&1
done
cat "$script.out"
