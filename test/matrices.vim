vim9script

# Case generation.  Every matrix is a product of axes narrowed by a filter;
# a case records the steps a user performs.  The history model in model.vim
# defines the expected outcome of every step, so no case carries an
# expectation of its own.
#
# Case fields:
#   id        unique name, selectable with BUCKLER_CASES
#   matrix    matrix name, selectable with BUCKLER_MATRICES
#   fixture   buffer the case starts from, see fixtures.vim
#   cursor    optional cursor override
#   seed      register seed, see fixtures.vim
#   settings  options set for the case
#   mappings  mappings defined for the case, {mode: {lhs: rhs}}
#   length    g:vim9buckler_history_length for the case
#   steps     list of steps, see below
#   readback  whether the system clipboard is read with the tool afterwards
#   needs     has() features the case requires, plus clip_tool
#
# Steps, each holding at most one operation that writes or reads registers:
#   {keys: ...}                  keys typed
#   {keys: ..., put: true}       a Visual put, whose replaced text is no yank
#   {mouse: [[button, row, col], ...]}
#                                mouse events, see the mouse matrix
#   {focus: 'lost' | 'gained'}   a focus event
#   {external: text, target: 'clipboard' | 'primary' | 'both'}
#                                text copied by another application, or a
#                                cleared selection when the text is empty

import './fixtures.vim' as fx

export const configs: dict<dict<any>> = {
    default: {sync: true},
    nosync: {sync: false},
}

const fixture_names = keys(fx.fixtures)->sort()
const seed_names = keys(fx.seeds)->sort()
const lengths = [10, 15]

const clipboards = [
    '', 'unnamed', 'unnamedplus', 'unnamed,unnamedplus', 'unnamedplus,unnamed',
    'autoselect', 'autoselectplus', 'autoselect,unnamed', 'autoselectplus,unnamedplus',
    'autoselect,unnamedplus', 'autoselectplus,unnamed', 'autoselect,autoselectplus,unnamed',
    'unnamed,unnamedplus,autoselect',
    'exclude:.*', 'unnamedplus,exclude:.*',
]
const clipboard_registers = ['unnamed', 'unnamedplus', 'unnamed,unnamedplus', 'unnamedplus,unnamed']
# The 'clipboard' values the focus events run under: the plugin watches a
# register under the first four and nothing without one
const focus_clipboards = clipboard_registers + ['']

const default_guioptions = 'egimrLtT'
const guioptions = ['', 'a', 'A', 'P', 'aA', 'aP', 'AP', 'aAP']

const prefixes = ['', '""', '"0', '"1', '"3', '"9', '"a', '"A', '"+', '"*', '"_']

# Visual selections used wherever a case needs a Visual area
const selections: dict<list<string>> = {
    v: ['ve', 'vjl', 'v$', 'vb'],
    V: ['V', 'Vj', 'Vk'],
    "\<C-V>": ["\<C-V>jl", "\<C-V>j$", "\<C-V>kh"],
}
const all_selections = selections.v + selections.V + selections["\<C-V>"]

# Crosses the axes in the given order so that ids are stable
export def Product(axes: list<list<any>>): list<dict<any>>
    var result: list<dict<any>> = [{}]
    for [name, values] in axes
        var next: list<dict<any>> = []
        for combo in result
            for value in values
                var extended = copy(combo)
                extended[name] = value
                add(next, extended)
            endfor
        endfor
        result = next
    endfor
    return result
enddef

def K(keys: string): dict<any>
    return {keys: keys}
enddef

def Put(keys: string): dict<any>
    return {keys: keys, put: true}
enddef

def Gesture(events: list<list<any>>): dict<any>
    return {mouse: events}
enddef

def Focus(event: string): dict<any>
    return {focus: event}
enddef

def External(text: string, target: string): dict<any>
    return {external: text, target: target}
enddef

# Steps from plain strings, step dicts, or a mix
def Steps(items: list<any>): list<dict<any>>
    return mapnew(items, (_, item) => type(item) == v:t_string ? K(item) : item)
enddef

# Raw text of a step; Id() encodes the special keys once for every part
def StepText(step: dict<any>): string
    if has_key(step, 'keys')
        return step.keys
    elseif has_key(step, 'mouse')
        return join(mapnew(step.mouse, (_, e) => e[0] .. e[1] .. ',' .. e[2]), ' ')
    elseif has_key(step, 'focus')
        return step.focus
    endif
    return step.target .. '=' .. step.external
enddef

def KeysOf(steps: list<dict<any>>): string
    return join(mapnew(filter(copy(steps), (_, s) => has_key(s, 'keys')), (_, s) => s.keys), '')
enddef

def Needs(case: dict<any>): list<string>
    var needs: list<string> = []
    var keys = KeysOf(case.steps)
    var external = indexof(case.steps, (_, s) => has_key(s, 'external')) >= 0
    # The autoselect flags of 'guioptions' copy a selection to a clipboard
    # register as the 'clipboard' option does
    if external || case.readback
        extend(needs, ['clipboard_working', 'clip_tool'])
    elseif has_key(case.settings, 'clipboard') || get(case.settings, 'guioptions', '') =~# '[aAP]'
            || keys =~ '"[*+]\|\%(yank\|delete\|put!\=\) [*+]\|setreg(.[*+]\|\<C-R>[*+]'
        add(needs, 'clipboard')
    endif
    if has_key(case.settings, 'guioptions')
        add(needs, 'gui_running')
    endif
    if indexof(case.steps, (_, s) => has_key(s, 'mouse')) >= 0
        extend(needs, ['mouse', 'mouse_sgr'])
    endif
    return needs
enddef

def Id(matrix: string, parts: list<string>): string
    return matrix .. '/' .. join(filter(mapnew(parts, (_, p) => keytrans(p)), (_, p) => !empty(p)), '/')
enddef

def Case(matrix: string, parts: list<string>, spec: dict<any>): dict<any>
    var case = extend({
        matrix: matrix,
        id: Id(matrix, parts),
        fixture: 'ascii',
        seed: 'full',
        settings: {},
        mappings: {},
        length: 10,
        readback: false,
    }, spec)
    case.steps = Steps(case.steps)
    case.needs = Needs(case)
    return case
enddef


