vim9script

# Runs every generated case in vanilla Vim driven by the history model and
# then in Vim with the plugin loaded, compares the two and writes the
# reports.
#
# run.sh configures the process through environment variables:
#   BUCKLER_CONFIG     plugin configuration name from matrices.vim
#   BUCKLER_DISPLAY    display variant name, recorded in the reports
#   BUCKLER_RESULTS    directory that receives the report files
#   BUCKLER_CASES      optional pattern that selects case ids
#   BUCKLER_MATRICES   optional pattern that selects matrix names
#   BUCKLER_CLIP_TOOL  tool that reaches the system clipboard: wl, xclip or empty
#   BUCKLER_SCOPE      clipboard selects the cases that can depend on the
#                      display server, anything else every case

import './fixtures.vim' as fx
import './matrices.vim' as mx
import './model.vim' as model

const test_dir = expand('<sfile>:p:h')
const repo_dir = fnamemodify(test_dir, ':h')
const results_dir = $BUCKLER_RESULTS
const config_name = $BUCKLER_CONFIG
const config = mx.configs[config_name]

# The plugin's history and clipboard register names, emptied before every
# case of the plugin run: the plugin reads them once when Vim starts
import autoload repo_dir .. '/autoload/buckler/history.vim' as plugin_history
import autoload repo_dir .. '/autoload/buckler/clipboard.vim' as plugin_clipboard

# Facts about this build that matrices use to decide what to generate
const ctx: dict<any> = {
    config: config,
    config_name: config_name,
    gui: has('gui_running') ? true : false,
    clipboard: has('clipboard') ? true : false,
    clipboard_working: has('clipboard_working') ? true : false,
    display: $BUCKLER_DISPLAY,
    tool: $BUCKLER_CLIP_TOOL,
    registers: fx.seeded_registers + (has('clipboard') ? ['*', '+'] : []),
}

var saved_options: dict<any> = {}
# Tool processes that own a system clipboard selection, by selection name
var owners: dict<job> = {}
var harness_errors: list<string> = []


def Baseline()
    set encoding=utf-8
    set belloff=all
    set nomore
    set noswapfile
    set hidden
    set shortmess+=I
    set noshowmode
    set noshowcmd
    set noruler
    set laststatus=0
    set lazyredraw
    set report=99999
    set nomodeline
    set clipboard=
    if has('gui_running')
        set guioptions-=a
        set guioptions-=A
    else
        set ttymouse=sgr
        # Terminal Vim switches bracketed paste and modifyOtherKeys around
        # every fed key sequence, which floods the log with their codes; the
        # keys come from feedkeys() and never pass the terminal
        set t_BE= t_BD= t_TI= t_TE=
    endif
enddef

def NewBuffer(fixture: dict<any>, cursor: list<number>)
    silent! bwipeout!
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile noundofile
    setlocal undolevels=-1
    setline(1, fixture.lines)
    setlocal undolevels<
    for [name, pos] in items(fixture.marks)
        setpos("'" .. name, [0, pos[0], pos[1], 0])
    endfor
    cursor(cursor[0], cursor[1])
    setlocal nomodified
    # The last Visual mode and area outlive the buffer they were used in
    visualmode(1)
    silent! delmarks < > [ ] . ^
enddef

def ApplySettings(settings: dict<any>)
    saved_options = {}
    for [name, value] in items(settings)
        saved_options[name] = eval('&' .. name)
        execute('&' .. name .. ' = ' .. string(value))
    endfor
enddef

def RestoreSettings()
    for [name, value] in items(saved_options)
        execute('&' .. name .. ' = ' .. string(value))
    endfor
    saved_options = {}
enddef

# Mappings a case defines, as a user would in a vimrc: {mode: {lhs: rhs}}
def ApplyMappings(mappings: dict<any>)
    for [mode, maps] in items(mappings)
        for [lhs, rhs] in items(maps)
            execute(mode .. 'noremap ' .. lhs .. ' ' .. rhs)
        endfor
    endfor
