vim9script
# Print the tables from
# https://github.com/Coacher/vim9-buckler/wiki/gVim-TextYankPost-triggers
# measured in this gVim. Overwrites the clipboard. Run from a terminal:
#
#   gvim -f --clean -n -S tools/gvim-textyankpost-events.vim

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

def VisualSelection()
    feedkeys("gg0ve\<Esc>", 'xt')
enddef

def SelectModeSelection()
    feedkeys("gg0gh\<End>\<Esc>", 'xt')
enddef

# Double-click the first word. An empty 'mouse' makes the selection
# modeless, and modeless selection copies the screen, so draw it first.
def ModelessSelection()
    redraw
    for multiclick in [0, 1]
        test_gui_event('mouse', {button: 0, row: 1, col: 1, multiclick: multiclick, modifiers: 0})
        test_gui_event('mouse', {button: 3, row: 1, col: 1, multiclick: 0, modifiers: 0})
    endfor
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

set clipboard= mouse=
setline(1, 'alpha beta gamma')

var page = []
for [name, Action] in [['Visual mode selection', VisualSelection], ['Select mode selection', SelectModeSelection], ['Modeless selection', ModelessSelection]]
    var results = [['set guioptions='] + fields]
    for guioptions in ['a', 'A', 'P', 'aA', 'aP', 'AP', 'aAP', '']
        &guioptions = guioptions
        for event in Triggered(Action)
            add(results, [guioptions] + event)
        endfor
    endfor
    page += ['## ' .. name, ''] + Table(results) + ['']
endfor
writefile(page, '/dev/stdout')
quitall!
