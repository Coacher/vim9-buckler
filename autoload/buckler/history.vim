vim9script

export var history: list<dict<string>>

export def Count(): number
    # Count the number of items in the yank history
    return len(history)
enddef

export def Get(idx: number = 0): dict<string>
    # Get an item from the yank history by index
    return history[idx]
enddef

export def Set(idx: number, item: dict<string>)
    # Set an item in the yank history by index
    history[idx] = item
enddef

export def Push(item: dict<string>)
    # Push an item to the yank history maintaining its length
    if !empty(item.value) && ((Count() == 0) || (Get() != item))
        insert(history, item)
        if Count() > g:vim9buckler_history_length
            remove(history, -1)
        endif
    endif
enddef
