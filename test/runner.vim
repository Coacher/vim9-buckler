" Entry point of a test process, kept in legacy script on purpose.
"
" Keys are fed from here so that command lines typed during a case are
" parsed with the rules a user gets at the keyboard, not with the Vim9
" rules of the script that called feedkeys().  Vim restores the redo buffer
" when a function returns, so the steps of one case are fed from a single
" call, which lets "." repeat the previous step and isolates the cases
" from each other.

if !has('vim9script') || !has('patch-9.1.563')
    " The plugin itself refuses such builds; run.sh checks them separately.
    cquit!
endif

function BucklerFeed(keys) abort
    silent! call feedkeys(a:keys, 'xt')
endfunction

" Runs the steps of a case; the harness performs the steps that are no keys
" and the bookkeeping around every step.
function BucklerRunSteps(steps) abort
    for step in a:steps
        call g:BucklerBeginStep(step)
        if has_key(step, 'keys')
            silent! call feedkeys(step.keys, 'xt')
        else
            call g:BucklerRunStep(step)
        endif
        call g:BucklerEndStep(step)
    endfor
endfunction

execute 'source' fnameescape(expand('<sfile>:p:h') .. '/harness.vim')
