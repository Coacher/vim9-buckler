Test suite
==========

The suite checks that vim9-buckler keeps a linear yank history and mirrors
it into the numbered, unnamed and clipboard registers, in terminal Vim and
in gVim, with and without a display server, and that the system clipboard
follows along.

Design
------

Every case is a list of steps a user performs: keys typed, a focus event,
or text copied by another application. The harness runs every case twice in
one Vim process: first without the plugin, then with it. Both runs start
from the same buffer, cursor, marks, settings and register seeds, and the
harness compares the buffer, cursor, mode, marks, search pattern, every
register and, where a case asks for it, the system clipboard afterwards.

The expected outcome is defined by the specification, never by hand. The
specification is `model.vim`: a history model that watches the TextYankPost
events Vim produces during the run without the plugin and, after every
step, writes the registers the history dictates. Vim then performs the next
step against those registers, so the buffer of the run without the plugin
shows what a user must see when the plugin does its job, and the registers
show what the plugin must leave behind. A step holds at most one operation
that writes or reads registers, which is why a Visual put is two steps, the
selection and the put key. The steps of a case are fed from one legacy
function call: typed command lines then follow the rules a user gets at the
keyboard, and the redo buffer, which Vim restores when a function returns,
carries from one step to the next and no further, so `.` repeats the
previous step and no case sees the changes of another.

The model is the whole specification, in short:

* Items are the register value and type. A yank, delete or change into the
  unnamed register or into a register named by `'clipboard'` pushes an
  item, unless it equals the head; the history keeps at most
  `g:vim9buckler_history_length` items. A yank into numbered register n
  replaces item n when it exists; `"0` with an empty history pushes; a
  yank into a numbered register beyond the history is refused with a
  message, and the register keeps holding what the history dictates.
  Other registers leave the history alone.
* Text that a Visual put replaces is no item, for any register and for
  `p`, `P`, `gp`, `gP`, counts and `:normal`. Vim does not repeat a Visual
  put: `.` after one deletes an area of the same size and puts nothing, so
  the text it deletes after `p` is an item like any other delete. Before a
  put from the unnamed or a `'clipboard'` register over a selection the
  `'clipboard'` registers are set to the head, so the put inserts the head
  and not the selection an autoselect register offers.
* A selection Vim copies into an autoselect register, `*` under
  `'clipboard'` `autoselect` or `'guioptions'` `a` and `+` under
  `autoselectplus` or `P`, is a yank into that register when Vim reports
  it with TextYankPost, which it does when a key or the mouse ends the
  selection: an item when the register is one `'clipboard'` names. An
  operator ending the selection reports its own yank or delete, if any,
  and the copy stays unreported: the history and the other registers stay
  as they are, and the register keeps the selection.
* After every yank, delete, change or put `"0` to `"9` hold the first ten
  items, `""` points to `"0`, and the `'clipboard'` registers hold the
  head. Other operations leave every register as Vim left it.
* When the plugin loads, `"0` up to the history length, oldest first, and
  then the primary clipboard register are pushed, and the registers are
  rewritten.
* On FocusGained with `g:vim9buckler_sync_clipboard` the primary clipboard
  register, `+` when `'clipboard'` has `unnamedplus` and `*` when it has
  `unnamed`, is read; non-empty text different from the head is pushed. A
  cleared or unchanged clipboard pushes nothing, and an unchanged one
  leaves every register alone. Without a clipboard register nothing is
  read and nothing changes. Until the plugin has seen a change made
  outside Vim, the clipboard registers are left as that application set
  them.

Register writes that bypass TextYankPost, such as macro recording,
`setreg()` or a modeless selection, are not items: the suite expects the
next yank or delete to overwrite them. The report shows the field by field
difference between the specified and the actual state.

Matrices
--------

`matrices.vim` generates the cases as products of axes. Nothing is listed
case by case: a new motion, setting, seed or fixture becomes a new axis
value.

* `yank`: linewise, Visual and Insert CTRL-O yanks with counts and every
  register prefix, including `Y` from every Visual kind.
* `motions`, `marks`: every motion, text object and mark as the target of
  `y`, `d` and `c`, from every cursor position of every fixture.
* `delete`, `change`: every change and delete key in Normal, Visual, Insert
  CTRL-O and Replace CTRL-O modes, with counts before the operator and
  the motion, and with every register prefix.
* `select`: typing over a Select mode selection entered through every
  entry Vim offers, with the register CTRL-R names for the deleted text,
  and the Visual commands run from the selection through CTRL-O and
  CTRL-G, puts among them.
