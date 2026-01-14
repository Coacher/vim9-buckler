vim9script

import autoload './clipboard.vim'
import autoload './history.vim'
import autoload './registers.vim'
import autoload './visual.vim'

export def ProcessTextYank()
    var register = v:event.regname
    var item = {value: getreg(register), type: v:event.regtype}

    if clipboard.IsClipboardRegister(register)
        # Clipboard register is used
        if tolower(visual.char) != 'p'
            # Real yank, push the item to the yank history
            history.Push(item)
        endif
        # Set the numbered registers from the yank history
        registers.SetNumberedFromHistory()
    elseif register =~ '\d'
        # Numbered register is used
        var idx = str2nr(register)
        if history.Count() > idx
            # Update the item in the yank history if it is present
            history.Set(idx, item)
        elseif idx == 0
            # 0 register is used and the yank history is empty,
            # push the item to the yank history
            history.Push(item)
        else
            # Other numbered register is used and it is missing from the
            # yank history, warn user about a possible data loss on yank
            echomsg '"' .. register .. ' may be cleared after next yank'
        endif
    endif
    # Set the clipboard registers from the 0 register after all yanks
    registers.SetClipboardFromZero()
enddef
