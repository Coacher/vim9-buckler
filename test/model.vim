vim9script

# The specification of the yank history, as a model that writes registers.
#
# The harness drives this model through the vanilla run of every case: the
# model watches the TextYankPost events Vim produces, keeps the history the
# plugin is expected to keep and rewrites the registers after every step.
# The plugin run must end in the same state.  Nothing here reads the plugin.
#
# Items are {value, type} pairs as getreg() and getregtype() return them.

export var history: list<dict<string>> = []

var length = 10
var sync = true
var registers: list<string> = []
# Set once the system clipboard changed outside Vim, cleared when the plugin
# is expected to have rewritten the clipboard registers again
var dirty = false
var put_step = false
var events = 0
# Set when the step makes the plugin write the registers the history
# dictates: on every event, after a clipboard change found on FocusGained
# and before a Visual put; other steps leave the registers as Vim left them
var rewrite_registers = false

const null_item = {value: null_string, type: null_string}

# The registers 'clipboard' makes Vim use for the unnamed register, the
# first one is the one the clipboard sync watches
export def ClipboardRegisters(): list<string>
    var result: list<string> = []
    if has('clipboard')
        var names = split(&clipboard, ',')
        if index(names, 'unnamedplus') >= 0
            add(result, '+')
        endif
        if index(names, 'unnamed') >= 0
            add(result, '*')
        endif
    endif
    return result
enddef

def Item(register: string): dict<string>
    return {value: getreg(register), type: getregtype(register)}
enddef

def Head(): dict<string>
    return get(history, 0, null_item)
enddef

# Empty registers compare equal whatever type Vim reports for them
def Same(a: dict<string>, b: dict<string>): bool
    return (empty(a.value) && empty(b.value)) || a == b
enddef

export def Push(item: dict<string>)
    if !empty(item.value) && Head() != item
        insert(history, item)
        history = history[: length - 1]
    endif
enddef

export def Reset(history_length: number, sync_clipboard: bool)
    history = []
    length = history_length
    sync = sync_clipboard
    registers = ClipboardRegisters()
    dirty = false
enddef

# The history the plugin builds from the registers it finds when it loads
export def Startup()
    for idx in range(min([length, 10]) - 1, 0, -1)
        Push(Item(string(idx)))
    endfor
    if !empty(registers)
        Push(Item(registers[0]))
    endif
enddef

export def OnTextYankPost()
    events += 1
    rewrite_registers = true
    # Text replaced by a Visual put is not a yank, and neither is the
    # selection Vim copies into an autoselect register while the put ends it
    if put_step
        return
    endif
    var register = v:event.regname
    if register == '' || register == '"' || index(registers, register) >= 0
        Push({value: getreg(register), type: v:event.regtype})
    elseif register =~ '^\d$'
        var idx = str2nr(register)
        if idx < len(history)
            history[idx] = {value: getreg(register), type: v:event.regtype}
        elseif idx == 0
            Push({value: getreg(register), type: v:event.regtype})
        endif
        # A yank beyond the history is refused: the plugin drops the text
        # and reports it with a message, which :silent! keeps out of the
        # message history, so the startup check is where the message shows
    endif
enddef

export def BeginStep(step: dict<any>)
    put_step = get(step, 'put', false)
    events = 0
    rewrite_registers = put_step
    # An autoselect register offers the selection itself to the put key, so
    # the plugin writes the head into the clipboard registers before a put
    # from the unnamed or a clipboard register
    if put_step
        var register = matchstr(step.keys, '^"\zs.')
        if register == '' || index(registers, register) >= 0
            WriteClipboard()
            dirty = false
        endif
    endif
enddef

export def EndStep(step: dict<any>)
    if has_key(step, 'external')
        dirty = true
    endif
    # A watched register that differs from the head makes the plugin push
    # and rewrite the registers; one equal to the head leaves everything,
    # including the other clipboard register, as it is
    if get(step, 'focus', '') == 'gained' && sync && !empty(registers)
        var item = Item(registers[0])
        if !Same(item, Head())
            Push(item)
            dirty = false
            rewrite_registers = true
        endif
    endif
    if events > 0
        dirty = false
    endif
    if rewrite_registers
        Sync()
    endif
enddef

# Writes the registers the history dictates: the numbered registers hold the
# first ten items, the unnamed register points to "0 and the clipboard
# registers hold the head, unless the system clipboard holds text the plugin
# has not seen yet
export def Sync()
    for idx in range(10)
        var item = get(history, idx, null_item)
        setreg(string(idx), item.value, item.type)
    endfor
    setreg('"', {points_to: '0'})
    if !dirty
        WriteClipboard()
    endif
enddef

def WriteClipboard()
    var head = Head()
    for register in registers
        setreg(register, head.value, head.type)
    endfor
enddef