* `put`: Visual puts after every kind of history item, with every put key,
  the indent adjusting ones among them, and every register prefix with
  and without a count, followed by a second put, a repeat, a put through
  `:normal`, an undo or a mapping; Normal mode puts as the control group,
  with every put key and a count, the register reads of Insert and
  Command-line mode, a put from Insert mode CTRL-O, numbered register
  puts repeated with `.`, which Vim moves to the next register, plain
  puts repeated with `.`, and Visual puts over the last line and from an
  Insert excursion.
* `registers`: operations against every register seed and history length,
  register writes that bypass TextYankPost, followed by a yank and on
  their own, yanks and deletes of nothing into every kind of register,
  and operations on an empty line.
* `settings`: each option that influences the operations, crossed with the
  operation groups it can affect, including every set of autoselect
  flags, of `'clipboard'` in terminal Vim and of `'guioptions'` in gVim,
  with every set of clipboard registers, each `'clipboard'` pair in either
  order, as Vim reports the `*` copy of a selection before the `+` copy,
  the puts that show what a selection left in the history, and Visual
  puts from every kind of register over the selection an autoselect
  register offers.
* `clipboard`: text copied by another application around FocusLost and
  FocusGained, followed by a yank, a delete or a Visual put, including text
  equal to the head and to an older item, with and without a `'clipboard'`
  register, a write into the unnamed register before the focus events, the
  system clipboard read back after Vim wrote it, and the startup under
  clipboard registers whose texts differ.
* `history`: runs of operations against every history length followed by
  a put of the head or of the oldest register, duplicates, the same text
  in another register type, undo, redo and time travel, repeat, and macros
  that yank when played back.
* `modes`: mode changes around the operations, such as Visual kind
  switches, Select hand-overs and Insert excursions.
* `ex`: the Ex commands that yank, delete or put.
* `silent`: operations that touch no register, such as case and shift
  changes, number increments, substitution, Replace mode and Insert mode
  deletions, between a yank and a put.
* `mouse`: selections made by dragging, double and triple clicks and a
  right click extension, followed by the keys that operate on them or a
  click that ends them, the middle button put, typing over a selection
  made with `'selectmode'` `mouse`, the same gestures and puts under every
  set of autoselect flags with every set of clipboard registers, and in
  gVim the gestures as modeless selections and middle button insertions
  under every set of `'guioptions'` autoselect flags with every set of
  clipboard registers.

Plugin configurations live in the same file: `default` with the clipboard
sync and `nosync` without it, which runs only the cases of the `clipboard`
matrix with focus events, as the sync shows in no other case. The history
length and `'clipboard'` vary per case and are applied before the plugin's
history and clipboard register names are reset and rebuilt from the options
and the seeded registers, as they are when Vim starts. The plugin refuses a
history length below ten, so the lengths start at ten.

Fixtures and register seeds live in `fixtures.vim`. Every register holds a
distinct value before a case runs, so any unexpected write shows up in the
diff with the register name in it, and the seeds shape the history the
plugin builds when it loads: full, partial and empty numbered registers,
gaps among them, duplicates, linewise and blockwise items, a clipboard
equal to `"0`, clipboard registers whose texts differ and a filled `*` next
to an empty `+`.

Isolation
---------

`run.sh` starts every Vim with an empty environment and a private home,
runtime directory and display. Nothing from the calling session reaches
Vim: no display, no Wayland socket, no D-Bus, no session clipboard. The
display variants are

* `none`: no display server, for terminal Vim only;
* `x11`: a private Xvfb server;
* `wayland`: a private headless sway compositor;
* `xwayland`: that compositor reached only through its Xwayland display.

The compositor is sway rather than weston because a headless weston offers
no data control protocol and no input seat, which leaves terminal Vim
without a clipboard and crashes gVim inside GTK on the first clipboard
write. A display variant whose server binary is missing is reported as
skipped with the binary named, and so is a gVim that cannot run on a
display: a gVim without Vim's own Wayland support limits GTK to X11 and
cannot open the `wayland` display, and the `xwayland` variant covers it
under a Wayland compositor instead. Clipboard cases are skipped on builds
without the clipboard feature. Terminal Vim reaches a display only through
the clipboard, so a terminal build without it runs on the `none` variant
alone and is reported as skipped on the others.