enddef

def ClearMappings(mappings: dict<any>)
    for [mode, maps] in items(mappings)
        for lhs in keys(maps)
            execute(mode .. 'unmap ' .. lhs)
        endfor
    endfor
enddef

def SeedRegisters(seed: dict<any>)
    for name in ctx.registers
        if name != '"'
            var value = fx.SeedValue(seed, name)
            if empty(value)
                setreg(name, null_string, null_string)
            else
                var regtype = index(seed.linewise, name) >= 0 ? 'V'
                    : index(seed.blockwise, name) >= 0 ? "\<C-V>" : 'v'
                setreg(name, [value], regtype)
            endif
        endif
    endfor
    setreg('"', {points_to: seed.points_to})
enddef


# System clipboard access through the tool run.sh selected for the display.
# Writers stay in the foreground so that stopping them empties the selection.

def RegisterOf(selection: string): string
    return selection == 'primary' ? '*' : '+'
enddef

def WriteCommand(selection: string): list<string>
    if ctx.tool == 'wl'
        return ['wl-copy', '--foreground'] + (selection == 'primary' ? ['--primary'] : [])
    endif
    return ['xclip', '-quiet', '-i', '-selection', selection]
enddef

def ReadCommand(selection: string): list<string>
    if ctx.tool == 'wl'
        return ['wl-paste', '--no-newline'] + (selection == 'primary' ? ['--primary'] : [])
    endif
    return ['xclip', '-o', '-selection', selection]
enddef

def TargetsCommand(selection: string): list<string>
    if ctx.tool == 'wl'
        return ['wl-paste', '--list-types'] + (selection == 'primary' ? ['--primary'] : [])
    endif
    return ['xclip', '-o', '-selection', selection, '-t', 'TARGETS']
enddef

# Sleeps in short steps until the condition holds, serving selection
# requests meanwhile, and reports whether it held before it gives up
def WaitFor(Cond: func(): bool): bool
    var start = reltime()
    while reltimefloat(reltime(start)) < 3.0
        if Cond()
            return true
        endif
        sleep 1m
    endwhile
    return Cond()
enddef

def StopOwner(selection: string)
    if has_key(owners, selection)
        job_stop(owners[selection])
        WaitFor(() => job_status(owners[selection]) != 'run')
        remove(owners, selection)
    endif
enddef

def StopOwners()
    for selection in keys(owners)
        StopOwner(selection)
    endfor
enddef

# Gives the selection to a tool process holding the text, or empties it
def WriteClipboard(text: string, target: string)
    for selection in target == 'both' ? ['clipboard', 'primary'] : [target]
        StopOwner(selection)
        if empty(text)
            continue
        endif
        # Terminal Vim under X11 misses a takeover that follows its own
        # register write at once, as if the ownership request were still
        # unsent; a pause in which Vim handles its connection first makes
        # every takeover visible, however short it is
        sleep 1m
        var job = job_start(WriteCommand(selection), {in_io: 'pipe', out_io: 'null', err_io: 'null'})
        ch_sendraw(job, text)
        ch_close_in(job)
        owners[selection] = job
        if !WaitFor(() => getreg(RegisterOf(selection)) == text)
            add(harness_errors, 'clipboard write to ' .. selection .. ' not seen by Vim')
        endif
    endfor
enddef

# Runs a reading tool while Vim keeps serving the selection, and reports
# its output, its error output and its exit status, which is negative when
# the tool does not exit in time
def RunReader(command: list<string>): dict<any>
    var out: list<string> = []
    var err: list<string> = []
    # The output of a tool may reach the callbacks after the tool exits;
    # Vim closes the channel only once it has passed on all of it
    var closed = false
    var job = job_start(command, {
        in_io: 'null', out_mode: 'raw', err_mode: 'raw',
        out_cb: (_, msg) => add(out, msg),
        err_cb: (_, msg) => add(err, msg),
        close_cb: (_) => {
            closed = true
        },
    })
    if !WaitFor(() => closed && job_status(job) != 'run')
        job_stop(job)
        return {exitval: -1, out: '', err: ''}
    endif
    return {exitval: job_info(job).exitval, out: join(out, ''), err: join(err, '')}
