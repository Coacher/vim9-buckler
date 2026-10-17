vim9script
# Behavior test of vim9-buckler, see test/run.sh. Runs every scenario in one
# Vim process and checks the plugin invariants after every step.
# Env: OUT (result file), GO ('guioptions' flags a/A/P, gVim only),
# ONLY and PASS_ONLY (optional regexps of scenario names, both must match).

import autoload 'buckler/history.vim' as bh
import autoload 'buckler/registers.vim'

const LINES = ['alpha beta gamma', 'delta epsilon', 'zeta eta theta', 'iota kappa', 'lambda mu']
const STEP_DELAY = 120
const SLOW_DELAY = 600
const WATCHDOG = 240

# Step syntax: 'KEYS|EXPECT'. KEYS are fed as typed, or one of the @actions.
# EXPECT: push (history gets the yanked text), none (history unchanged),
# paste (none + the newest history item got pasted), mpaste (none + "* got
# pasted), plus/star (push when "+/"* is a clipboard register or there is no
# clipboard support and Vim uses the unnamed register instead, none otherwise),
# ext (none, another application changes the clipboard), extplus/extstar/
# extboth (the external text gets to history if the primary clipboard register
# changed), numbered (the "N history item gets the yanked text if it exists,
# "0 pushes to an empty history, otherwise history unchanged and a warning),
# sync (history after @sync), any (no history check).
# paste1..paste9 (none + the given history item got pasted), pasteplus/
# pastestar (paste when "+/"* follows the history, none otherwise).
# known:EXPECT is a known issue, it is checked against EXPECT but its failures
# are reported as KNOWN and are not counted. Errors are always counted.
const SCENARIOS = [
  # Yanks
  ['yank yy', ['yy|push']],
  ['yank yw', ['yw|push']],
  ['yank yiw', ['wyiw|push']],
  ['yank y$', ['wy$|push']],
  ['yank Y', ['jY|push']],
  ['yank 3yy', ['3yy|push']],
  ['yank vey', ['wvey|push']],
  ['yank Vjy', ['Vjy|push']],
  ['yank blockwise', ["\<C-V>jly|push"]],
  ['yank twice same', ['yy|push', 'yy|none']],
  ['yank sequence', ['yy|push', 'jyy|push', 'jyy|push', 'jyw|push']],
  ['yank "a', ['"ayy|none']],
  ['yank "+', ['j"+yy|plus']],
  ['yank "*', ['j"*yy|star']],
  ['yank "0', ['yy|push', 'j"0yy|numbered']],
  ['yank "0 empty history', ['@histclear|any', '"0yy|numbered']],
  ['yank "_', ['"_yy|none']],
  ['yank "A', ['"ayy|none', 'j"Ayy|none']],
  ['yank "1', ['yy|push', 'jyy|push', 'j"1yy|numbered', 'p|paste']],
  ['yank "1 same as "0', ['yy|push', 'jyy|push', '"1yy|numbered']],
  ['yank "5 missing from history', ['yy|push', 'j"5yy|numbered', 'jyy|push']],
  ['yank vY', ['wvY|push']],
  ['yank again older', ['yy|push', 'jyy|push', 'kyy|push']],
  ['yank :yank', [':2yank|push', ':4yank|push']],
  ['yank :yank a', [':yank a|none']],
  ['yank :yank +', [':yank +|plus']],
  ['yank :normal', [':normal! jyy|push']],
  ['yank ""yy', ['j""yy|push']],
  ['yank 2yw', ['2yw|push']],
  ['yank y2j', ['y2j|push']],
  ['yank yip', ['yip|push']],
  ['yank forced blockwise', ["y\<C-V>jl|push"]],
  ['yank vipy', ['vipy|push']],
  ['yank vapy', ['jvapy|push']],
  ['yank vo', ['wveohy|push']],
  ['yank gvy', ['wvey|push', 'gvy|push']],
  ['yank V"py', ['yy|push', 'jV"py|none', 'p|paste']],
  ['yank V"+y', ['jV"+y|plus']],
  ['yank same text other type', ['yiw|push', "\<C-V>ey|push"]],
  ['yank multibyte', [":call setline(2, 'привет мир ✓ 日本')|none", 'jyy|push', 'p|paste', 'wyiw|push', 'P|paste']],
  ['yank empty line', [":call setline(2, '')|none", 'jyy|push', 'p|any']],
  ['yank insert CTRL-O', ["A\<C-O>yy\<Esc>|push"]],
  ['yank macro', ['qayyjq|push', '@a|push', '@@|push']],
  ['yank macro q1', ['yy|push', 'jyy|push', 'q1lq|none', 'p|paste']],
  ['yank macro q"', ['yy|push', 'q"lq|none', 'p|paste']],
  ['yank setreg 0', ['yy|push', ":call setreg('0', 'manual')|none", 'p|paste']],
  ['yank setreg +', ['yy|push', ":call setreg('+', 'manual')|none", 'p|paste']],
  # History length
  ['history overflow', ['yiw|push'] + repeat(['wyiw|push'], 11)],
  ['history length 3', ['@histlen=3|none', 'yiw|push'] + repeat(['wyiw|push'], 4)],
  ['history overflow "9p', ['yiw|push'] + repeat(['wyiw|push'], 11) + ['"9p|paste9']],
  ['history "1p repeat', ['yy|push', 'jyy|push', 'jyy|push', 'jyy|push', 'G"1p|paste1', 'u|none', '.|paste2']],
  ['history length shrink', ['yiw|push'] + repeat(['wyiw|push'], 5) + ['@histlen=3|any', 'wyiw|push']],
  # Startup sync of numbered registers, e.g. from viminfo
  ['sync numbered registers', ['@sync|sync', 'p|paste']],
  ['sync numbered registers gaps', ['@sync=,g1,,g3|sync', 'p|paste']],
  ['sync numbered registers same', ['@sync=d1,d1,d1|sync', 'p|paste']],
  # Deletes and changes
  ['delete dd', ['dd|push']],
  ['delete dw', ['dw|push']],
  ['delete x', ['x|push']],
  ['delete X', ['wX|push']],
  ['delete D', ['wD|push']],
  ['delete 2dd', ['2dd|push']],
  ['delete vex', ['wvex|push']],
  ['delete Vd', ['Vd|push']],
  ['delete blockwise', ["\<C-V>jld|push"]],
  ['delete "_dd', ['"_dd|none']],
  ['delete "add', ['"add|none']],
  ['delete "1dd', ['yy|push', 'jyy|push', 'j"1dd|numbered']],
  ['delete vD', ['jvD|push']],
  ['delete :delete', [':3delete|push']],
  ['delete "+dd', ['j"+dd|plus']],
  ['delete "*x', ['"*x|star']],
  ['delete "Add', ['"add|none', '"Add|none']],
  ['delete V"_d', ['V"_d|none']],
  ['delete diw', ['wdiw|push']],
  ['delete daw', ['wdaw|push']],
  ['delete dap', ['dap|push']],
  ['delete dG', ['jjdG|push']],
  ['delete dk', ['jdk|push']],
  ['delete dvj', ['wdvj|push']],
  ['delete d/pattern', ["d/eta\<CR>|push"]],
  ['delete 5x', ['5x|push']],
  ['delete blockwise X', ["\<C-V>jlX|push"]],
  ['delete :g', [':g/e/d|any', 'p|paste']],
  ['delete empty line', [":call setline(2, '')|none", 'jdd|push', 'p|any']],
  ['delete x on empty line', [":call setline(2, '')|none", 'jx|none']],
  ['delete insert CTRL-O', ["A\<C-O>dd\<Esc>|push"]],
  ['delete insert CTRL-W CTRL-U', ["A\<C-W>\<C-U>\<Esc>|none"]],
  ['repeat dw count', ['dw|push', '3.|push']],
  ['repeat Vjd', ['Vjd|push', '.|push']],
  ['change vec', ["wvecNEW\<Esc>|push"]],
  ['change ciw', ["wciwNEW\<Esc>|push"]],
  ['change vC', ["jvCNEW\<Esc>|push"]],
  ['change vS', ["jvSNEW\<Esc>|push"]],
  ['change blockwise c', ["\<C-V>jlcNEW\<Esc>|push"]],
  ['change R', ["RXYZ\<Esc>|none"]],
  ['change :s', [':s/a/b/g|none']],
  ['change operators without registers', ['g~~|none', 'gUU|none', 'guu|none', '>>|none', '<<|none', '~|none', 'rX|none', 'g??|none', "\<C-A>|none", 'gJ|none']],
  ['change visual operators without registers', ['vl~|none', 'Vu|none', 'VU|none', 'V>|none', 'VJ|none', 'vlrZ|none', "\<C-V>jIX\<Esc>|none"]],
  ['change cw', ["cwNEW\<Esc>|push"]],
  ['change cc', ["ccNEW\<Esc>|push"]],
  ['change s', ["sN\<Esc>|push"]],
  ['change C', ["wCNEW\<Esc>|push"]],
  ['join J', ['J|none']],
  # Pastes
  ['paste p', ['yy|push', 'jp|paste']],
  ['paste P', ['yy|push', 'jP|paste']],
  ['paste gp', ['yy|push', 'jgp|paste']],
  ['paste gP', ['yy|push', 'jgP|paste']],
  ['paste ]p', ['yy|push', 'j]p|paste']],
  ['paste 3p', ['yw|push', 'j3p|paste']],
  ['paste charwise p', ['yiw|push', 'jp|paste']],
  ['paste after delete', ['yy|push', 'jdd|push', 'p|paste']],
  ['paste "a', ['"ayy|none', 'j"ap|none']],
  ['paste "0', ['yy|push', 'j"0p|paste']],
  ['paste :put', ['yy|push', ':put|paste']],
  ['paste insert CTRL-R', ['yy|push', "jA\<C-R>\"\<Esc>|paste"]],
  ['paste insert CTRL-R CTRL-O', ['yy|push', "jA\<C-R>\<C-O>\"\<Esc>|paste"]],
  ['paste insert CTRL-O p', ['yy|push', "jA\<C-O>p\<Esc>|paste"]],
  ['paste cmdline CTRL-R', ['yiw|push', "0:\<C-R>\"\<Esc>|none"]],
  ['paste [P', ['yy|push', 'j[P|paste']],
  ['paste zp', ["\<C-V>ly|push", 'jzp|paste']],
  ['paste "+p', ['yy|push', 'j"+p|pasteplus']],
  ['paste "*p', ['yy|push', 'j"*p|pastestar']],
  ['paste ""p', ['yy|push', 'j""p|paste']],
  ['paste :put a', ['"ayy|none', ':put a|none']],
  ['paste multibyte', [":call setline(1, 'ёлка ✓ 日本')|none", 'yiw|push', 'jp|paste', 'jviwp|paste', 'p|paste']],
  ['visual p', ['yiw|push', 'jviwp|paste', 'jviwp|paste', 'p|paste']],
  ['visual Vp', ['yy|push', 'jVp|paste', 'jVp|paste', 'p|paste']],
  ['visual P', ['yy|push', 'jVP|paste', 'p|paste']],
  ['visual blockwise p', ['yl|push', "j\<C-V>jlp|paste", 'p|paste']],
  ['visual "ap', ['"ayy|none', 'jV"ap|none', 'p|any']],
  ['visual p after delete', ['yy|push', 'jdd|push', 'jVp|paste']],
  ['visual "0p', ['yy|push', 'jV"0p|paste', 'p|paste']],
  ['visual "1p', ['yy|push', 'jyy|push', 'jV"1p|paste1', 'p|paste']],
  ['visual "+p', ['yy|push', 'jV"+p|pasteplus', 'p|any']],
  ['visual "*p', ['yy|push', 'jV"*p|pastestar', 'p|any']],
  ['visual ""p', ['yy|push', 'jV""p|paste', 'p|paste']],
  ['visual 2p', ['yiw|push', 'jviw2p|paste', 'p|paste']],
  ['visual blockwise P', ['yl|push', "j\<C-V>jlP|paste", 'p|paste']],
  ['visual vp linewise text', ['yy|push', 'jwvep|paste', 'p|paste']],
  ['visual Vp charwise text', ['yiw|push', 'jVp|paste', 'P|paste']],
  ['visual p last line', ['yy|push', 'GVp|paste', 'p|paste']],
  ['visual p mapping', [':xnoremap <buffer> ,r p|none', 'yy|push', 'jV,r|paste', 'p|paste']],
  ['visual p :normal', ['yy|push', ':normal! jVp|paste', 'p|paste']],
  ['visual p feedkeys', ['yy|push', '@feedkeys=jVp|paste', 'p|paste']],
  ['visual p insert CTRL-O', ['yiw|push', "jA\<C-O>vbp\<Esc>|paste", 'p|paste']],
  # Visual selections that end without an operator
  ['select v Esc', ['yy|push', "jve\<Esc>|none", 'p|paste']],
  ['select V Esc', ['yy|push', "jV\<Esc>|none", 'p|paste']],
  ['select V moves away', ['yy|push', 'jVj|none', "\<Esc>|none", 'p|paste']],
  ['select gh Esc', ['yy|push', "jgh\<Right>\<Right>\<Esc>|none", 'p|paste']],
  ['select gv Esc', ['yy|push', "jve\<Esc>|none", "gv\<Esc>|none", 'p|paste']],
  # Select mode typing and <BS> delete the selection
  ['select gh type', ['yy|push', "jgh\<Right>\<Right>X\<Esc>|any", 'p|any']],
  ['select gh BS', ['yy|push', "jgh\<Right>\<Right>\<BS>\<Esc>|any", 'p|any']],
  ['select gH type', ['yy|push', "jgHX\<Esc>|any", 'p|any']],
  ['select v CTRL-G type', ['yy|push', "jve\<C-G>X\<Esc>|any", 'p|any']],
  ['select gh CTRL-O y', ['yy|push', "jgh\<Right>\<Right>\<C-O>y|push", 'P|paste']],
  ['select keymodel startsel', [':set keymodel=startsel selectmode=key|none', 'yy|push', "j\<S-Right>\<S-Right>X\<Esc>|any", 'p|any']],
  # Mouse
  ['mouse drag Esc', [':set mouse=a|none', 'yy|push', '@drag|none', "\<Esc>|none", 'p|paste']],
  ['mouse drag y', [':set mouse=a|none', '@drag|none', 'y|push']],
  ['mouse drag p', [':set mouse=a|none', 'yy|push', '@drag|none', 'p|paste']],
  ['mouse double click Esc', [':set mouse=a|none', 'yy|push', '@dclick|none', "\<Esc>|none", 'p|paste']],
  ['mouse middle click', [':set mouse=a|none', 'yy|push', '@middle|mpaste']],
  ['mouse triple click y', [':set mouse=a|none', 'yy|push', '@tclick|none', 'y|push']],
  ['mouse right click extend y', [':set mouse=a|none', '@drag|none', '@rightext|none', 'y|push']],
  ['mouse drag selectmode=mouse type', [':set mouse=a selectmode=mouse|none', 'yy|push', '@drag|none', "X\<Esc>|any", 'p|any']],
  # gVim modeless selection goes to the clipboard and is not recorded
  ['mouse modeless', [':set mouse=|none', 'yy|push', '@modeless|none', 'p|paste']],
  # Undo and redo
  ['undo delete', ['yy|push', 'jdd|push', 'u|none', 'p|paste']],
  ['redo delete', ['jdd|push', 'u|none', "\<C-R>|none", 'p|paste']],
  ['undo paste', ['yy|push', 'jp|paste', 'u|none', 'p|paste']],
  ['undo visual paste', ['yy|push', 'jVp|paste', 'u|none', "\<C-R>|none", 'u|none', 'p|paste']],
  ['undo line U', ['yy|push', 'jx|push', 'x|push', 'U|none', 'p|paste']],
  ['undo yank', ['yy|push', 'u|none', 'p|paste']],
  ['undo g- g+', ['yy|push', 'jdd|push', 'g-|none', 'g+|none', 'p|paste']],
  # Repeat
  ['repeat dd', ['dd|push', '.|push', '.|push']],
  ['repeat x', ['x|push', '.|push']],
  ['repeat cw', ["cwNEW\<Esc>|push", 'w.|push']],
  ['repeat p', ['yy|push', 'jp|paste', '.|paste']],
  ['repeat insert', ["A!\<Esc>|none", 'j.|none']],
  # Vim repeats a Visual paste as a delete, the deleted text is recorded
  ['repeat visual p', ['yy|push', 'jVp|paste', 'j.|none']],
  # Other applications
  ['external copy', ['yy|push', '@lost|none', '@copy|ext', '@gained|extplus', 'p|paste']],
  ['external select', ['yy|push', '@lost|none', '@select|ext', '@gained|extstar', 'p|paste']],
  ['external both', ['yy|push', '@lost|none', '@select|ext', '@copy|ext', '@gained|extboth', 'p|paste']],
  ['external no change', ['yy|push', '@lost|none', '@gained|none']],
  ['external then visual p', ['yy|push', '@lost|none', '@copy|ext', '@gained|extplus', 'jVp|paste']],
  ['external gained twice', ['yy|push', '@lost|none', '@copy|ext', '@gained|extplus', '@gained|none', 'p|paste']],
  ['external same text', ['yy|push', '@lost|none', "@copy=alpha beta gamma\n|ext", '@gained|none', 'p|paste']],
  ['external older history text', ['yy|push', 'jyy|push', '@lost|none', "@copy=alpha beta gamma\n|ext", '@gained|extplus', 'p|paste']],
  ['external multiline', ['yy|push', '@lost|none', "@copy=line one\nline two\n|ext", '@gained|extplus', 'p|paste']],
  ['external multibyte', ['yy|push', '@lost|none', '@copy=ёлка ✓ 日本|ext', '@gained|extplus', 'p|paste']],
  ['external clear', ['yy|push', '@lost|none', '@clear|ext', '@gained|none', 'p|paste']],
  ['external lost twice', ['yy|push', '@lost|none', '@copy|ext', '@lost|none', '@gained|extplus', 'p|paste']],
  ['external copy then delete', ['yy|push', '@lost|none', '@copy|ext', '@gained|extplus', 'jdd|push', 'p|paste']],
  ['external select then visual p', ['yy|push', '@lost|none', '@select|ext', '@gained|extstar', 'jVp|paste']],
  ['external then yank', ['yy|push', '@lost|none', '@copy|ext', '@gained|extplus', 'jyy|push', 'p|paste']],
  # 'clipboard' changed at runtime
  ['option clipboard=unnamed', ['yy|push', '@clipboard=unnamed|none', 'jp|paste', 'jyy|push']],
  ['option clipboard=unnamedplus', ['yy|push', '@clipboard=unnamedplus|none', 'jp|paste', 'jyy|push']],
  ['option clipboard=', ['yy|push', '@clipboard=|none', 'jp|paste', 'jyy|push']],
  ['option clipboard=unnamed,unnamedplus', ['yy|push', '@clipboard=unnamed,unnamedplus|none', 'jp|paste', 'jyy|push']],
  ['option clipboard=unnamedplus,autoselectplus', ['yy|push', '@clipboard=unnamedplus,autoselectplus|none', 'jVp|paste', 'p|paste']],
]
const SYNC = ['s0', 's1', 's1', 's3']
const CLIPBOARD = &clipboard
const HISTLEN = g:vim9buckler_history_length