A build that reaches display servers runs every case on the first server it
reaches, and terminal Vim also on `none`, but only the clipboard cases on
the other servers: the other cases reach the same state under every server.
The clipboard cases use a clipboard register, set `'clipboard'` or a
`'guioptions'` flag that copies a selection to a clipboard register, or
insert the star register with the middle button, and the summary of a run
limited to them says so.

The system clipboard is reached with `wl-copy` and `wl-paste` under
`wayland` and with `xclip` under `x11` and `xwayland`. The tools run inside
the private display, so nothing leaks into the session clipboard. A Wayland
client exchanges the clipboard only while it has keyboard focus, and a
headless seat has no keyboard, so the `wayland` variant keeps a virtual
keyboard connected through `wtype`; without it gVim is skipped on that
display with the reason named. A writer stays in the foreground and is
stopped to empty the selection; a reader runs as a job while Vim keeps
serving the selection it owns. Cases that need a tool are skipped with a
reason when it is missing. Each run records whether the clipboard was
reachable.

Mouse gestures reach terminal Vim as the key codes it reads for presses and
releases, positioned through `test_setmouse()`, and as the SGR terminal
codes for drags, which carry their own position; gVim takes them through
`test_gui_event()`. With the mouse disabled for the mode, gVim turns a
gesture into a modeless selection, which the `'guioptions'` flags `a` and
`A` make Vim copy into the `*` register on the release, and the middle
button inserts that register into the buffer, so these need no further
mechanics. Terminal Vim leaves the modeless selection to the terminal
emulator.

Running locally
---------------

    test/run.sh

Environment variables select what runs:

| Variable   | Meaning                                               |
|------------|-------------------------------------------------------|
| `VIM_BIN`  | terminal Vim binaries, space separated, default `vim` |
| `GVIM_BIN` | gVim binaries, space separated, default `gvim`        |
| `DISPLAYS` | display variants, default `none x11 wayland xwayland` |
| `CONFIGS`  | plugin configurations from `matrices.vim`             |
| `MATRICES` | Vim pattern selecting matrix names                    |
| `CASES`    | Vim pattern selecting case ids                        |
| `RESULTS`  | report directory, default `test/results`              |
| `TIMEOUT`  | seconds per Vim process, default 1800                 |
| `VERBOSE`  | `1` prints every report line                          |

An empty `GVIM_BIN` skips the GUI.

Any Vim or gVim binary works, so a local build is covered by naming it: for
example a GTK 2 build with `GVIM_BIN=/opt/vim-gtk2/bin/gvim test/run.sh`,
and one matrix on one configuration with
`MATRICES='^put$' CONFIGS=default test/run.sh`. Vim has no GTK 4 GUI.

Each run writes `report.txt`, `junit.xml` and `results.jsonl` under the
results directory. `results.jsonl` lists only the cases that did not pass,
and the failing ones carry the full expected and actual state. `vim.log`
keeps the text of what Vim printed: terminal Vim redraws its screen around
every fed key, so the log drops the escape sequences and control characters
once Vim exits and keeps the messages of a process that stopped without a
report.

`harness.vim` records known failures, which it recognizes from the copies
Vim reports in the run without the plugin. A case that meets one counts as
known rather than failed while it fails, unless the harness could not drive
it, and fails the run once it passes, so that the record goes with the fix.

Distribution coverage
---------------------

    test/docker.sh debian:stable

builds `Dockerfile` on the given base image with every packaged Vim
variant, the display servers and the clipboard tools, then runs `run.sh`
inside with no network as the calling user. Debian's `vim-nox` is left out,
as it only adds language interfaces to `vim.basic` and yields the same
results. Xwayland admits local clients only when it can resolve their user
name, so the script mounts a minimal passwd file with that user. The GitHub
workflow runs the same script for Debian stable, the Ubuntu LTS and current
releases, and Fedora, and uploads the reports. Failures appear as
annotations in the workflow log.

Builds the plugin refuses, without Vim9 script or older than the patch it
requires, get a separate check that sourcing the plugin leaves no
autocommands behind and does not mark itself loaded. A history length below
ten gets the same check on every supported build, and the plugin must
report the length in its error message. The keys of a case are fed under
`:silent!`, which keeps messages out of the message history, so the message
for a yank beyond the history is checked by the startup check below. Every
supported build also loads the plugin as a package through Vim's own
startup, terminal Vim without a display and gVim on every display it runs
on, from a home directory whose vimrc sets `'clipboard'` and the history
length, and `startup.vim` checks after VimEnter that the plugin is loaded
with those settings in effect and shifts the numbered registers on a yank.
