vim9script

import autoload './clipboard.vim'
import autoload './registers.vim'

export var char: string

export def ProcessKeyInput()
    char = v:char

    # 'clipboard' and 'guioptions' can be set to write to the same register
    # When pasting over a visually selected text, the selected text is first
    # yanked to the default register and then the default register is pasted
    # Therefore no visible change is made to the visually selected text
    # Forcibly sync the clipboard with the yank history to prevent this
    if (tolower(char) == 'p')
        if (v:register == '') || (v:register == clipboard.register)
            registers.SyncClipboardWithZero()
        endif
    endif
enddef

export def ProcessModeChange()
    char = ''
enddef