var queue: list<list<any>>
var scenario = ''
var step = ''
var expect = ''
var before: dict<any>
var external = ''
# Texts set by @copy/@select by register, registers set by the last @sync
var external_text: dict<string>
var sync_regs = SYNC
# Registers changed by other applications on purpose, not checked any more
var foreign: list<string>
var typs: list<dict<any>>
var failures = 0
var known_failures = 0
var known = false

autocmd TextYankPost * typs->add(deepcopy(v:event))

def Log(line: string)
  writefile([line], $OUT, 'a')
enddef

def ClipboardRegisters(): list<string>
  if !has('clipboard')
    return []
  endif
  var names = split(&clipboard, ',')
  return (index(names, 'unnamedplus') >= 0 ? ['+'] : []) + (index(names, 'unnamed') >= 0 ? ['*'] : [])
enddef

def Reg(name: string): string
  return getregtype(name) .. ':' .. getreg(name)
enddef

def Text(): string
  return join(getline(1, '$'), "\n")
enddef

def Value(item: dict<string>): string
  return trim(item.value ?? '', "\n", 2)
enddef

def State(): string
  return printf('buf=%s hist=%s 0=%s "=%s *=%s +=%s', string(getline(1, '$')),
    string(bh.history->mapnew((_, i) => i.value)), string(getreg('0')), string(getreg('"')),
    string(getreg('*')), string(getreg('+')))
