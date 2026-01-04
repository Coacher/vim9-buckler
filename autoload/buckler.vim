vim9script

import autoload './buckler/clipboard.vim'

augroup buckler_store_clipboard_name
autocmd!
autocmd VimEnter  *         clipboard.StoreClipboardName()
autocmd OptionSet clipboard clipboard.StoreClipboardName()
augroup END

import autoload './buckler/registers.vim'

augroup buckler_sync_history
autocmd!
autocmd VimEnter * registers.SyncHistoryWithRegisters()
augroup END

if g:vim9buckler_sync_clipboard
    import autoload './buckler/sync.vim'

    augroup buckler_sync_system_clipboard
    autocmd!
    autocmd FocusLost   * sync.ProcessFocusLost()
    autocmd FocusGained * sync.ProcessFocusGained()
    augroup END
endif

import autoload './buckler/visual.vim'

augroup buckler_process_visual
autocmd!
autocmd KeyInputPre [vV\x16]*            visual.ProcessKeyInput()
autocmd ModeChanged [vV\x16]*:[^vV\x16]* visual.ProcessModeChange()
augroup END

import autoload './buckler/yank.vim'

augroup buckler_process_yank
autocmd!
autocmd TextYankPost * yank.ProcessTextYank()
augroup END
