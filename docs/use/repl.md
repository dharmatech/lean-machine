# The REPL

The REPL evaluates Lean in the desktop's own process: Init and the
desktop's modules but its apps, with `LeanMachine` open (the apps are
values in `(← world).catalog`, by the name of their declaration:
``do launch ((← world).catalog.lookup `LeanMachine.clock).get!`` opens a
clock). A line is Lean commands
(`def sq (n : Nat) := n * n`, `#eval`, `namespace`, `open`) or a term,
evaluated as `#eval` would (`sq 12`); what Lean says comes back under
it, errors in red.

Click in the REPL and type; Left, Right, Home, End, Backspace
and Delete edit the line, and Up and Down go back and forth through
earlier lines.

Ctrl+V pastes what you copied elsewhere, lines and all: a `def` with a
`where`, a `structure`, a few commands and an `#eval`. Shift+Enter
starts a new line yourself, indented like the one above (two more after
`:=`). In a line of several, Home and End go to the start and end of
the cursor's own line, and Up and Down move between them; from the
first or the last, they go through earlier lines as usual. Enter
evaluates all of it, and an error says which line it's on (`line 2,
col 2`).

Each REPL has its own Lean, kept in its state, so undo takes back
definitions too. In a REPL, `world` is the desktop as it was when Enter
was pressed (`(·.windows.map (·.title)) <$> world`), and `launch app`
opens an app made there in a new window.

More:

- [Stopping a line](repl-stopping.md)
- [Colours and Tab](repl-colours.md)

How it works: [Lean inside the desktop](../design/lean/README.md)

[↑ Use](README.md)