enddef

def Fail(reason: string)
  if known
    known_failures += 1
  else
    failures += 1
  endif
  Log(printf('%s | %s | %s | %s | %s', known ? 'KNOWN' : 'FAIL', scenario, strtrans(step), reason, State()))
enddef

def Check()
  var hist = bh.history
  if !empty(v:errmsg)
    Fail('error: ' .. v:errmsg)
  endif
  known = expect =~ '^known'
  if known
    expect = matchstr(expect, ':\zs.*') ?? 'any'
  endif
  # History changes
  var primary = get(ClipboardRegisters(), 0, '')
  var kind = expect
  # Without a working clipboard "* and "+ are the unnamed register
  var working = has('clipboard_working')
  # History index of the text that must get pasted, -1 for none
  var paste_idx = -1
  if kind == 'plus' || kind == 'star'
    kind = !working || index(ClipboardRegisters(), kind == 'plus' ? '+' : '*') >= 0 ? 'push' : 'none'
  elseif kind == 'pasteplus' || kind == 'pastestar'
    paste_idx = !working || index(ClipboardRegisters(), kind == 'pasteplus' ? '+' : '*') >= 0 ? 0 : -1
  elseif kind =~ '^paste\d\=$'
    paste_idx = str2nr(kind[5 :])
    if paste_idx > 0 && paste_idx >= len(before.hist)
      # Shorter 'g:vim9buckler_history_length', nothing to paste
      paste_idx = -1
    endif
  elseif kind == 'ext'
    kind = 'none'
  elseif kind =~ '^ext'
    var reg = {extplus: '+', extstar: '*', extboth: primary}[kind]
    kind = working && g:vim9buckler_sync_clipboard && primary != '' && reg == primary ? 'external' : 'none'
  endif
  # Yank to a numbered register: "N text may stay out of the history
  var idx = str2nr(matchstr(step, '"\zs\d'))
  if kind == 'numbered'
    kind = idx < len(before.hist) ? 'set' : idx == 0 ? 'push' : 'warn'
  endif
  # Registers follow the history. With 'guioptions' flags 'a' or 'P' or
  # 'clipboard' autoselect a Visual selection is in the clipboard until Visual
  # mode ends.
  var autoselect = false
  if mode() =~# "^[vVsS\x16\x13]"
    if &clipboard =~# 'autoselect'
      autoselect = true
    elseif has('gui_running')
      autoselect = &guioptions =~# '[aP]'
    endif
  endif
  if external == '' && !autoselect
    for r in ClipboardRegisters()
      if index(foreign, r) < 0 && Reg(r) != Reg('0')
        Fail($'"{r} differs from "0')
      endif
    endfor
  endif
  if getreg('"') != getreg('0')
    Fail('"" differs from "0')
  endif
  for i in range(10)
    var want = i < len(hist) ? (hist[i].value ?? '') : ''
    if kind == 'warn' && i == idx
      # Kept until the next yank, see 'yank "5 missing from history'
    elseif getreg(string(i)) != want
      Fail($'"{i} differs from history[{i}]')
    elseif i < len(hist) && getregtype(string(i)) != hist[i].type
      Fail($'"{i} type differs from history[{i}]')
    endif
  endfor
  for i in range(1, max([len(hist) - 1, 0]))
    if hist[i] == hist[i - 1]
      Fail($'adjacent duplicates at history[{i}]')
    endif
  endfor
  if hist != before.hist && len(hist) > g:vim9buckler_history_length
    Fail($'history is longer than {g:vim9buckler_history_length}')
  endif
  if kind == 'push'
    if empty(typs)
      Fail('no TextYankPost')
    else
      var text = join(typs[-1].regcontents, "\n")
      if empty(hist) || Value(hist[0]) != text
        Fail('history[0] is not the yanked text ' .. string(text))
      elseif len(before.hist) > 0 && Value(before.hist[0]) != text && (len(hist) < 2 || hist[1] != before.hist[0])
        Fail('previous history[0] is not history[1]')
      endif
    endif
  elseif kind == 'external'
    if empty(hist) || Value(hist[0]) != trim(get(external_text, primary, ''), "\n", 2)
      Fail('external text is not history[0]')
    endif
  elseif kind == 'set'
    var want = before.hist->mapnew((_, i) => Value(i))
    if !empty(typs)
      want[idx] = join(typs[-1].regcontents, "\n")
    endif
    if hist->mapnew((_, i) => Value(i)) != want
      Fail($'history[{idx}] is not the only change, want {string(want)}')
    endif
  elseif kind == 'warn'
    if hist != before.hist
      Fail('history changed')
    endif
    if execute('messages') !~ $'"{idx} may be cleared after next yank\n*$'
      Fail($'no "{idx} warning')
    endif
  elseif kind == 'sync'
    # Numbered registers from "9 to "0 then the clipboard register get pushed
    var numbered = sync_regs[: min([g:vim9buckler_history_length, 10]) - 1]->filter((_, v) => v != '')
    # Without a working clipboard "+ and "* are "", it points to "0
    var pushed = (working && primary != '' ? [trim(before.primary, "\n", 2)] : []) + numbered + before.hist->mapnew((_, i) => Value(i))
    var want = pushed->copy()->filter((i, v) => i == 0 || v != pushed[i - 1])[: g:vim9buckler_history_length - 1]
    if hist->mapnew((_, i) => Value(i)) != want
      Fail($'history is not {string(want)}')
    endif
  elseif kind != 'any' && hist != before.hist
    Fail('history changed')
  endif
  # Text yanked to an explicitly given register must not get lost
  var explicit = matchstr(step, '"\zs.')
  if explicit != '' && explicit != '_' && !empty(typs) && typs[-1].operator != 'd'
    var text = join(typs[-1].regcontents, "\n")
    if trim(getreg(explicit), "\n", 2) != text && (empty(hist) || Value(hist[0]) != text)
      Fail($'text yanked to "{explicit} is lost')
    endif
  endif
  # Pasted text
  if !g:vim9buckler_sync_clipboard && !empty(foreign)
    # Without clipboard sync Vim pastes what the other application set
  elseif paste_idx >= 0 || expect == 'mpaste'
    # Without clipboard support the middle click pastes the unnamed register
    var want = paste_idx >= 0 ? Value(get(before.hist, paste_idx, {value: ''}))
      : !working ? Value(get(before.hist, 0, {value: ''})) : trim(before.star, "\n", 2)
    if empty(want) || count(Text(), want) <= count(before.text, want)
      Fail('did not paste ' .. string(want))
    endif
  endif
  known = false
