vim9script
# Print the table from
# https://github.com/Coacher/vim9-buckler/wiki/Vim-'clipboard'-options-behavior
# measured in this Vim. Overwrites the clipboard. Run from a terminal:
#
#   vim --clean -n -es -S tools/vim-clipboard-registers.vim

const registers = ['0', '1', '"', '*', '+']

def Yank()
    feedkeys('gg0yy', 'xt')
enddef

# Undo the change, so that every action finds the same text.
def Delete()
    feedkeys('gg0ddu', 'xt')
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

setline(1, 'alpha beta gamma')

var results = [['set clipboard=', 'Yank changes', 'Delete changes', 'Visual paste changes', 'Visual mode selection changes', 'Select mode selection changes']]
for clipboard in ['autoselect', 'autoselectplus', 'unnamed', 'unnamedplus', 'unnamedplus,unnamed', '']
    &clipboard = clipboard
    add(results, [
        clipboard,
        Changed(Yank),
        Changed(Delete),
        Changed(VisualPaste),
        Changed(VisualSelection),
        Changed(SelectModeSelection),
    ])
endfor
writefile(Table(results), '/dev/stdout')
quitall!
