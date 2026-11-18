# Apps made in the REPL

`launch` puts an app made by interpreted
code in a window, and its step and view run in the interpreter on the
main thread, between frames. A step that never returns would hang the
desktop: nothing guards the main thread yet.

[↑ Stopping](README.md)
