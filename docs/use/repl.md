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

Each REPL has its own Lean, kept in its state, so undo takes back
definitions too. In a REPL, `world` is the desktop as it was when Enter
was pressed (`(·.windows.map (·.title)) <$> world`), and `launch app`
opens an app made there in a new window.

More:

- [Stopping a line](repl-stopping.md)
- [Colours and Tab](repl-colours.md)

How it works: [Lean inside the desktop](../design/lean/README.md)

[↑ Use](README.md)
