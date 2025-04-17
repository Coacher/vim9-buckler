vim9script

import autoload './buckler/clipboard.vim'

augroup buckler_save_clipboard_name
autocmd!
autocmd VimEnter * ++once clipboard.SaveClipboardName()
autocmd OptionSet clipboard clipboard.SaveClipboardName()
augroup END

import autoload './buckler/registers.vim'

augroup buckler_setup_history
autocmd!
autocmd VimEnter * ++once registers.SetupHistoryOnVimEnter()
augroup END

if g:vim9buckler_sync_clipboard
    import autoload './buckler/sync.vim'

    augroup buckler_sync_system_clipboard
    autocmd!
    autocmd FocusLost * sync.ProcessFocusLost()
    autocmd FocusGained * sync.ProcessFocusGained()
    augroup END
endif

import autoload './buckler/visual.vim'

augroup buckler_process_visual
autocmd!
autocmd ModeChanged [vV\x16]*:[^vV\x16]* visual.ProcessModeChange()
autocmd KeyInputPre [vV\x16]* visual.ProcessKeyInput()
augroup END

import autoload './buckler/yank.vim'

augroup buckler_process_yank
autocmd!
autocmd TextYankPost * yank.ProcessTextYank()
augroup END
