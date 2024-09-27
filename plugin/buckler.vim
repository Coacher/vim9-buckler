if !has('vim9script')
    echoerr 'vim9-buckler requires vim9script feature enabled'
    finish
endif

vim9script


if exists('g:vim9buckler_loaded')
    finish
endif

g:vim9buckler_loaded = 1


g:vim9buckler_history_length = get(g:, 'vim9buckler_history_length', 10)

g:vim9buckler_sync_clipboard = get(g:, 'vim9buckler_sync_clipboard', v:true)


import '../autoload/buckler.vim'
