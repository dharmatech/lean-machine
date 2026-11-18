# What a line of a file costs

About 24 µs a line: all 258 lines of
Repl.lean in 6.1 ms, as a file opens or the desktop's Lean arrives. A
keystroke, the editor's step with its line read again, 77 µs; Down,
1.3 µs. An edit reads the lines below only while they start
differently than before, so `/-` typed at the top costs 0.26 ms (a
line inside a comment is only scanned for `-/`), and deleting its `/`
6 ms, every line read again by the tokenizer. That's on the main
thread, in the step: a file of 2,000 lines would take some 50 ms, a
dropped frame or three. Reading only the lines in view, and the rest
when they come into view, would bound it.

[↑ The editor](README.md)
