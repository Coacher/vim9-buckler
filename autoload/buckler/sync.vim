vim9script

import autoload './clipboard.vim'
import autoload './history.vim'
import autoload './registers.vim'

var contents: dict<string>

export def ProcessFocusLost()
    contents = registers.GetReg(clipboard.Primary())
enddef

export def ProcessFocusGained()
    var item = registers.GetReg(clipboard.Primary())
    if item != contents
        history.Push(item)
        registers.SetNumberedFromHistory()
        registers.SetClipboardFromZero()
    endif
enddef
