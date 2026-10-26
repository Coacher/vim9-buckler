vim9script
# Print the tables from
# https://github.com/Coacher/vim9-buckler/wiki/Vim-registers-behavior
# measured in this Vim. Overwrites the clipboard. Run from a terminal:
#
#   vim --clean -n -es -S tools/vim-registers-behavior.vim

const registers = ['0', '1', '"', '*', '+']

def Yank(register: string)
    feedkeys('gg0' .. register .. 'yy', 'xt')
enddef

# Undo the change, so that every action finds the same text.
def Delete(register: string)
    feedkeys('gg0' .. register .. 'ddu', 'xt')
enddef

# Undo the change, so that every action finds the same text.
def VisualPaste(register: string)
    feedkeys('gg0V' .. register .. 'pu', 'xt')
enddef

# Return the registers that Action() with the register named changes, with
# the register the unnamed one points to.
def Changed(Action: func(string), register: string): string
    for name in registers
        setreg(name, 'old')
    endfor
    Action(register)
    var changed = []
    for name in registers
        if getreg(name) != 'old'
            add(changed, name == '"' ? 'unnamed -> ' .. getreginfo('"').points_to : name)
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

var page = []
for [name, Action] in [['Yank', Yank], ['Delete', Delete], ['Visual paste', VisualPaste]]
    var results = [['set clipboard=', 'no register', '""', '"*', '"+']]
    for clipboard in ['autoselect', 'autoselectplus', 'unnamed', 'unnamedplus', 'unnamedplus,unnamed', '']
        &clipboard = clipboard
        add(results, [
            clipboard,
            Changed(Action, ''),
            Changed(Action, '""'),
            Changed(Action, '"*'),
            Changed(Action, '"+'),
        ])
    endfor
    page += ['## ' .. name, ''] + Table(results) + ['']
endfor
writefile(page, '/dev/stdout')
quitall!