enddef

def ReadOnce(selection: string): dict<any>
    var result = RunReader(ReadCommand(selection))
    if result.exitval < 0
        add(harness_errors, 'clipboard read of ' .. selection .. ' timed out')
    endif
    return result
enddef

def Outcome(result: dict<any>): string
    return printf('exit %d, output %s, errors %s', result.exitval, string(trim(result.out)), string(trim(result.err)))
enddef

# Reads the selection with the tool while Vim keeps serving it.  A read
# that returns nothing although the register holds text is reported, so
# that a tool that cannot reach the selection never passes a case.  The
# report names how the read ended and which targets the selection offers
# then, as an owner that refuses the text still lists its targets and a
# selection without an owner lists none.
def ReadClipboard(selection: string): string
    # Vim's own ownership request may still be unsent, see WriteClipboard
    sleep 1m
    var result = ReadOnce(selection)
    # The tool exits with an error when nothing owns the selection
    var text = result.exitval == 0 ? result.out : ''
    if empty(text) && !empty(getreg(RegisterOf(selection)))
        add(harness_errors, printf('clipboard read of %s returned nothing while the register holds text: read %s; targets %s',
            selection, Outcome(result), Outcome(RunReader(TargetsCommand(selection)))))
    endif
    return text
enddef


def Snapshot(readback: bool): dict<any>
    var marks: dict<any> = {}
    for name in ['[', ']', '<', '>', '.', '^', 'a', 'b']
        marks[name] = getpos("'" .. name)[1 : 2]
    endfor
    var registers: dict<any> = {}
    for name in ctx.registers
        registers[name] = getreginfo(name)
    endfor
    var state = {
        lines: getline(1, '$'),
        cursor: getcurpos()[1 : 4],
        mode: mode(1),
        visualmode: visualmode(),
        marks: marks,
        registers: registers,
        search: getreg('/'),
        modified: &modified ? true : false,
        errmsg: v:errmsg,
    }
    if readback
        state.system_clipboard = {
            clipboard: ReadClipboard('clipboard'),
            primary: ReadClipboard('primary'),
        }
    endif
    return state
enddef

def InSelection(): bool
    return mode(1) =~# "^[vVsS\<C-V>\<C-S>]"
enddef

def Autoselect(): bool
    return &clipboard =~# 'autoselect' || (ctx.gui && &guioptions =~# '[aP]')
enddef

# Mouse events as terminal Vim and gVim take them.  A press or release is
# the key code Vim reads for it, at the position test_setmouse() sets; a
# drag is the SGR terminal code that carries its own position, so that a
# gesture can move between events of one typeahead run.  gVim takes every
# event through test_gui_event() and processes the gesture in one go, in a
# low level run outside the ":normal" bookkeeping: inside it Vim answers an
# empty typeahead with a fake key instead of reading the input buffer.
# After a drag Vim peeks for a repeated one, and when nothing is left in
# the typeahead it fakes a CTRL-C that ends the selection on the next key,
# so a drag is always fed together with the event that follows it.
const mouse_keys = {
    left: "\<LeftMouse>", left2: "\<2-LeftMouse>", left3: "\<3-LeftMouse>",
    middle: "\<MiddleMouse>", right: "\<RightMouse>",
}
const release_keys = {left: "\<LeftRelease>", middle: "\<MiddleRelease>", right: "\<RightRelease>"}
const gui_buttons = {left: 0, left2: 0, left3: 0, middle: 1, right: 2, release: 3, drag: 0x43}

