vim9script
# Behavior test of vim9-buckler, see test/run.sh. Runs every scenario in one
# Vim process and checks the plugin invariants after every step.
# Env: OUT (result file), GO ('guioptions' flags a/A/P, gVim only),
# ONLY (optional regexp of scenario names).

import autoload 'buckler/history.vim' as bh
import autoload 'buckler/registers.vim'

const LINES = ['alpha beta gamma', 'delta epsilon', 'zeta eta theta', 'iota kappa', 'lambda mu']
const STEP_DELAY = 120
const SLOW_DELAY = 600
const WATCHDOG = 110

# Step syntax: 'KEYS|EXPECT'. KEYS are fed as typed, or one of the @actions.
# EXPECT: push (history gets the yanked text), none (history unchanged),
# paste (none + the newest history item got pasted), mpaste (none + "* got
# pasted), plus/star (push when "+/"* is a clipboard register or there is no
# clipboard support and Vim uses the unnamed register instead, none otherwise),
# ext (none, another application changes the clipboard), extplus/extstar/
# extboth (the external text gets to history if the primary clipboard register
# changed), any (no history check), known (known issue, only error checks).
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
  ['yank "0', ['yy|push', 'j"0yy|any']],
  ['yank "_', ['"_yy|none']],
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
  ['visual p', ['yiw|push', 'jviwp|paste', 'jviwp|paste', 'p|paste']],
  ['visual Vp', ['yy|push', 'jVp|paste', 'jVp|paste', 'p|paste']],
  ['visual P', ['yy|push', 'jVP|paste', 'p|paste']],
  ['visual blockwise p', ['yl|push', "j\<C-V>jlp|paste", 'p|paste']],
  ['visual "ap', ['"ayy|none', 'jV"ap|none', 'p|any']],
  ['visual p after delete', ['yy|push', 'jdd|push', 'jVp|paste']],
  # Visual selections that end without an operator
  ['select v Esc', ['yy|push', "jve\<Esc>|none", 'p|paste']],
  ['select V Esc', ['yy|push', "jV\<Esc>|none", 'p|paste']],
  ['select V moves away', ['yy|push', 'jVj|none', "\<Esc>|none", 'p|paste']],
  ['select gh Esc', ['yy|push', "jgh\<Right>\<Right>\<Esc>|none", 'p|paste']],
  ['select gv Esc', ['yy|push', "jve\<Esc>|none", "gv\<Esc>|none", 'p|paste']],
  # Mouse
  ['mouse drag Esc', [':set mouse=a|none', 'yy|push', '@drag|none', "\<Esc>|none", 'p|paste']],
  ['mouse drag y', [':set mouse=a|none', '@drag|none', 'y|push']],
  ['mouse drag p', [':set mouse=a|none', 'yy|push', '@drag|none', 'p|paste']],
  ['mouse double click Esc', [':set mouse=a|none', 'yy|push', '@dclick|none', "\<Esc>|none", 'p|paste']],
  ['mouse middle click', [':set mouse=a|none', 'yy|push', '@middle|mpaste']],
  # gVim modeless selection goes to the clipboard and is not recorded
  ['mouse modeless', [':set mouse=|none', 'yy|push', '@modeless|known', 'p|known']],
  # Undo and redo
  ['undo delete', ['yy|push', 'jdd|push', 'u|none', 'p|paste']],
  ['redo delete', ['jdd|push', 'u|none', "\<C-R>|none", 'p|paste']],
  ['undo paste', ['yy|push', 'jp|paste', 'u|none', 'p|paste']],
  ['undo visual paste', ['yy|push', 'jVp|paste', 'u|none', "\<C-R>|none", 'u|none', 'p|paste']],
  ['undo line U', ['yy|push', 'jx|push', 'x|push', 'U|none', 'p|paste']],
  ['undo yank', ['yy|push', 'u|none', 'p|paste']],
  # Repeat
  ['repeat dd', ['dd|push', '.|push', '.|push']],
  ['repeat x', ['x|push', '.|push']],
  ['repeat cw', ["cwNEW\<Esc>|push", 'w.|push']],
  ['repeat p', ['yy|push', 'jp|paste', '.|paste']],
  ['repeat insert', ["A!\<Esc>|none", 'j.|none']],
  # Vim repeats a Visual paste as a delete, the deleted text is recorded
  ['repeat visual p', ['yy|push', 'jVp|paste', 'j.|known']],
  # Other applications
  ['external copy', ['yy|push', '@lost|none', '@copy|ext', '@gained|extplus', 'p|paste']],
  ['external select', ['yy|push', '@lost|none', '@select|ext', '@gained|extstar', 'p|paste']],
  ['external both', ['yy|push', '@lost|none', '@select|ext', '@copy|ext', '@gained|extboth', 'p|paste']],
  ['external no change', ['yy|push', '@lost|none', '@gained|none']],
  ['external then visual p', ['yy|push', '@lost|none', '@copy|ext', '@gained|extplus', 'jVp|paste']],
]

