vim9script

import autoload './clipboard.vim'
import autoload './history.vim'
import autoload './registers.vim'
import autoload './visual.vim'

export def ProcessTextYank()
    var operator = v:event.operator

    if (operator == 'y') || ((operator == 'd') && (tolower(visual.char) != 'p'))
        var register = v:event.regname
        var item = {value: getreg(register), type: v:event.regtype}

        if clipboard.IsClipboardRegister(register)
            # The default register was used, push an item to the yank history
            # Sync the numbered and clipboard registers with the yank history
            history.Push(item)
            registers.SetNumberedFromHistory()
            registers.SetClipboardFromZero()
        elseif register =~ '\d'
            # Numbered register was used, update the item in the yank history
            var idx = str2nr(register)
            if history.Count() > idx
                history.Set(idx, item)
            endif
            if idx == 0
                # The 0 register was explicitly used
                if history.Count() == 0
                    history.Push(item)
                endif
                registers.SetClipboardFromZero()
            endif
        else
            registers.SetClipboardFromZero()
        endif
    else
        registers.SetNumberedFromHistory()
        registers.SetClipboardFromZero()
    endif
enddef