def Mouse(events: list<list<any>>)
    if ctx.gui
        # A modeless selection copies the screen, which the typeahead runs
        # have not drawn since the buffer was set up
        redraw
        for [button, row, col] in events
            test_gui_event('mouse', {
                button: gui_buttons[button], row: row, col: col,
                multiclick: button =~ '\d$' ? 1 : 0, modifiers: 0,
            })
        endfor
        feedkeys('', 'Lx!')
        return
    endif
    var pressed = 'left'
    var drags = ''
    for [button, row, col] in events
        if button == 'drag'
            drags ..= printf("\<Esc>[<32;%d;%dM", col, row)
            continue
        endif
        if button != 'release'
            pressed = substitute(button, '\d$', '', '')
        endif
        test_setmouse(row, col)
        g:BucklerFeed(drags .. (button == 'release' ? release_keys[pressed] : mouse_keys[button]))
        drags = ''
    endfor
    if !empty(drags)
        g:BucklerFeed(drags)
    endif
enddef

# Whether the case under way runs with the plugin rather than the model
var plugin_run = false

# The steps of a case run from BucklerRunSteps() in runner.vim, which feeds
# the keys itself and calls back here around every step and for the steps
# that are no keys.
def g:BucklerBeginStep(step: dict<any>)
    if !plugin_run
        model.BeginStep(step)
    endif
enddef

def g:BucklerRunStep(step: dict<any>)
    if has_key(step, 'mouse')
        Mouse(step.mouse)
    elseif has_key(step, 'focus')
        execute('silent! doautocmd <nomodeline> ' .. (step.focus == 'lost' ? 'FocusLost' : 'FocusGained'))
    elseif has_key(step, 'external')
        WriteClipboard(step.external, step.target)
    endif
enddef

def g:BucklerEndStep(step: dict<any>)
    # Between keystrokes the main loop redraws, and with autoselect that is
    # when Vim claims the selection and drops the register text it will
    # yank again on the next read.  The typeahead run skips redraws, so
    # redraw here to put the plugin in front of the same sequence.
    if InSelection() && Autoselect()
        redraw
    endif
    if !plugin_run
        model.EndStep(step)
    endif
enddef

def PluginReset()
    if !empty(plugin_history.history)
        remove(plugin_history.history, 0, -1)
    endif
    if !empty(plugin_clipboard.registers)
        remove(plugin_clipboard.registers, 0, -1)
    endif
    doautocmd <nomodeline> VimEnter
enddef

# Runs the steps of a case from its initial state and returns the state
# after the last one.  Without the plugin the model rewrites the registers
# after every step as the plugin is expected to leave them.
def Execute(case: dict<any>, with_plugin: bool): dict<any>
    var fixture = fx.fixtures[case.fixture]
    StopOwners()
    harness_errors = []
    NewBuffer(fixture, get(case, 'cursor', fixture.cursor))
    ApplySettings(get(case, 'settings', {}))
    ApplyMappings(case.mappings)
    g:vim9buckler_history_length = case.length
    SeedRegisters(fx.seeds[case.seed])
    # A search pattern that matches nothing, so that a motion typed by
    # accident searches the same way in both runs
    setreg('/', 'buckler-no-match')
    v:errmsg = ''
    plugin_run = with_plugin
    if with_plugin
        PluginReset()
    else
        model.Reset(case.length, config.sync)
        model.Startup()
        model.Sync()
    endif
    g:BucklerRunSteps(case.steps)
    var after = Snapshot(case.readback)
    after.harness_errors = copy(harness_errors)
    var tries = 0
    while mode(1) != 'n' && tries < 5
        g:BucklerFeed("\<Esc>")
        tries += 1
    endwhile
    ClearMappings(case.mappings)
    RestoreSettings()
    return after
enddef

