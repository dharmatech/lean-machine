# Reloaded code is interpreted

A reloaded app runs in Lean's
interpreter, as REPL code does, called from the compiled loop. A
clock's view takes 220 µs instead of 15 (it computes 60 marks and
three hands with `sin` and `cos`), and is drawn in 0.75 ms instead of
0.53; an editor's Down, 44 µs instead of 1.7; its view 450 µs instead
of 105; a keystroke 135 µs instead of 80 (most of it is Lean's
tokenizer, which is compiled either way). Fine for these apps; a frame
still fits easily. Without the safepoints it's 3 to 8% faster. Native
code would mean a C compiler at run time and `Lean.Dynlib.load`, with
new symbol names for each reload, since Lean never unloads a library.

[↑ Reloading](README.md)
