vim9script

import autoload './clipboard.vim'
import autoload './registers.vim'

export var char: string

export def ProcessKeyInput()
    char = v:char

    # 'clipboard' and 'guioptions' can be set to both use the same register.
    # In this case, when pasting over a visually selected text, the selected
    # text is first yanked to the 'guioptions' register, then the 'clipboard'
    # register is pasted. Thus, no visible change is made to the selected text.
    # In gVim TextYankPost autocmd is processed too late to prevent this issue.
    # TextYankPost event is triggered only for 'p', see 'help put-Visual-mode'.
    # Set clipboard registers from the 0 register before paste to prevent this
    if (tolower(char) == 'p') && clipboard.IsClipboardRegister(v:register)
        registers.SetClipboardFromZero()
    endif
enddef

export def ProcessModeChange()
    char = null_string
enddef