enddef

def Mouse(keys: list<list<any>>)
  if empty(keys)
    return
  endif
  var [key, row, col] = keys[0]
  test_setmouse(row, col)
  feedkeys(key, 't')
  timer_start(50, (_) => Mouse(keys[1 : ]))
enddef

def Do(action: string)
  if action =~ '^:'
    execute action
  elseif action == '@drag'
    Mouse([["\<LeftMouse>", 3, 1], ["\<LeftDrag>", 3, 4], ["\<LeftDrag>", 3, 8], ["\<LeftRelease>", 3, 8]])
  elseif action == '@dclick'
    Mouse([["\<LeftMouse>", 3, 2], ["\<LeftRelease>", 3, 2], ["\<2-LeftMouse>", 3, 2], ["\<LeftRelease>", 3, 2]])
  elseif action == '@tclick'
    Mouse([["\<LeftMouse>", 3, 2], ["\<LeftRelease>", 3, 2], ["\<2-LeftMouse>", 3, 2], ["\<LeftRelease>", 3, 2],
      ["\<3-LeftMouse>", 3, 2], ["\<LeftRelease>", 3, 2]])
  elseif action == '@rightext'
    Mouse([["\<RightMouse>", 4, 3], ["\<RightRelease>", 4, 3]])
  elseif action == '@middle'
    Mouse([["\<MiddleMouse>", 4, 1], ["\<MiddleRelease>", 4, 1]])
  elseif action == '@modeless'
    if has('gui_running')
      for [button, col] in [[0, 1], [0x43, 4], [0x43, 8], [3, 8]]
        test_gui_event('mouse', {button: button, row: 3, col: col, multiclick: 0, modifiers: 0})
      endfor
    endif
  elseif action =~ '^@clipboard='
    if has('clipboard')
      execute 'set clipboard=' .. matchstr(action, '=\zs.*')
    endif
  elseif action =~ '^@histlen='
    g:vim9buckler_history_length = str2nr(matchstr(action, '=\zs.*'))
  elseif action == '@histclear'
    # Clipboard support and a 'clipboard' register keep the history non-empty
    bh.history->filter((_, _) => false)
    registers.SetNumberedFromHistory()
    registers.SetClipboardFromZero()
  elseif action =~ '^@sync'
    sync_regs = action =~ '=' ? split(matchstr(action, '=\zs.*'), ',', 1) : SYNC
    for i in range(len(sync_regs))
      setreg(string(i), sync_regs[i])
    endfor
    registers.SyncHistoryWithRegisters()
  elseif action == '@lost' || action == '@gained'
    execute 'doautocmd' (action == '@lost' ? 'FocusLost' : 'FocusGained')
    if action == '@gained'
      external = ''
    endif
  elseif action =~ '^@\(copy\|select\)\(=\|$\)'
    # Another application owns the selection, @copy=TEXT sets the given text
    var name = matchstr(action, '^@\zs\a\+')
    external = action
    foreign->add(name == 'select' ? '*' : '+')
    var text = action =~ '=' ? matchstr(action, '=\zs\_.*') : $'external-{name}-{rand() % 1000}'
    external_text[name == 'select' ? '*' : '+'] = text
    system($'xsel -i {name == 'select' ? '-p' : '-b'} >/dev/null 2>&1', text)
  elseif action == '@clear'
    # The selection owner exits
    external = action
    foreign += ['+', '*']
    system('xsel -c -b; xsel -c -p')
  elseif action =~ '^@feedkeys='
    # Keys from a plugin, not typed
    feedkeys(matchstr(action, '=\zs.*'), 'n')
  else
    feedkeys(action, 't')
  endif