def Diff(expected: any, actual: any, path: string, out: list<string>)
    if type(expected) != type(actual)
        add(out, path .. ': expected ' .. string(expected) .. ', actual ' .. string(actual))
    elseif type(expected) == v:t_dict
        for key in sort(keys(expected) + keys(actual))->uniq()
            if !has_key(actual, key)
                add(out, path .. '.' .. key .. ': missing, expected ' .. string(expected[key]))
            elseif !has_key(expected, key)
                add(out, path .. '.' .. key .. ': unexpected ' .. string(actual[key]))
            else
                Diff(expected[key], actual[key], path .. '.' .. key, out)
            endif
        endfor
    elseif expected != actual
        add(out, path .. ': expected ' .. string(expected) .. ', actual ' .. string(actual))
    endif
enddef

def Unmet(case: dict<any>): string
    for need in case.needs
        if need == 'clip_tool'
            if empty(ctx.tool)
                return 'no clipboard tool for display ' .. ctx.display
            endif
        elseif !has(need)
            return 'build lacks ' .. need
        endif
    endfor
    return ''
enddef

# The cases that can reach another state under another display server:
# those that need the clipboard, and those whose middle button inserts the
# star register, which is the system selection where the clipboard works
def ClipboardCase(case: dict<any>): bool
    return indexof(case.needs, (_, need) => need =~ '^clipboard') >= 0
        || indexof(case.steps, (_, s) => indexof(get(s, 'mouse', []), (_, e) => e[0] == 'middle') >= 0) >= 0
enddef

def Selected(case: dict<any>): bool
    return (empty($BUCKLER_MATRICES) || case.matrix =~ $BUCKLER_MATRICES)
        && (empty($BUCKLER_CASES) || case.id =~ $BUCKLER_CASES)
        && ($BUCKLER_SCOPE != 'clipboard' || ClipboardCase(case))
enddef

def LoadPlugin()
    g:vim9buckler_sync_clipboard = config.sync
    g:vim9buckler_history_length = 10
    execute('source ' .. fnameescape(repo_dir .. '/plugin/buckler.vim'))
    if !exists('g:vim9buckler_loaded')
        throw 'plugin did not load'
    endif
enddef

def StepText(step: dict<any>): string
    if has_key(step, 'keys')
        return strtrans(step.keys)
    elseif has_key(step, 'mouse')
        return '<Mouse ' .. join(mapnew(step.mouse, (_, e) => e[0] .. e[1] .. ',' .. e[2]), ' ') .. '>'
    elseif has_key(step, 'focus')
        return '<Focus' .. (step.focus == 'lost' ? 'Lost' : 'Gained') .. '>'
    endif
    return '<' .. step.target .. '=' .. strtrans(step.external) .. '>'
enddef

def XmlEscape(text: string): string
    return text->substitute('&', '\&amp;', 'g')->substitute('<', '\&lt;', 'g')
        ->substitute('>', '\&gt;', 'g')->substitute('"', '\&quot;', 'g')
        ->substitute('[^[:print:]\t\n]', '', 'g')
enddef

