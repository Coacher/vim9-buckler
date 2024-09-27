vim9script

import autoload './clipboard.vim'
import autoload './history.vim'
import autoload './registers.vim'

var contents: dict<string>

export def ProcessFocusLost()
    contents = registers.GetReg(clipboard.register)
enddef

export def ProcessFocusGained()
    var item = registers.GetReg(clipboard.register)
    if item != contents
        history.Push(item)
        registers.SyncNumberedWithHistory()
        registers.SyncClipboardWithZero()
    endif
enddef