var queue: list<list<any>>
var scenario = ''
var step = ''
var expect = ''
var before: dict<any>
var external = ''
# Registers changed by other applications on purpose, not checked any more
var foreign: list<string>
var typs: list<dict<any>>
var failures = 0

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
  failures += 1
  Log(printf('FAIL | %s | %s | %s | %s', scenario, strtrans(step), reason, State()))
enddef

def Check()
  var hist = bh.history
  if !empty(v:errmsg)
    Fail('error: ' .. v:errmsg)
  endif
  if expect == 'known'
    return
  endif
  # Registers follow the history. With 'guioptions' flags 'a' or 'P' a Visual
  # selection is in the clipboard until Visual mode ends.
  var autoselect = has('gui_running') && &guioptions =~# '[aP]' && mode() =~# "^[vVsS\x16\x13]"
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
    if getreg(string(i)) != want
      Fail($'"{i} differs from history[{i}]')
    endif
  endfor
  for i in range(1, max([len(hist) - 1, 0]))
    if hist[i] == hist[i - 1]
      Fail($'adjacent duplicates at history[{i}]')
    endif
  endfor
  # History changes
  var primary = get(ClipboardRegisters(), 0, '')
  var kind = expect
  if kind == 'plus' || kind == 'star'
    kind = !has('clipboard') || index(ClipboardRegisters(), kind == 'plus' ? '+' : '*') >= 0 ? 'push' : 'none'
  elseif kind == 'ext'
    kind = 'none'
  elseif kind =~ '^ext'
    var reg = {extplus: '+', extstar: '*', extboth: primary}[kind]
    kind = primary != '' && reg == primary ? 'external' : 'none'
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
    if empty(hist) || Value(hist[0]) !~ '^external-'
      Fail('external text is not history[0]')
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
  if expect == 'paste' || expect == 'mpaste'
    # Without clipboard support the middle click pastes the unnamed register
    var want = expect == 'paste' || !has('clipboard') ? Value(get(before.hist, 0, {value: ''})) : trim(before.star, "\n", 2)
    if empty(want) || count(Text(), want) <= count(before.text, want)
      Fail('did not paste ' .. string(want))
    endif
  endif
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
  elseif action == '@middle'
    Mouse([["\<MiddleMouse>", 4, 1], ["\<MiddleRelease>", 4, 1]])
  elseif action == '@modeless'
    if has('gui_running')
      for [button, col] in [[0, 1], [0x43, 4], [0x43, 8], [3, 8]]
        test_gui_event('mouse', {button: button, row: 3, col: col, multiclick: 0, modifiers: 0})
      endfor
    endif
  elseif action == '@lost' || action == '@gained'
    execute 'doautocmd' (action == '@lost' ? 'FocusLost' : 'FocusGained')
    if action == '@gained'
      external = ''
    endif
  elseif action == '@copy' || action == '@select'
    # Another application owns the selection
    external = action
    foreign->add(action == '@select' ? '*' : '+')
    system($'printf external-{action[1 : ]}-{rand() % 1000} | xsel -i {action == '@select' ? '-p' : '-b'} >/dev/null 2>&1')
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
    before = {hist: deepcopy(bh.history), text: Text(), star: getreg('*')}
    typs = []
    v:errmsg = ''
    Do(step)
    timer_start(step =~ '^@\(copy\|select\|gained\|drag\|dclick\|middle\)' ? SLOW_DELAY : STEP_DELAY, (_) => Next())
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
for [name, steps] in SCENARIOS
  if empty($ONLY) || name =~ $ONLY
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
