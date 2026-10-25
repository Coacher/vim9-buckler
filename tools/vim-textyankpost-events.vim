vim9script
# Print the tables from
# https://github.com/Coacher/vim9-buckler/wiki/Vim-TextYankPost-triggers
# measured in this Vim. Overwrites the clipboard. Silent Ex mode would make
# mode() report c, so Vim runs in Normal mode with the screen discarded and
# prints the tables to stderr. Vim sets a terminal on stdin, or on stderr
# when stdin is none, to raw mode, which breaks the printed lines, so give it
# neither. Run from a terminal:
#
#   vim --clean -n --not-a-term -S tools/vim-textyankpost-events.vim </dev/null 2>&1 >/dev/null | cat

const fields = ['v:operator', 'v:register', 'v:event.operator', 'v:event.regname', 'v:event.visual', 'mode()', 'visualmode()']

var events = []

def Record()
    var values = []
    for value in [v:operator, v:register, v:event.operator, v:event.regname, string(v:event.visual), mode(), visualmode()]
        add(values, empty(value) ? '(empty)' : value)
    endfor
    add(events, values)
enddef

autocmd TextYankPost * Record()

def Yank()
    feedkeys('gg0yy', 'xt')
enddef

# Undo the change, so that every action finds the same text.
def Delete()
    feedkeys('gg0ddu', 'xt')
enddef

def VisualYank()
    feedkeys('gg0Vy', 'xt')
enddef

# Undo the change, so that every action finds the same text.
def VisualDelete()
    feedkeys('gg0Vdu', 'xt')
enddef

# Undo the change, so that every action finds the same text.
def VisualPaste()
    feedkeys('gg0Vpu', 'xt')
enddef

def VisualSelection()
    feedkeys("gg0ve\<Esc>", 'xt')
enddef

def SelectModeSelection()
    feedkeys("gg0gh\<End>\<Esc>", 'xt')
enddef

# Return the fields of the TextYankPost events that Action() triggers,
# or blank fields when it triggers none.
def Triggered(Action: func): list<list<string>>
    events = []
    Action()
    return empty(events) ? [repeat([''], len(fields))] : events
enddef

# Return the lines of a Markdown table padded to the widest cells.
def Table(rows: list<list<string>>): list<string>
    var widths = repeat([0], len(rows[0]))
    for row in rows
        for column in range(len(row))
            widths[column] = max([widths[column], len(row[column])])
        endfor
    endfor
    var lines = []
    for row in rows
        var cells = []
        for column in range(len(row))
            add(cells, printf('%-*s', widths[column], row[column]))
        endfor
        add(lines, '| ' .. join(cells, ' | ') .. ' |')
    endfor
    var dashes = []
    for width in widths
        add(dashes, repeat('-', width))
    endfor
    insert(lines, '|-' .. join(dashes, '-|-') .. '-|', 1)
    return lines
enddef

setline(1, 'alpha beta gamma')

var page = []
for [name, Action] in [['Yank', Yank], ['Delete', Delete], ['Visual yank', VisualYank], ['Visual delete', VisualDelete], ['Visual paste', VisualPaste], ['Visual mode selection', VisualSelection], ['Select mode selection', SelectModeSelection]]
    var results = [['set clipboard='] + fields]
    for clipboard in ['autoselect', 'autoselectplus', 'unnamed', 'unnamedplus', 'unnamedplus,unnamed', '']
        &clipboard = clipboard
        for event in Triggered(Action)
            add(results, [clipboard] + event)
        endfor
    endfor
    page += ['## ' .. name, ''] + Table(results) + ['']
endfor
writefile(page, '/dev/stderr')
quitall!
