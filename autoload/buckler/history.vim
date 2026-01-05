vim9script

export var history: list<dict<string>>

const null_entry = {value: null_string, type: null_string}

export def Count(): number
    # Count the number of items in the yank history
    return len(history)
enddef

export def Get(idx: number = 0): dict<string>
    # Get an item from the yank history by index
    return get(history, idx, null_entry)
enddef

export def Set(idx: number, item: dict<string>)
    # Set an item in the yank history by index
    history[idx] = item
enddef

export def Push(item: dict<string>)
    # Push an item to the yank history maintaining its length
    if !empty(item.value) && (Get() != item)
        insert(history, item)
        if Count() > g:vim9buckler_history_length
            remove(history, -1)
        endif
    endif
enddef