# Every motion and text object as the target of yank, delete and change in
# Normal mode, from each cursor position of each fixture.
const motions: list<dict<any>> = [
    {keys: 'w'}, {keys: 'W'}, {keys: 'e'}, {keys: 'E'}, {keys: 'b'}, {keys: 'B'},
    {keys: 'ge'}, {keys: 'gE'}, {keys: '0'}, {keys: '^'}, {keys: '$'},
    {keys: 'h'}, {keys: 'l'}, {keys: 'j'}, {keys: 'k'}, {keys: 'gj'}, {keys: 'gk'},
    {keys: '+'}, {keys: '-'}, {keys: '_'}, {keys: '|'}, {keys: 'G'}, {keys: 'gg'},
    {keys: 'H'}, {keys: 'L'}, {keys: 'M'},
    {keys: 'fe'}, {keys: 'te'}, {keys: 'Fo'}, {keys: 'To'},
    {keys: ';', prelude: 'fe'}, {keys: ',', prelude: 'fe'},
    {keys: '('}, {keys: ')'}, {keys: '{'}, {keys: '}'}, {keys: '%'},
    {keys: "/line\<CR>"}, {keys: "?one\<CR>"},
    {keys: 'n', prelude: "/line\<CR>"}, {keys: 'N', prelude: "/line\<CR>"},
    {keys: 'iw'}, {keys: 'aw'}, {keys: 'iW'}, {keys: 'aW'},
    {keys: 'is'}, {keys: 'as'}, {keys: 'ip'}, {keys: 'ap'},
    {keys: 'i('}, {keys: 'a('}, {keys: 'ib'}, {keys: 'ab'},
    {keys: 'i{'}, {keys: 'a{'}, {keys: 'i['}, {keys: 'a['}, {keys: 'i<'}, {keys: 'a<'},
    {keys: 'i"'}, {keys: 'a"'}, {keys: "i'"}, {keys: "a'"}, {keys: 'i`'},
    {keys: 'it'}, {keys: 'at'},
    {keys: 'gn', prelude: "/line\<CR>gg"}, {keys: 'gN', prelude: "/line\<CR>G"},
    {keys: 'vj'}, {keys: 'Vw'}, {keys: "\<C-V>j"}, {keys: 'v$'}, {keys: 'viw'},
]

# Marks as motion targets, and the marks an operation leaves behind
const mark_motions: list<dict<any>> = [
    {keys: '`a'}, {keys: "'a"}, {keys: '`b'}, {keys: "'b"},
    {keys: '`[', prelude: 'yiw'}, {keys: '`]', prelude: 'yiw'},
    {keys: '`[', prelude: 'dw'}, {keys: '`]', prelude: 'dw'},
    {keys: '`<', prelude: "viw\<Esc>"}, {keys: '`>', prelude: "viw\<Esc>"},
    {keys: '`.', prelude: "ix\<Esc>"}, {keys: '`^', prelude: "ix\<Esc>"},
    {keys: '`c', prelude: 'mcj'}, {keys: "'c", prelude: 'mcjj'},
]

const operator_suffix = {y: '', d: '', c: "NEW\<Esc>"}

def MotionCases(matrix: string, table: list<dict<any>>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['op', ['y', 'd', 'c']],
            ['motion', table],
            ['count', ['', '2']],
            ['fixture', fixture_names],
    ])
        var prelude = get(combo.motion, 'prelude', '')
        for cursor in fx.fixtures[combo.fixture].cursors
            var parts = [combo.op, prelude, combo.motion.keys, combo.count, combo.fixture, join(cursor, ',')]
            add(cases, Case(matrix, parts, {
                fixture: combo.fixture,
                cursor: cursor,
                steps: [prelude .. combo.op .. combo.count .. combo.motion.keys .. operator_suffix[combo.op]],
            }))
        endfor
    endfor
    return cases
enddef

def Motions(ctx: dict<any>): list<dict<any>>
    return MotionCases('motions', motions)
enddef

def Marks(ctx: dict<any>): list<dict<any>>
    return MotionCases('marks', mark_motions)
enddef


# Yank keys other than operator and motion: linewise and Visual yanks with
# counts and register prefixes, and yanks from a suspended Insert or
# Replace edit.
def Yank(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['op', ['yy', 'Y', 'y$', 'yiw', 'yj']],
            ['count', ['', '2', '3']],
            ['prefix', prefixes],
            ['fixture', fixture_names],
    ])
        add(cases, Case('yank', [combo.prefix .. combo.count .. combo.op, combo.fixture], {
            fixture: combo.fixture,
            steps: [combo.prefix .. combo.count .. combo.op],
        }))
    endfor
    for combo in Product([
            ['selection', all_selections],
            ['prefix', prefixes],
            ['op', ['y', 'Y']],
            ['fixture', ['ascii', 'multibyte']],
    ])
        add(cases, Case('yank', [combo.selection .. combo.prefix .. combo.op, combo.fixture], {
            fixture: combo.fixture,
            steps: [combo.selection .. combo.prefix .. combo.op],
        }))
    endfor
    for combo in Product([
            ['mode', ['i', 'R']],
            ['op', ['yy', 'yw', 'yiw', 'y$', '"ayy', '"1yy']],
            ['fixture', fixture_names],
    ])
        add(cases, Case('yank', [combo.mode .. "\<C-O>" .. combo.op, combo.fixture], {
            fixture: combo.fixture,
            steps: [combo.mode .. "\<C-O>" .. combo.op .. "\<Esc>"],
        }))
    endfor
    return cases
enddef


# Change and delete keys across the modes that can start them, with counts
# before the operator and the motion, and with every register prefix.
const operators: list<dict<any>> = [
    {lhs: 'c', family: 'change', modes: ['n', 'x', 'i', 'R'], motion: true},
    {lhs: 'C', family: 'change', modes: ['n', 'x', 'i', 'R']},
    {lhs: 's', family: 'change', modes: ['n', 'x', 'i', 'R']},
    {lhs: 'S', family: 'change', modes: ['n', 'x', 'i', 'R']},
    {lhs: 'cc', family: 'change', modes: ['n', 'i', 'R']},
    {lhs: 'R', family: 'change', modes: ['x']},
    {lhs: 'd', family: 'delete', modes: ['n', 'x', 'i', 'R'], motion: true},
    {lhs: 'D', family: 'delete', modes: ['n', 'x', 'i', 'R']},
    {lhs: 'x', family: 'delete', modes: ['n', 'x', 'i', 'R']},
    {lhs: 'X', family: 'delete', modes: ['n', 'x', 'i', 'R']},
    {lhs: 'dd', family: 'delete', modes: ['n', 'i', 'R']},
    {lhs: "\<Del>", family: 'delete', modes: ['n', 'x', 'i', 'R'], nocount: true},
    {lhs: "\<kDel>", family: 'delete', modes: ['n', 'x', 'i', 'R'], nocount: true},
]

const counts: dict<list<string>> = {
    none: ['', ''],
    op: ['2', ''],
    motion: ['', '3'],
    both: ['2', '3'],
}

