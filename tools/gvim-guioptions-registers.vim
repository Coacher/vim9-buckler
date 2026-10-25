vim9script
# Print the table from
# https://github.com/Coacher/vim9-buckler/wiki/gVim-'guioptions'-options-behavior
# measured in this gVim. Overwrites the clipboard. Run from a terminal:
#
#   gvim -f --clean -n -S tools/gvim-guioptions-registers.vim

const registers = ['0', '1', '"', '*', '+']

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

# Return the registers that Action() changes.
def Changed(Action: func): string
    for name in registers
        setreg(name, 'old')
    endfor
    Action()
    var changed = []
    for name in registers
        if getreg(name) != 'old'
            add(changed, name == '"' ? 'unnamed' : name)
        endif
    endfor
    return join(changed, ', ')
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

var results = [['set guioptions=', 'Visual mode selection changes', 'Select mode selection changes', 'Modeless selection changes']]
for guioptions in ['a', 'A', 'P', 'aA', 'aP', 'AP', 'aAP', '']
    &guioptions = guioptions
    add(results, [
        guioptions,
        Changed(VisualSelection),
        Changed(SelectModeSelection),
        Changed(ModelessSelection),
    ])
endfor
writefile(Table(results), '/dev/stdout')
quitall!
