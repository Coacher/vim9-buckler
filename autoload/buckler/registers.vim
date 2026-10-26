vim9script

import autoload './clipboard.vim'
import autoload './history.vim'

export def GetReg(register: string): dict<string>
    # Get a yank history item from the given register
    return history.Item(getreg(register), getregtype(register))
enddef

export def SetReg(register: string, item: dict<string>)
    # Set the given register to the given yank history item
    setreg(register, item.value, item.type)
enddef

export def SetNumberedFromHistory()
    # Set the numbered registers from the yank history
    for idx in range(10)
        SetReg(string(idx), history.Get(idx))
    endfor
enddef

export def SetClipboardFromZero()
    # Set the unnamed and clipboard registers from the 0 register
    setreg('', {points_to: '0'})
    for register in clipboard.registers
        SetReg(register, GetReg('0'))
    endfor
enddef

export def SyncHistoryWithRegisters()
    # Push the numbered and clipboard registers to the yank history
    # Then update all the registers from the resulting yank history
    for idx in range(9, 0, -1)
        history.Push(GetReg(string(idx)))
    endfor
    if !empty(clipboard.registers)
        history.Push(GetReg(clipboard.Primary()))
    endif
    SetNumberedFromHistory()
    SetClipboardFromZero()
enddef
