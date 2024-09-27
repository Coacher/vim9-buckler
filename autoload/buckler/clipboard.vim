vim9script

export var register: string

export def SaveClipboardName()
    # Save the configured clipboard register name
    var names = split(&clipboard, ',')
    if index(names, 'unnamedplus') >= 0
        register = '+'
    elseif index(names, 'unnamed') >= 0
        register = '*'
    else
        register = ''
    endif
enddef
