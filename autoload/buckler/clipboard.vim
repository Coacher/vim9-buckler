vim9script

export var register: string = ''

var has_clipboard = has('clipboard')

export def StoreClipboardName()
    # Store the configured clipboard register name
    if has_clipboard
        var names = split(&clipboard, ',')
        if index(names, 'unnamedplus') >= 0
            register = '+'
        elseif index(names, 'unnamed') >= 0
            register = '*'
        else
            register = ''
        endif
    endif
enddef

export def IsClipboardRegister(name: string): bool
    # Check if the given name is the clipboard register name
    return (name == register) || (name == '')
enddef