enddef

def Reset()
  enew!
  setlocal bufhidden=wipe undolevels=-1
  setline(1, LINES)
  setlocal undolevels=1000
  cursor(1, 1)
  set mouse=
  if has('clipboard') && &clipboard != CLIPBOARD
    execute 'set clipboard=' .. CLIPBOARD
  endif
  set selectmode& keymodel&
  g:vim9buckler_history_length = HISTLEN
  sync_regs = SYNC
  external_text = {}
  for r in ['a', '-'] + range(10)->mapnew((_, i) => string(i))
    setreg(r, '')
  endfor
  bh.history->filter((_, _) => false)
  if has('clipboard')
    setreg('*', 'init-star')
    setreg('+', 'init-plus')
  endif
  registers.SyncHistoryWithRegisters()
  external = ''
  foreign = []
enddef

def Next()
  try
    if !empty(step)
      Check()
    endif
    step = ''
    if empty(queue)
      if known_failures > 0
        Log($'KNOWN | known_failures={known_failures}')
      endif
      Log($'DONE | failures={failures}')
      qall!
    endif
    if queue[0][0] != scenario
      # New scenario: leave any pending mode, then reset the state
      scenario = queue[0][0]
      feedkeys("\<C-\>\<C-N>", 'n')
      timer_start(STEP_DELAY, (_) => {
        try
          Reset()
        catch
          Fail('reset exception: ' .. v:exception)
        endtry
        timer_start(STEP_DELAY, (_) => Next())
      })
      return
    endif
    [step, expect] = (remove(queue, 0)[1] .. '|any')->split('|', 1)[0 : 1]
    before = {hist: deepcopy(bh.history), text: Text(), star: getreg('*'),
      primary: bh.Get().value ?? ''}
    typs = []
    known = false
    v:errmsg = ''
    Do(step)
    timer_start(step =~ '^@\(copy\|select\|clear\|gained\|drag\|dclick\|tclick\|rightext\|middle\)' ? SLOW_DELAY : STEP_DELAY, (_) => Next())
  catch
    Fail('exception: ' .. v:exception .. ' at ' .. v:throwpoint)
    step = ''
    timer_start(STEP_DELAY, (_) => Next())
  endtry
enddef

set nomore shortmess+=F
if has('gui_running')
  &guioptions = 'egimrLtT' .. $GO
endif
# Vim without clipboard support rejects "+ and "* in Ex commands and functions
const CLIPBOARD_ONLY = ['yank :yank +', 'yank setreg +']
for [name, steps] in SCENARIOS
  if (empty($ONLY) || name =~ $ONLY) && (empty($PASS_ONLY) || name =~ $PASS_ONLY)
      && (has('clipboard') || index(CLIPBOARD_ONLY, name) < 0)
    for s in steps
      queue->add([name, s])
    endfor
  endif
endfor
# Never stay open, whatever happens to the step queue
timer_start(WATCHDOG * 1000, (_) => {
  Log($'WATCHDOG | quit after {WATCHDOG}s at {scenario} | {strtrans(step)}')
  qall!
})
timer_start(500, (_) => Next())
