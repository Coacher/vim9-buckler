vim9script

# Checks the plugin after Vim's own startup loaded it as a package.
#
# run.sh runs this script with -S from a home directory whose vimrc sets
# 'clipboard' and the history length, so the checks wait for VimEnter: the
# plugin must be marked loaded with its autocommands in place, the vimrc
# settings must be in effect, two yanks must shift the numbered registers,
# a yank beyond the history must be refused with a message and with the
# registers kept as the history dictates, and no error may have been
# reported.  The keys run without :silent!, so the message the plugin gives
# reaches the message history as it does for a user.  Failures are written
# to the results directory and make Vim exit with a failure status.

def Check()
    var failures: list<string> = []
    if !exists('g:vim9buckler_loaded')
        add(failures, 'plugin not marked loaded')
    endif
    if !exists('#buckler_process_yank#TextYankPost')
        add(failures, 'TextYankPost autocommand missing')
    endif
    if g:vim9buckler_history_length != 12
        add(failures, 'history length from the vimrc not kept: ' .. g:vim9buckler_history_length)
    endif
    setline(1, ['first line', 'second line'])
    normal! yy
    normal! jyy
    if getreg('0') != "second line\n" || getreg('1') != "first line\n"
        add(failures, printf('registers after two yanks: "0 = %s, "1 = %s', string(getreg('0')), string(getreg('1'))))
    endif
    if has('clipboard') && getreg('*') != "second line\n"
        add(failures, 'clipboard register after a yank: ' .. string(getreg('*')))
    endif
    messages clear
    normal! "9yy
    if execute('messages') !~# 'Out-of-range'
        add(failures, 'yank beyond the history not refused: ' .. string(execute('messages')))
    endif
    if !empty(getreg('9')) || !getreginfo('0').isunnamed
        add(failures, printf('registers after the refused yank: "9 = %s, "0 unnamed = %s', string(getreg('9')), getreginfo('0').isunnamed))
    endif
    if !empty(v:errmsg)
        add(failures, 'error reported: ' .. v:errmsg)
    endif
    writefile(failures, $BUCKLER_RESULTS .. '/failures.txt')
    if empty(failures)
        qall!
    endif
    cquit!
enddef

autocmd VimEnter * ++once ++nested Check()
