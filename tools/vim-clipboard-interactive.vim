vim9script
# Fill the buffer with the table from
# https://github.com/Coacher/vim9-buckler/wiki/Vim-'clipboard'-options-behavior
# measured in this Vim interactively. Overwrites the clipboard. Run from a terminal:
#
#   vim --clean -n -S tools/vim-clipboard-interactive.vim

const registers = ['0', '1', '"', '*', '+']

# Wait until the user does the request and presses Enter.
def Ask(request: string)
    input(request .. ', then press Enter ')
enddef

# Ask for a drag over the text. With 'mouse' set to c, Vim takes the mouse
# only on the command line, so the drag while input() waits makes a modeless
# selection, and modeless selection copies the screen, so draw it first.
def ModelessSelection()
    redraw
    Ask('set clipboard=' .. &clipboard .. ': select some text above with the mouse')
enddef

def DESelection()
    Ask('select some text in another application')
enddef

def DECopy()
    Ask('copy some text in another application')
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

set mouse=c
setline(1, 'alpha beta gamma')

# Selections and copies in another application do not depend on
# 'clipboard', so ask for each once.
const de_selection = Changed(DESelection)
const de_copy = Changed(DECopy)

var results = [['set clipboard=', 'Modeless selection changes', 'DE select changes', 'DE copy changes']]
for clipboard in ['autoselect', 'autoselectplus', 'unnamed', 'unnamedplus', 'unnamedplus,unnamed', '']
    &clipboard = clipboard
    add(results, [
        clipboard,
        Changed(ModelessSelection),
        de_selection,
        de_copy,
    ])
endfor
setline(1, Table(results))