def Operators(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['op', operators],
            ['prefix', prefixes],
            ['mode', ['n', 'v', 'V', "\<C-V>", 'i', 'R']],
            ['count', keys(counts)->sort()],
            ['motion', ['w', 'j', 'iw']],
            ['fixture', fixture_names],
    ])
        var op = combo.op
        var visual = combo.mode =~ "^[vV\<C-V>]$"
        if index(op.modes, visual ? 'x' : combo.mode) < 0
            continue
        endif
        # A register prefix is crossed with the keys alone, not with the counts
        var prefixed = !empty(combo.prefix)
        if prefixed && (combo.count != 'none' || index(['ascii', 'multibyte'], combo.fixture) < 0)
            continue
        endif
        var has_motion = get(op, 'motion', false) && !visual
        if !has_motion && combo.motion != 'w'
            continue
        endif
        var [opcount, mcount] = counts[combo.count]
        if (!has_motion && !empty(mcount)) || (get(op, 'nocount', false) && !empty(opcount))
            continue
        endif
        if visual && !empty(opcount)
            continue
        endif
        var tail = has_motion ? mcount .. combo.motion : ''
        var suffix = op.family == 'change' ? "NEW\<Esc>" : ''
        var selections_for = visual ? (prefixed ? selections[combo.mode][: 0] : selections[combo.mode]) : ['']
        for selection in selections_for
            var prelude = visual ? selection : (combo.mode == 'n' ? '' : combo.mode .. "\<C-O>")
            var parts = [combo.prefix .. op.lhs, combo.mode, selection, combo.count, has_motion ? combo.motion : '', combo.fixture]
            add(cases, Case(op.family, parts, {
                fixture: combo.fixture,
                steps: [prelude .. combo.prefix .. opcount .. op.lhs .. tail .. suffix],
            }))
        endfor
    endfor
    return cases
enddef


# Typing over a Select mode selection entered every way Vim offers, from
# Normal mode and from a suspended Insert or Replace edit.
const select_entries: list<dict<any>> = [
    {name: 'gh', prelude: 'gh'},
    {name: 'gH', prelude: 'gH'},
    {name: 'g<C-H>', prelude: "g\<C-H>"},
    {name: 'v<C-G>', prelude: "ve\<C-G>"},
    {name: 'V<C-G>', prelude: "Vj\<C-G>"},
    {name: '<C-V><C-G>', prelude: "\<C-V>jl\<C-G>"},
    {name: 'gh<S-Right>', prelude: "gh\<S-Right>\<S-Right>", settings: {keymodel: 'startsel'}},
    {name: 'gH<S-Down>', prelude: "gH\<S-Down>", settings: {keymodel: 'startsel'}},
    {name: 'selectmode=cmd', prelude: "v\<S-Right>", settings: {selectmode: 'cmd', keymodel: 'startsel'}},
    {name: 'selectmode=cmd-V', prelude: 'V', settings: {selectmode: 'cmd'}},
    {name: 'selectmode=key', prelude: "\<S-Right>\<S-Right>", settings: {selectmode: 'key', keymodel: 'startsel'}},
    {name: 'selectmode=key<S-Down>', prelude: "\<S-Down>", settings: {selectmode: 'key', keymodel: 'startsel'}},
    {name: 'i<S-Right>', prelude: "i\<S-Right>\<S-Right>", settings: {selectmode: 'key', keymodel: 'startsel'}},
    {name: 'i<S-Down>', prelude: "i\<S-Down>", settings: {selectmode: 'key', keymodel: 'startsel'}},
    {name: 'R<S-Right>', prelude: "R\<S-Right>\<S-Right>", settings: {selectmode: 'key', keymodel: 'startsel'}},
    {name: 'i<C-O>gh', prelude: "i\<C-O>gh"},
    {name: 'i<C-O>v<C-G>', prelude: "i\<C-O>ve\<C-G>"},
    {name: 'R<C-O>v<C-G>', prelude: "R\<C-O>ve\<C-G>"},
]

const select_keys = ['X', "\<BS>", "\<Del>", "\<CR>", ' ', 'ю']

# Registers CTRL-R names for the text that typing deletes: a named register
# leaves the history alone, the 0 register replaces its item
const select_registers = ['a', '0']

# Visual commands run from Select mode: one command through CTRL-O, puts
# among them, and an operator after CTRL-G made the selection Visual again,
# typed in one run with the keys that enter Select mode
const select_commands: list<any> = [
    "\<C-O>y", "\<C-O>d", Put("\<C-O>p"), Put("\<C-O>P"), "\<C-G>d", "\<C-G>y",
]

