vim9script

import autoload './clipboard.vim'
import autoload './history.vim'
import autoload './registers.vim'

export def ProcessFocusGained()
    var item = registers.GetReg(clipboard.Primary())
    if item != history.Get()
        history.Push(item)
        registers.SetNumberedFromHistory()
        registers.SetClipboardFromZero()
    endif
enddef
