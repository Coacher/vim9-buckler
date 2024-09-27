vim9script

import autoload './clipboard.vim'
import autoload './history.vim'

export def GetReg(register: string): dict<string>
    # Get a yank history item from the given register
    return {value: getreg(register), type: getregtype(register)}
enddef

export def SetReg(register: string, item: dict<string>)
    # Set the given register to the given yank history item
    setreg(register, item.value, item.type)
enddef

export def SyncNumberedWithHistory()
    # Sync the numbered registers with the yank history
    for idx in range(min([history.Count(), 10]))
        SetReg(string(idx), history.Get(idx))
    endfor
enddef

export def SyncClipboardWithZero()
    # Sync the unnamed and clipboard registers with the 0 register
    setreg('', {points_to: '0'})
    if !empty(clipboard.register)
        SetReg(clipboard.register, GetReg('0'))
    endif
enddef

export def SetupHistoryOnVimEnter()
    # Push the numbered and clipboard registers to the yank history
    # Then update all the registers from the resulting yank history
    for idx in range(min([g:vim9buckler_history_length, 10]) - 1, 0, -1)
        history.Push(GetReg(string(idx)))
    endfor
    if !empty(clipboard.register)
        history.Push(GetReg(clipboard.register))
    endif
    SyncNumberedWithHistory()
    SyncClipboardWithZero()
enddef