def Select(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['entry', select_entries],
            ['key', select_keys],
            ['fixture', ['ascii', 'multibyte', 'single']],
    ])
        add(cases, Case('select', [combo.entry.name, combo.key, combo.fixture], {
            fixture: combo.fixture,
            settings: get(combo.entry, 'settings', {}),
            steps: [combo.entry.prelude .. combo.key .. "\<Esc>"],
        }))
    endfor
    for combo in Product([
            ['entry', select_entries],
            ['register', select_registers],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var keys = "\<C-R>" .. combo.register .. 'X'
        add(cases, Case('select', [combo.entry.name, keys, combo.fixture], {
            fixture: combo.fixture,
            settings: get(combo.entry, 'settings', {}),
            steps: [combo.entry.prelude .. keys .. "\<Esc>"],
        }))
    endfor
    for combo in Product([
            ['entry', select_entries],
            ['command', select_commands],
            ['fixture', ['ascii', 'multibyte', 'single']],
    ])
        var step = Steps([combo.command])[0]
        add(cases, Case('select', [combo.entry.name, StepText(step), combo.fixture], {
            fixture: combo.fixture,
            settings: get(combo.entry, 'settings', {}),
            steps: [extend(copy(step), {keys: combo.entry.prelude .. step.keys})],
        }))
    endfor
    return cases
enddef


# Visual puts: a step that builds the history, the selection, the put key,
# and what follows the put.  Normal mode puts are the control group that
# yanks nothing; a repeated put of a numbered register moves on to the next
# register, and puts over the last line and from an Insert excursion are
# the edges of the Visual put.
const builders: list<string> = ['yy', 'dd', '"ayy', '3yy', 'yiw', "\<C-V>jly"]

const put_keys: list<dict<any>> = [
    {key: 'p'}, {key: 'P'}, {key: 'gp'}, {key: 'gP'}, {key: ']p'}, {key: '[P'}, {key: '2p'},
    {key: "\<F5>", mappings: {x: {'<F5>': 'p'}}},
]

const put_prefixes = ['"0', '"1', '"a', '"+', '"*']

# Steps after a Visual put: a second put of the same text, a put over a
# further selection, a repeat, which deletes without putting, a put through
# :normal, an undone put
const followups: list<list<any>> = [
    ['p'],
    ['jV', Put('p')],
    ['j.'],
    [Put(":normal Vp\<CR>")],
    ['u', 'p'],
    ['gv', Put('p')],
]

const normal_puts: list<string> = [
    'p', 'P', 'gp', 'gP', ']p', ']P', '[p', '[P', 'zp', 'zP', '3p', '2P', ":put\<CR>", ":put!\<CR>",
    "i\<C-R>\"\<Esc>", "i\<C-R>0\<Esc>", "i\<C-R>+\<Esc>", "i\<C-R>\<C-R>\"\<Esc>",
    "i\<C-R>\<C-O>\"\<Esc>", "i\<C-R>\<C-P>\"\<Esc>", ":\<C-R>\"\<Esc>", "A\<C-O>p\<Esc>",
]

# Puts repeated with ., which moves on to the next numbered register
# after a numbered one and repeats a plain one as it is
const numbered_puts: list<list<any>> = [
    ['"1p', 'u', '.'], ['"1p', '.', '.'], ['"1P', 'u', '.'], ['"2p', 'u', '.'], ['"9p', 'u', '.'], ['"0p', '.'],
    ['p', '.'], ['P', '.'], ['3p', '.'],
]

const edge_puts: list<list<any>> = [
    ['yy', 'GV', Put('p')], ['yiw', 'G$viw', Put('P')], ['yiw', "jA\<C-O>vb", Put('p')], ['yy', "jA\<C-O>V", Put('p')],
]

def PutCases(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['builder', builders],
            ['selection', all_selections],
            ['put', put_keys],
            ['fixture', ['ascii', 'multibyte', 'indented']],
    ])
        add(cases, Case('put', ['visual', combo.builder, 'j' .. combo.selection, combo.put.key, combo.fixture], {
            fixture: combo.fixture,
            mappings: get(combo.put, 'mappings', {}),
            steps: [combo.builder, 'j' .. combo.selection, Put(combo.put.key)],
        }))
    endfor
    for combo in Product([
            ['builder', ['yy', 'dd']],
            ['selection', ['ve', 'Vj', "\<C-V>jl"]],
            ['key', ['p', 'P', '2p']],
            ['prefix', put_prefixes],
            ['fixture', ['ascii', 'multibyte', 'indented']],
    ])
        add(cases, Case('put', ['register', combo.builder, 'j' .. combo.selection, combo.prefix .. combo.key, combo.fixture], {
            fixture: combo.fixture,
            steps: [combo.builder, 'j' .. combo.selection, Put(combo.prefix .. combo.key)],
        }))
    endfor
    for combo in Product([
            ['builder', ['yy', 'dd', '"ayy']],
            ['selection', ['ve', 'Vj', "\<C-V>jl"]],
            ['key', ['p', 'P']],
            ['followup', followups],
            ['fixture', ['ascii', 'multibyte', 'indented']],
    ])
        var steps = [combo.builder, 'j' .. combo.selection, Put(combo.key)] + combo.followup
        var parts = ['after'] + mapnew(Steps(steps), (_, s) => StepText(s)) + [combo.fixture]
        add(cases, Case('put', parts, {fixture: combo.fixture, steps: steps}))
    endfor
    for combo in Product([
            ['builder', builders],
            ['put', normal_puts],
            ['fixture', ['ascii', 'multibyte', 'indented']],
    ])
        add(cases, Case('put', ['normal', combo.builder, 'j' .. combo.put, combo.fixture], {
            fixture: combo.fixture,
            steps: [combo.builder, 'j' .. combo.put],
        }))
    endfor
    for combo in Product([
            ['builder', ['', 'yy', 'dd']],
            ['puts', numbered_puts],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var steps = (empty(combo.builder) ? [] : [combo.builder]) + combo.puts
        add(cases, Case('put', ['numbered', combo.builder] + combo.puts + [combo.fixture], {
            fixture: combo.fixture,
            steps: steps,
        }))
    endfor
    for combo in Product([
            ['steps', edge_puts],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var parts = ['edge'] + mapnew(Steps(combo.steps), (_, s) => StepText(s)) + [combo.fixture]
        add(cases, Case('put', parts, {fixture: combo.fixture, steps: combo.steps}))
    endfor
    return cases
enddef


# Operations against every register seed and history length, so that the
# startup history, the numbered registers and the unnamed pointer are
# checked, writes that bypass TextYankPost, followed by a yank and on
# their own, and yanks and deletes of nothing into every kind of register.
const register_ops: list<string> = [
    'yy', 'dd', '"1dd', '"0yy', '"0dd', '""yy', '"2yy', '"5yy', '"9yy', '"ayy', '"Ayy',
    '"_dd', 'x', "cwNEW\<Esc>", '"+yy', '"*yy', '"-yy', 'yiw', 'dw', 'D', 'Y', 'J',
]

const bypass_writes: list<string> = [
    'q1yyq', 'q"yyq', 'qayyq', ":let @0 = 'foreign'\<CR>", ":let @\" = 'foreign'\<CR>",
    ":let @9 = 'foreign'\<CR>", ":call setreg('+', 'foreign')\<CR>", ":call setreg('1', 'foreign', 'V')\<CR>",
]

# The same writes as the last register operation of a case, the recordings
# split so that the write of q is a step of its own: a register written
# without an event stays as Vim wrote it
const bypass_alone: list<list<string>> = [
    ['q1', 'yy', 'q'], ['q"', 'yy', 'q'], ['qa', 'yy', 'q'],
] + mapnew(bypass_writes[3 :], (_, write) => [write])

# Yanks and deletes of an empty region from the first column: the yank
# reports an empty item, the delete reports nothing
const empty_ops: list<string> = [
    'y0', '""y0', '"0y0', '"1y0', '"3y0', '"9y0', '"ay0', '"+y0', '"_y0', 'd0', '"1d0', '"ad0',
]

# Operations on an empty line: the deletes of a character report nothing,
# the linewise ones report an item without text
const empty_line_ops: list<string> = [
    'x', 'X', 'dd', 'yy', 'Y', 'D', 'dw', 'yiw', 'J', "cwNEW\<Esc>", 'vd', 'vy', 'Vd', 'Vy',
    '"1dd', '"3yy', '"ayy', '"add', '"+yy',
]

def Registers(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['op', register_ops],
            ['seed', seed_names],
            ['length', lengths],
            ['fixture', ['ascii', 'multibyte']],
    ])
        add(cases, Case('registers', [combo.op, combo.seed, string(combo.length), combo.fixture], {
            fixture: combo.fixture,
            seed: combo.seed,
            length: combo.length,
            steps: [combo.op, 'p'],
        }))
    endfor
    for combo in Product([
            ['write', bypass_writes],
            ['op', ['yy', 'dd']],
            ['seed', ['full', 'partial']],
            ['length', lengths],
    ])
        add(cases, Case('registers', [combo.write, 'j' .. combo.op, combo.seed, string(combo.length)], {
            seed: combo.seed,
            length: combo.length,
            steps: [combo.write, 'j' .. combo.op, 'p'],
        }))
    endfor
    for combo in Product([
            ['write', bypass_alone],
            ['seed', ['full', 'partial']],
            ['length', lengths],
    ])
        add(cases, Case('registers', ['alone'] + combo.write + [combo.seed, string(combo.length)], {
            seed: combo.seed,
            length: combo.length,
            steps: combo.write + ['p'],
        }))
    endfor
    for combo in Product([
            ['op', empty_ops],
            ['seed', ['full', 'partial', 'empty']],
    ])
        add(cases, Case('registers', ['nothing', combo.op, combo.seed], {
            cursor: [1, 1],
            seed: combo.seed,
            steps: [combo.op, 'p'],
        }))
    endfor
    for combo in Product([
            ['op', empty_line_ops],
            ['seed', ['full', 'empty']],
    ])
        add(cases, Case('registers', ['emptyline', combo.op, combo.seed], {
            fixture: 'sparse',
            cursor: [2, 1],
            seed: combo.seed,
            steps: [combo.op, 'p'],
        }))
    endfor
    return cases
enddef


def SettingsId(settings: dict<any>): string
    return join(mapnew(sort(keys(settings)), (_, k) => k .. '=' .. string(settings[k])->trim("'")), ',')
enddef

# Operations grouped by what a setting can influence
const setting_ops: dict<list<list<any>>> = {
    yank: [['yy'], ['yiw'], ['y$'], ['vey'], ['Vjy'], ["\<C-V>jly"], ['3yy']],
    delete: [['dw'], ['dd'], ['x'], ['D'], ['ved'], ['Vjd'], ["\<C-V>jld"]],
    change: [["cwNEW\<Esc>"], ["ccNEW\<Esc>"], ["SNEW\<Esc>"], ["vjlcNEW\<Esc>"]],
    select: [
        ["ve\<C-G>X\<Esc>"], ["Vj\<C-G>\<BS>"], ["gh\<Right>\<Right>Y\<Esc>"],
        ["ve\<C-G>\<C-O>d"], ["gh\<Right>\<Right>", Put("\<C-O>p")],
    ],
    put: [
        ['yy', 'jV', Put('p')], ['yy', 'jV', Put('p'), 'p'], ['dd', 've', Put('P')],
        ['yiw', 'jviw', Put('p'), 'j.'], ['yy', 'jp'],
        ['yiw', 'jviw', Put('"0p')], ['yiw', 'jviw', Put('"ap')], ['yiw', 'jviw', Put('"*p')], ['yiw', 'jviw', Put('"+p')],
    ],
    insert: [["i\<C-O>yy"], ["i\<C-O>dw"], ["R\<C-O>x"]],
    autoselect: [
        ["ve\<Esc>"], ['ve', "\<Esc>"], ["v\<Esc>"], ['V>'], ['VJ'], ['vl~'], ['Vu'], ['VU'], ['vlrZ'],
        ["\<C-V>jIxx\<Esc>"], ['vey'], ['Vd'], ["vecNEW\<Esc>"], ['V', Put('p')], ['ve', Put('P')],
        ["gh\<Right>\<Right>\<Esc>"], ["ve\<C-G>\<Esc>"], ["ve\<C-G>X\<Esc>"], ['vjy'],
        ["veo\<Esc>"], ['ve', 'y'], ['V', 'j', 'd'],
        ["ve\<Esc>", 'p'], ['vl~', 'p'], ["ve\<Esc>", '"1p'], ["Vj\<Esc>", 'p'], ["\<C-V>jl\<Esc>", 'p'],
        ["ve\<Esc>", "jve\<Esc>", 'p'], ['yiw', "viw\<Esc>", '"1p'], ["ve\<Esc>", 'jyy', '"1p'],
        ["ve\<Esc>", 'jdd'],
        ["gh\<Right>\<Right>\<C-O>J"], ["ve\<C-G>\<C-O>~"], ["gh\<Right>\<Right>\<C-O>y"],
        ["ve\<C-G>\<C-G>d"], ["gh\<Right>\<Right>", Put("\<C-O>p")],
    ],
    lineend: [
        ['$x'], ['$3x'], ['0X'], ['$dl'], ['0dh'], ['$d '], ["0d\<BS>"], ['$d$'], ['$vd'], ['v$d'], ['$y '], ['$yl'],
    ],
    shifted: [["\<S-Right>\<S-Right>d"], ["\<S-Down>y"], ["v\<S-Right>x"], ["\<S-End>cNEW\<Esc>"]],
    keyselect: [["\<S-Right>\<S-Right>X\<Esc>"], ["\<S-Down>\<BS>"], ["\<S-End>X\<Esc>"]],
    cmdselect: [["v\<S-Right>X\<Esc>"], ["VX\<Esc>"], ["\<C-V>\<S-Right>\<BS>"]],
    folded: [['zfjdd'], ['zfjdj'], ['zfjyy'], ['zfjyj'], ["zfjccNEW\<Esc>"], ['zfjx'], ['zfjVd'], ['zfjVy']],
    repeat: [['dw', '.'], ['x', 'yiw', '.'], ["cwNEW\<Esc>", 'j.'], ['yy', 'j.'], ['yiw', 'w.'], ['dd', '3.']],
    empty: [['0d0'], ['vd'], ["cwNEW\<Esc>"], ['diw'], ['x'], ['yy'], ['yiw']],
}

const empty_fixtures = ['sparse']

def SettingsTable(ctx: dict<any>): list<dict<any>>
    var table: list<dict<any>> = []
    for clipboard in clipboards
        var groups = ['yank', 'delete', 'change', 'select', 'put', 'insert']
        if clipboard =~ 'autoselect'
            add(groups, 'autoselect')
        endif
        add(table, {settings: {clipboard: clipboard}, groups: groups})
    endfor
    extend(table, [
        {settings: {selection: 'exclusive'}, groups: ['yank', 'delete', 'change', 'select', 'put', 'lineend']},
        {settings: {selection: 'old'}, groups: ['yank', 'delete', 'change', 'select', 'put', 'lineend']},
        {settings: {selectmode: 'mouse'}, groups: ['delete', 'select']},
        {settings: {selectmode: 'key', keymodel: 'startsel'}, groups: ['keyselect', 'select']},
        {settings: {selectmode: 'cmd', keymodel: 'startsel'}, groups: ['cmdselect', 'insert']},
        {settings: {keymodel: 'startsel'}, groups: ['shifted']},
        {settings: {keymodel: 'stopsel'}, groups: ['delete', 'select']},
        {settings: {keymodel: 'startsel,stopsel'}, groups: ['shifted', 'select']},
        {settings: {virtualedit: 'all'}, groups: ['yank', 'delete', 'change', 'put', 'lineend']},
        {settings: {virtualedit: 'onemore'}, groups: ['yank', 'delete', 'change', 'put', 'lineend']},
        {settings: {virtualedit: 'block'}, groups: ['yank', 'delete', 'change', 'put', 'lineend']},
        {settings: {virtualedit: 'insert'}, groups: ['insert', 'change']},
        {settings: {cpoptions: 'aABceFsy'}, groups: ['repeat', 'yank', 'delete']},
        {settings: {cpoptions: 'aABceFsE'}, groups: ['empty', 'delete']},
        {settings: {cpoptions: 'aABceFs$'}, groups: ['change']},
        {settings: {startofline: false}, groups: ['yank', 'delete', 'change', 'put']},
        {settings: {whichwrap: 'b,s,h,l,<,>,[,]'}, groups: ['lineend']},
        {settings: {whichwrap: ''}, groups: ['lineend']},
        {settings: {autoindent: true}, groups: ['change', 'select', 'put']},
        {settings: {modifiable: false}, groups: ['yank', 'delete', 'change', 'select', 'put']},
        {settings: {readonly: true}, groups: ['yank', 'delete', 'change', 'select', 'put']},
        {settings: {timeout: false}, groups: ['delete', 'change', 'select']},
        {settings: {timeoutlen: 1}, groups: ['delete', 'change', 'select']},
        {settings: {ttimeout: true, ttimeoutlen: 10}, groups: ['delete', 'change', 'select']},
        {settings: {foldmethod: 'manual'}, groups: ['folded']},
    ])
    for flags in guioptions
        var go = flags .. default_guioptions
        add(table, {settings: {guioptions: go}, groups: ['yank', 'delete', 'put', 'select', 'autoselect']})
        for clipboard in clipboard_registers
            add(table, {settings: {guioptions: go, clipboard: clipboard}, groups: ['yank', 'put', 'autoselect']})
        endfor
    endfor
    return table
enddef

def Settings(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for entry in SettingsTable(ctx)
        for group in entry.groups
            for steps in setting_ops[group]
                for fixture in group == 'empty' ? empty_fixtures : ['ascii', 'indented']
                    var parts = [SettingsId(entry.settings), group] + mapnew(Steps(steps), (_, s) => StepText(s)) + [fixture]
                    add(cases, Case('settings', parts, {
                        fixture: fixture,
                        settings: entry.settings,
                        steps: steps,
                    }))
                endfor
            endfor
        endfor
    endfor
    return cases
enddef


# Text copied by another application while Vim has no focus, including the
# text of the head, which pushes nothing, and of an older item, which does,
# a write into the unnamed register before the focus events, which is no
# clipboard change, the system clipboard read back after Vim wrote it, and
# the startup under clipboard registers whose texts differ.
const external_texts: dict<string> = {
    word: 'external text',
    line: "external line\n",
    multi: "first external line\nsecond external line\n",
    multibyte: 'внешний текст',
}

# The head of the history under a seed and a 'clipboard' value, see
# model.vim Startup(): the clipboard register when one is named and holds
# text, otherwise the 0 register
def HeadText(seed: dict<any>, clipboard: string): string
    var text = clipboard =~ 'unnamed' ? fx.SeedValue(seed, '+') : ''
    return empty(text) ? fx.SeedValue(seed, '0') : text
enddef

def FocusSequences(text: string, target: string): dict<list<any>>
    return {
        copy: [Focus('lost'), External(text, target), Focus('gained')],
        copy_gained_twice: [Focus('lost'), External(text, target), Focus('gained'), Focus('gained')],
        copy_then_yank: [Focus('lost'), External(text, target), Focus('gained'), 'jyy'],
        copy_then_delete: [Focus('lost'), External(text, target), Focus('gained'), 'jdd'],
        copy_then_put: [Focus('lost'), External(text, target), Focus('gained'), 'jV', Put('p')],
    }
enddef

# Sequences whose external text is given: a cleared selection, the text of
# the head and the text of an older item
def FixedSequences(target: string, seed: dict<any>, clipboard: string): dict<list<any>>
    return {
        clear: [Focus('lost'), External('', target), Focus('gained')],
        same_as_head: [Focus('lost'), External(HeadText(seed, clipboard), target), Focus('gained')],
        older_item: [Focus('lost'), External(fx.SeedText('1'), target), Focus('gained')],
    }
enddef

# Seeds whose clipboard registers differ: the plugin pushes the primary
# register when it loads and writes the head into both
const split_seeds = ['split', 'staronly']

const readback_ops: list<list<any>> = [
    ['yy'], ['dd'], ['yiw'], ['"ayy'], ['"+yy'], ['yy', 'jV', Put('p')], ['x'], ['ve', "\<Esc>"],
]

def Clipboard(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['text', keys(external_texts)->sort()],
            ['sequence', keys(FocusSequences('', ''))->sort()],
            ['target', ['clipboard', 'primary', 'both']],
            ['clipboard', focus_clipboards],
            ['seed', ['full', 'empty']],
    ])
        var sequences = FocusSequences(external_texts[combo.text], combo.target)
        add(cases, Case('clipboard', [combo.sequence, combo.text, combo.target, combo.clipboard, combo.seed], {
            seed: combo.seed,
            settings: {clipboard: combo.clipboard},
            steps: sequences[combo.sequence] + ['p'],
        }))
    endfor
    for combo in Product([
            ['sequence', keys(FixedSequences('', fx.seeds.full, ''))->sort()],
            ['target', ['clipboard', 'primary', 'both']],
            ['clipboard', focus_clipboards],
            ['seed', ['full', 'empty']],
    ])
        # The head of the empty seed is empty, which the cleared selection covers
        if combo.sequence == 'same_as_head' && combo.seed == 'empty'
            continue
        endif
        var sequences = FixedSequences(combo.target, fx.seeds[combo.seed], combo.clipboard)
        add(cases, Case('clipboard', [combo.sequence, combo.target, combo.clipboard, combo.seed], {
            seed: combo.seed,
            settings: {clipboard: combo.clipboard},
            steps: sequences[combo.sequence] + ['p'],
        }))
    endfor
    for combo in Product([
            ['clipboard', focus_clipboards],
            ['seed', ['full', 'empty']],
    ])
        add(cases, Case('clipboard', ['nochange', combo.clipboard, combo.seed], {
            seed: combo.seed,
            settings: {clipboard: combo.clipboard},
            steps: [Focus('lost'), Focus('gained'), 'p'],
        }))
        add(cases, Case('clipboard', ['unnamed_write', combo.clipboard, combo.seed], {
            seed: combo.seed,
            settings: {clipboard: combo.clipboard},
            steps: [":let @\" = 'foreign'\<CR>", Focus('lost'), Focus('gained'), 'p'],
        }))
    endfor
    for combo in Product([
            ['op', readback_ops],
            ['clipboard', clipboards],
            ['seed', ['full', 'empty']],
    ])
        var parts = ['readback'] + mapnew(Steps(combo.op), (_, s) => StepText(s)) + [combo.clipboard, combo.seed]
        add(cases, Case('clipboard', parts, {
            seed: combo.seed,
            settings: {clipboard: combo.clipboard},
            steps: combo.op,
            readback: true,
        }))
    endfor
    for combo in Product([
            ['clipboard', clipboard_registers],
            ['seed', split_seeds],
    ])
        add(cases, Case('clipboard', ['startup', combo.clipboard, combo.seed], {
            seed: combo.seed,
            settings: {clipboard: combo.clipboard},
            steps: ['p'],
            readback: true,
        }))
    endfor
    return cases
enddef


# Runs of operations against every history length: rotation past the
# length, duplicates, and the commands that yank nothing.
const history_patterns: dict<string> = {
    yank_lines: 'yyj',
    yank_same: 'yy',
    yank_alternate: 'yyjyyk',
    delete_lines: 'dd',
    delete_chars: 'x',
    delete_words: 'dw',
}

const history_sequences: list<list<any>> = [
    ['dd', 'u'], ['dd', 'u', "\<C-R>"], ['yy', 'jdd', 'u', 'p'], ['dw', '.'], ['x', '.'],
    ['yy', 'j.'], ['yy', 'jdd', 'u', 'u'], ['yiw', 'wdiw', 'u', "\<C-R>", 'p'],
    ['yy', 'jx', 'x', 'U', 'p'], ['yy', 'jdd', 'g-', 'g+', 'p'], ['dd', 'g-', 'p'], ['yy', 'jdd', 'u', 'g+', 'p'],
    ['qayyjq', '@a', '@@'], ['qadwq', 'j@a', 'p'], ['qayyq', 'j2@a', 'p'], ["qacwNEW\<Esc>q", 'j@a', 'p'],
    ['qaVjyq', 'G@a', 'p'], [":yank\<CR>", 'j@:', 'p'], ['qayyq', ":normal @a\<CR>", 'p'],
    ['yiw', "\<C-V>ey", 'p'], ['yy', '0v$y', 'p'], ['yiw', 'viwy', 'p'],
]

def History(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['pattern', keys(history_patterns)->sort()],
            ['repeat', [1, 2, 5, 11, 16]],
            ['put', ['p', '"9p']],
            ['length', lengths],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var parts = [combo.pattern, string(combo.repeat)] + (combo.put == 'p' ? [] : [combo.put]) + [string(combo.length), combo.fixture]
        add(cases, Case('history', parts, {
            fixture: combo.fixture,
            length: combo.length,
            steps: repeat([history_patterns[combo.pattern]], combo.repeat) + [combo.put],
        }))
    endfor
    for combo in Product([
            ['sequence', history_sequences],
            ['length', lengths],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var parts = mapnew(Steps(combo.sequence), (_, s) => StepText(s)) + [string(combo.length), combo.fixture]
        add(cases, Case('history', parts, {
            fixture: combo.fixture,
            length: combo.length,
            steps: combo.sequence,
        }))
    endfor
    return cases
enddef


# Operations that cross mode boundaries: Visual kind switches, Select and
# Visual hand-overs, Insert and Replace excursions, Ex commands from Visual
# mode and puts split from their selections.
const mode_sequences: list<list<any>> = [
    ['vjVy'], ['Vjvd'], ["vj\<C-V>y"], ["\<C-V>jlvd"], ["\<C-V>jlVcNEW\<Esc>"],
    ['vjoy'], ['vjOd'], ["\<C-V>jlOy"], ["\<C-V>jlox"],
    ["ve\<Esc>gvy"], ["vj\<Esc>0gvd"], ["ve\<Esc>jgvx"],
    ["ve\<C-G>\<C-O>\<C-G>X\<Esc>"], ["ve\<C-G>\<Esc>yw"], ["ve\<C-G>\<Esc>x"],
    ['vjvyw'], ["Vj\<Esc>dd"], ["\<C-V>jl\<Esc>x"],
    ["ihello\<Esc>yw"], ["ihello\<C-O>dw"], ["i\<C-\>\<C-O>yw"], ["i\<C-O>vjy"], ["i\<C-O>Vd"], ["i\<C-O>vecNEW\<Esc>"],
    ["i\<C-O>yy"], ["i\<C-O>x"], ["A\<C-O>D"], ["I\<C-O>Y"], ["a\<C-O>sNEW\<Esc>"], ["o\<C-O>SNEW\<Esc>"],
    ["R\<C-O>x"], ["Rab\<C-O>yw"], ["gR\<C-O>dw"], ["gRab\<C-O>x"],
    ["vj:'<,'>yank\<CR>"], ["Vj:delete\<CR>"], ["Vj:normal d\<CR>"], ["Vj:normal y\<CR>"],
    ['yvj'], ['yVw'], ["y\<C-V>j"], ['dvj'], ['yv$'], ["cviwNEW\<Esc>"],
    ['vey', 'dw'], ['ved', 've', Put('p')], ['yy', 'Vj', Put('p')], ["ve\<C-G>X\<Esc>", 'dd'],
    ['V', 'j', Put('p')], ['v', 'e', 'y'], ['yiw', 'viw', Put('p'), 'gv', Put('p')],
    ['yy', 'jV', Put('p'), 'u', 'jV', Put('p')], ['yiw', "i\<C-R>0\<Esc>", 'yy'],
]

def Modes(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['sequence', mode_sequences],
            ['fixture', ['ascii', 'multibyte', 'single']],
    ])
        var parts = mapnew(Steps(combo.sequence), (_, s) => StepText(s)) + [combo.fixture]
        add(cases, Case('modes', parts, {fixture: combo.fixture, steps: combo.sequence}))
    endfor
    return cases
enddef


# Ex commands that yank, delete or put, followed by a put
const ex_commands: list<string> = [
    ":yank\<CR>", ":2yank a\<CR>", ":1,3yank\<CR>", ":yank +\<CR>", ":yank *\<CR>", ":yank 0\<CR>",
    ":yank 1\<CR>", ":yank _\<CR>", ":yank A\<CR>", "Vj:yank\<CR>",
    ":delete\<CR>", ":2delete\<CR>", ":%delete\<CR>", ":delete a\<CR>", ":delete _\<CR>", ":delete 1\<CR>",
    "Vj:delete\<CR>", ":2,3change\<CR>new\<CR>.\<CR>",
    ":g/line/yank\<CR>", ":g/line/yank A\<CR>", ":g/./delete\<CR>", ":g/paragraph/delete a\<CR>",
    ":normal yy\<CR>", ":normal! dd\<CR>", ":normal 2yy\<CR>", ":execute 'normal dd'\<CR>",
    ":3,4normal yy\<CR>", ":normal vey\<CR>", ":normal ved\<CR>", ":normal cwNEW\<CR>",
    ":put\<CR>", ":put a\<CR>", ":2put 0\<CR>", ":put! +\<CR>", ":1,2join\<CR>", ":move 0\<CR>", ":t.\<CR>",
]

def Ex(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['command', ex_commands],
            ['fixture', ['ascii', 'multibyte']],
    ])
        add(cases, Case('ex', [combo.command, combo.fixture], {
            fixture: combo.fixture,
            steps: [combo.command, 'p'],
        }))
    endfor
    return cases
enddef


# Operations that touch no register, between a yank and a put that must
# still put the yanked text: case and shift changes, replacements, number
# increments, joins without a register, substitution, Replace mode, Insert
# mode deletions and a repeated insert.
const silent_ops: list<list<any>> = [
    ['g~~'], ['gUU'], ['guu'], ['g~iw'], ['~'], ['rX'], ['3rX'], ['g??'], ["\<C-A>"], ["\<C-X>"], ["5\<C-A>"],
    ['gJ'], ['>>'], ['<<'], ['=='], ["RXYZ\<Esc>"], ["gRXY\<Esc>"], [":s/e/E/g\<CR>"], [":%s/a/A/g\<CR>"],
    ["ihello world\<C-W>\<Esc>"], ["Ahello\<C-U>\<Esc>"], ["ihello\<BS>\<BS>\<Esc>"], ["A!\<Esc>", 'j.'],
]

def Silent(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['op', silent_ops],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var steps = ['yy'] + combo.op + ['p']
        var parts = mapnew(Steps(combo.op), (_, s) => StepText(s)) + [combo.fixture]
        add(cases, Case('silent', parts, {fixture: combo.fixture, steps: steps}))
    endfor
    return cases
enddef


# Mouse gestures as button events with the screen row and column, through
# test_setmouse() in terminal Vim and test_gui_event() in gVim.  A left
# press, drags and a release select text; a second and third press of the
# same spot select a word and a line; a right press extends a selection; a
# middle press puts the clipboard register.  The keys that follow operate on
# the selection the gesture made.
const gestures: dict<list<list<any>>> = {
    drag: [['left', 1, 5], ['drag', 1, 9], ['drag', 1, 13], ['release', 1, 13]],
    drag_lines: [['left', 1, 5], ['drag', 2, 3], ['release', 2, 3]],
    double: [['left', 1, 6], ['release', 1, 6], ['left2', 1, 6], ['release', 1, 6]],
    triple: [['left', 2, 4], ['release', 2, 4], ['left2', 2, 4], ['release', 2, 4], ['left3', 2, 4], ['release', 2, 4]],
    extend: [['left', 1, 5], ['drag', 1, 9], ['release', 1, 9], ['right', 2, 6], ['release', 2, 6]],
}

const middle_click: list<list<any>> = [['middle', 2, 3], ['release', 2, 3]]

const gesture_followups: list<list<any>> = [
    ["\<Esc>"], ['y'], ['d'], ["cNEW\<Esc>"], [Put('p')], ["\<Esc>", 'p'], ['y', 'p'],
]

# With the mouse disabled for the mode, gVim turns the same gestures into a
# modeless selection, which the 'guioptions' flag A makes Vim copy into the
# star register on the release without a TextYankPost event; without the
# flag the selection is only highlighted.  A middle click inserts the star
# register into the buffer.  The 'clipboard' values vary what else the star
# register serves.
const modeless_settings: dict<dict<any>> = {
    plain: {mouse: '', guioptions: default_guioptions, clipboard: ''},
    autoselect: {mouse: '', guioptions: 'A' .. default_guioptions, clipboard: ''},
    unnamed: {mouse: '', guioptions: default_guioptions, clipboard: 'unnamed'},
    unnamed_autoselect: {mouse: '', guioptions: 'A' .. default_guioptions, clipboard: 'unnamed'},
}

# Operations that write a register, as the bypass writes are followed by
const modeless_followups: list<list<any>> = [
    ['yy'], ['dd'], ['yiw', 'p'], ["ciwNEW\<Esc>"],
]

def MouseCases(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['gesture', keys(gestures)->sort()],
            ['followup', gesture_followups],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var steps = ['yy', Gesture(gestures[combo.gesture])] + combo.followup
        var parts = [combo.gesture] + mapnew(Steps(combo.followup), (_, s) => StepText(s)) + [combo.fixture]
        add(cases, Case('mouse', parts, {
            fixture: combo.fixture,
            settings: {mouse: 'a', mousemodel: 'extend'},
            steps: steps,
        }))
    endfor
    for combo in Product([
            ['builder', ['yy', 'yiw', 'dd', '"ayy']],
            ['fixture', ['ascii', 'multibyte']],
    ])
        add(cases, Case('mouse', ['middle', combo.builder, combo.fixture], {
            fixture: combo.fixture,
            settings: {mouse: 'a', mousemodel: 'extend'},
            steps: [combo.builder, Gesture(middle_click)],
        }))
    endfor
    for combo in Product([
            ['gesture', ['drag', 'double']],
            ['key', ["X\<Esc>", "\<BS>", "\<CR>"]],
            ['fixture', ['ascii', 'multibyte']],
    ])
        add(cases, Case('mouse', ['select', combo.gesture, combo.key, combo.fixture], {
            fixture: combo.fixture,
            settings: {mouse: 'a', mousemodel: 'extend', selectmode: 'mouse'},
            steps: ['yy', Gesture(gestures[combo.gesture]), combo.key],
        }))
    endfor
    for combo in Product([
            ['variant', keys(modeless_settings)->sort()],
            ['gesture', keys(gestures)->sort()],
            ['followup', modeless_followups],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var parts = ['modeless', combo.variant, combo.gesture]
            + mapnew(Steps(combo.followup), (_, s) => StepText(s)) + [combo.fixture]
        add(cases, Case('mouse', parts, {
            fixture: combo.fixture,
            settings: modeless_settings[combo.variant],
            steps: ['yy', Gesture(gestures[combo.gesture])] + combo.followup,
        }))
    endfor
    for combo in Product([
            ['variant', keys(modeless_settings)->sort()],
            ['builder', ['yy', 'yiw', 'dd', '"ayy']],
            ['fixture', ['ascii', 'multibyte']],
    ])
        add(cases, Case('mouse', ['modeless', combo.variant, 'middle', combo.builder, combo.fixture], {
            fixture: combo.fixture,
            settings: modeless_settings[combo.variant],
            steps: [combo.builder, Gesture(middle_click)],
        }))
    endfor
    return cases
enddef


export def Cases(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    if ctx.config_name == 'nosync'
        # The clipboard sync setting only shows in the focus events, so the
        # cases without one would repeat the default configuration
        return Clipboard(ctx)->filter((_, c) => indexof(c.steps, (_, s) => has_key(s, 'focus')) >= 0)
    endif
    extend(cases, Yank(ctx))
    extend(cases, Motions(ctx))
    extend(cases, Marks(ctx))
    extend(cases, Operators(ctx))
    extend(cases, Select(ctx))
    extend(cases, PutCases(ctx))
    extend(cases, Registers(ctx))
    extend(cases, Settings(ctx))
    extend(cases, Clipboard(ctx))
    extend(cases, History(ctx))
    extend(cases, Modes(ctx))
    extend(cases, Ex(ctx))
    extend(cases, Silent(ctx))
    extend(cases, MouseCases(ctx))
    return cases
enddef
