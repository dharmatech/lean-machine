# The world is gone from IO

In Lean 4.36, `IO α` is `EST IO.Error
IO.RealWorld α`: a function from an erased world (`Void`) to an
`EST.Out`, `ok` or `error` with one field each. Externs take no world
argument, and `BaseIO` and `ST` results aren't boxed at all. So an IO
function can return the error object at its start with no world to
thread. runs.cpp's externs, written for the older convention, took a
world argument Lean no longer passes, and `sv_guarded_io` handed that
garbage to the action as its world; harmless, as the world is never
read, and now gone.

[↑ Stopping](README.md)