def WriteReports(results: list<dict<any>>, run: string)
    var counts = {PASS: 0, FAIL: 0, SKIP: 0}
    var report: list<string> = []
    var xml: list<string> = ['<?xml version="1.0" encoding="UTF-8"?>']
    var cases: list<string> = []
    for result in results
        counts[result.status] += 1
        var name = XmlEscape(result.id)
        if result.status == 'PASS'
            add(cases, printf('  <testcase classname="%s" name="%s"/>', XmlEscape(run), name))
        elseif result.status == 'SKIP'
            add(cases, printf('  <testcase classname="%s" name="%s"><skipped message="%s"/></testcase>',
                XmlEscape(run), name, XmlEscape(result.reason)))
        else
            var detail = join(result.diffs, "\n")
            add(report, 'FAIL ' .. result.id)
            extend(report, mapnew(result.diffs, (_, line) => '    ' .. line))
            add(cases, printf('  <testcase classname="%s" name="%s"><failure message="%s">%s</failure></testcase>',
                XmlEscape(run), name, XmlEscape(result.diffs[0]), XmlEscape(detail)))
        endif
    endfor
    var skips: dict<number> = {}
    for result in results
        if result.status == 'SKIP'
            skips[result.reason] = get(skips, result.reason, 0) + 1
        endif
    endfor
    for [reason, count] in items(skips)
        add(report, printf('SKIP %d cases: %s', count, reason))
    endfor
    add(report, printf('SUMMARY %s: %d passed, %d failed, %d skipped, clipboard %s%s%s',
        run, counts.PASS, counts.FAIL, counts.SKIP,
        ctx.clipboard_working ? 'working' : (ctx.clipboard ? 'present' : 'absent'),
        empty(ctx.tool) ? '' : ' via ' .. ctx.tool,
        $BUCKLER_SCOPE == 'clipboard' ? ', clipboard cases only' : ''))
    add(xml, printf('<testsuite name="%s" tests="%d" failures="%d" skipped="%d">',
        XmlEscape(run), len(results), counts.FAIL, counts.SKIP))
    extend(xml, cases)
    add(xml, '</testsuite>')
    writefile(report, results_dir .. '/report.txt')
    writefile(xml, results_dir .. '/junit.xml')
    writefile(results->copy()->filter((_, r) => r.status != 'PASS')->map((_, r) => json_encode(r)),
        results_dir .. '/results.jsonl')
enddef

def Main()
    Baseline()
    var run = printf('%s/%s/%s', ctx.display, config_name, ctx.gui ? 'gui' : 'term')
    var cases = filter(mx.Cases(ctx), (_, c) => Selected(c))
    var ids: dict<bool> = {}
    for case in cases
        if has_key(ids, case.id)
            throw 'duplicate case id ' .. case.id
        endif
        ids[case.id] = true
    endfor
    augroup buckler_model
        autocmd!
        autocmd TextYankPost * model.OnTextYankPost()
    augroup END
    # The expected states wait for the plugin run in their string form,
    # which needs far less memory than their dictionaries
    var expected_states: dict<string> = {}
    for case in cases
        if empty(Unmet(case))
            expected_states[case.id] = string(Execute(case, false))
        endif
    endfor
    augroup buckler_model
        autocmd!
    augroup END
    StopOwners()
    LoadPlugin()
    var results: list<dict<any>> = []
    for case in cases
        var unmet = Unmet(case)
        if !empty(unmet)
            add(results, {id: case.id, matrix: case.matrix, status: 'SKIP', reason: unmet})
            continue
        endif
        var plugin = Execute(case, true)
        var expected_state = remove(expected_states, case.id)
        var expected: dict<any> = {}
        var diffs: list<string> = []
        # Equal string forms mean equal states, unless both runs share a
        # harness error; the expected state is only rebuilt for the walk
        # that describes a difference
        if !empty(plugin.harness_errors) || string(plugin) != expected_state
            expected = eval(expected_state)
            # A case the harness could not drive fails in either run
            for message in expected.harness_errors + plugin.harness_errors
                add(diffs, 'harness: ' .. message)
            endfor
            remove(expected, 'harness_errors')
            remove(plugin, 'harness_errors')
            Diff(expected, plugin, '', diffs)
        endif
        var result = {
            id: case.id, matrix: case.matrix,
            status: empty(diffs) ? 'PASS' : 'FAIL',
            diffs: diffs,
            steps: mapnew(case.steps, (_, s) => StepText(s)),
        }
        if !empty(diffs)
            extend(result, {expected: expected, actual: plugin})
        endif
        add(results, result)
    endfor
    StopOwners()
    WriteReports(results, run)
    execute(indexof(results, (_, r) => r.status == 'FAIL') >= 0 ? 'cquit!' : 'qall!')
enddef

try
    Main()
catch
    writefile(['HARNESS ERROR ' .. v:exception .. ' @ ' .. v:throwpoint], results_dir .. '/report.txt')
    cquit!
endtry
