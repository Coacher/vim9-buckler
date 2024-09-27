vim9script

export var char: string

export def ProcessKeyInput()
    char = v:char
enddef

export def ProcessModeChange()
    char = ''
enddef
