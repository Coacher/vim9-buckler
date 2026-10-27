vim9script

# Buffer fixtures and register seeds shared by every matrix.
#
# A fixture is the buffer a case starts from: its lines, the cursor position
# the case uses unless it names another one, further cursor positions that
# put text objects in reach, and the marks that are set before any key is
# fed.  Register seeds give every register a distinct, recognizable value so
# that an unexpected write is visible in the diff, and shape the history the
# plugin builds from the registers when it loads.

export const fixtures: dict<dict<any>> = {
    ascii: {
        lines: [
            'one two three four five',
            '  indented (paren) "quoted" <tag>text</tag> end',
            '',
            'alpha beta gamma delta epsilon.  Second sentence here.',
            'last line of the first paragraph',
            '',
            'second paragraph line one',
            'second paragraph line two',
        ],
        cursor: [1, 5],
        cursors: [[1, 5], [2, 14], [2, 23], [2, 36], [4, 20], [8, 1]],
        marks: {a: [4, 7], b: [7, 1]},
    },
    multibyte: {
        lines: [
            'раз два три четыре пять',
            '日本語 テキスト の 行',
            'café naïve (скобки) "кавычки"',
            'mixed ascii and кириллица words',
            '',
            'tail line',
        ],
        cursor: [1, 5],
        cursors: [[1, 5], [2, 7], [3, 20], [4, 25]],
        marks: {a: [3, 7], b: [6, 1]},
    },
    indented: {
        lines: [
            "\tfirst tab line",
            "\t\tsecond tab line",
            '    four spaces',
            "\tif (cond) {",
            "\t\tbody;",
            "\t}",
            'trailing spaces   ',
            'end',
        ],
        cursor: [4, 10],
        cursors: [[4, 10], [1, 3], [5, 4], [7, 16]],
        marks: {a: [2, 3], b: [8, 1]},
    },
    sparse: {
        lines: ['a', '', '', 'bb', '', 'ccc', ''],
        cursor: [4, 1],
        cursors: [[4, 1], [2, 1], [7, 1]],
        marks: {a: [1, 1], b: [6, 2]},
    },
    single: {
        lines: ['only one line here'],
        cursor: [1, 6],
        cursors: [[1, 6], [1, 1], [1, 18]],
        marks: {a: [1, 1], b: [1, 10]},
    },
}

# Registers seeded before every execution.  The clipboard registers are
# added by the harness when the build has the clipboard feature.
export const seeded_registers: list<string> =
    ['"', '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9']
    + ['a', 'b', 'c', 'd', 'e', 'z']

# Seeds differ in how many numbered registers hold text, which registers
# hold linewise or blockwise text, what the clipboard registers hold and
# where the unnamed register points.
#   numbered    count of numbered registers holding text, from "0 up
#   holes       numbered registers within that count left empty
#   duplicates  numbered registers holding the same text as "0
#   clipboard   'distinct' text in both clipboard registers, the text of
#               'zero', '' for empty, 'split' for text of their own in each,
#               or 'staronly' for text in the star register only
export const seeds: dict<dict<any>> = {
    full: {numbered: 10, duplicates: [], clipboard: 'distinct', linewise: ['z'], blockwise: ['e'], points_to: '0'},
    partial: {numbered: 3, duplicates: [], clipboard: 'distinct', linewise: ['1', 'z'], blockwise: ['e'], points_to: '0'},
    empty: {numbered: 0, duplicates: [], clipboard: '', linewise: ['z'], blockwise: ['e'], points_to: '0'},
    dupes: {numbered: 10, duplicates: ['1', '4'], clipboard: 'zero', linewise: ['z'], blockwise: ['e'], points_to: '0'},
    types: {numbered: 10, duplicates: [], clipboard: 'distinct', linewise: ['0', '4', '*', '+', 'z'], blockwise: ['1', 'e'], points_to: '0'},
    clipzero: {numbered: 10, duplicates: [], clipboard: 'zero', linewise: ['z'], blockwise: ['e'], points_to: '0'},
    named: {numbered: 10, duplicates: [], clipboard: 'distinct', linewise: ['a', 'z'], blockwise: ['b'], points_to: 'a'},
    split: {numbered: 10, duplicates: [], clipboard: 'split', linewise: ['z'], blockwise: ['e'], points_to: '0'},
    staronly: {numbered: 10, duplicates: [], clipboard: 'staronly', linewise: ['z'], blockwise: ['e'], points_to: '0'},
    gaps: {numbered: 10, holes: ['0', '2', '5'], duplicates: [], clipboard: 'distinct', linewise: ['z'], blockwise: ['e'], points_to: '1'},
}

export def SeedText(name: string): string
    return 'seed register ' .. name
enddef

# The text a register holds under a seed, '' when it is left empty
export def SeedValue(seed: dict<any>, name: string): string
    if name =~ '^\d$'
        if index(get(seed, 'holes', []), name) >= 0
            return ''
        endif
        if index(seed.duplicates, name) >= 0
            return SeedText('0')
        endif
        return str2nr(name) < seed.numbered ? SeedText(name) : ''
    elseif name =~ '^[*+]$'
        if seed.clipboard == 'split' || (seed.clipboard == 'staronly' && name == '*')
            return SeedText(name == '*' ? 'star' : 'clipboard')
        endif
        return seed.clipboard == 'distinct' ? SeedText('clipboard')
            : seed.clipboard == 'zero' ? SeedValue(seed, '0') : ''
    endif
    return SeedText(name)
enddef
