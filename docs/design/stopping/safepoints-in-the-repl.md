# Safepoints in what the REPL compiles

Lean 4.36's compiler (LCNF)
runs a list of passes kept in the environment, as an extension's state
(`passManagerExt`), so that a module can add passes for the modules
that import it (`@[cpass]`). The REPLs' Lean gets one more pass by
changing that state once it's imported: the pass is compiled into the
desktop, so the REPLs' Lean needn't import Lean for it, and nothing
else compiles with it. It runs at the end of the impure phase, after
boxing and reference counting, so that nothing later drops or moves
what it adds, and starts every function with `safepoint 0`, those of
`#eval` included. Loops in what Lean compiles are recursive functions
(join points don't loop), so a safepoint at the start of every
function reaches every loop the REPL compiles, closures and
specializations of library loops included: `quiet 4000000 0` stops 50
ms after Ctrl+C. Two things to know when writing such a pass: in the
impure phase a `cases` is named by its discriminant's type in the
machine (`UInt8` for a `Bool`; naming it `Bool` panics in
`nameToIRType`), and an impure signature no longer says whether a
function is IO, so `returnsIO` asks the declaration the mono phase
saved (`… → lcVoid → EST.Out IO.Error …`).

[↑ Stopping](README.md)
