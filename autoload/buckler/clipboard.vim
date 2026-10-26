vim9script

export var registers: list<string> = []

const has_clipboard = has('clipboard')

export def StoreClipboardName()
    # Store the configured clipboard register names
    if has_clipboard
        var names = split(&clipboard, ',')
        if index(names, 'unnamedplus') >= 0
            add(registers, '+')
        endif
        if index(names, 'unnamed') >= 0
            add(registers, '*')
        endif
    endif
enddef

export def Primary(): string
    # Get the primary clipboard register name
    return get(registers, 0, '')
enddef

export def IsClipboardRegister(name: string): bool
    # Check if the given name is the clipboard or the unnamed register name
    return (index(registers, name) >= 0) || (name == '') || (name == '"')
enddef
