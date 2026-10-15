vim9script

export var register: string = ''
export var registers: list<string> = []

var has_clipboard = has('clipboard')

export def StoreClipboardName()
    # Store the configured clipboard register names
    # With 'unnamed,unnamedplus' yanks go to both registers
    # but pastes read and deletes write the + register only
    if has_clipboard
        var names = split(&clipboard, ',')
        registers = []
        if index(names, 'unnamedplus') >= 0
            add(registers, '+')
        endif
        if index(names, 'unnamed') >= 0
            add(registers, '*')
        endif
        register = get(registers, 0, '')
    endif
enddef

export def IsClipboardRegister(name: string): bool
    # Check if the given name is the clipboard register name
    return (name == '') || (index(registers, name) >= 0)
enddef
