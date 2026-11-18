# Files as requests, answered at once

Reading, writing and listing
files don't go on threads of their own, as runs do: a run can be cut
off at any safepoint, which includes every allocation, and a write cut
off midway would leave half a file. Files this size take well under a
millisecond, so the loop answers on its own thread, as it answers a
stop with nothing to stop. Lean's `IO.FS.writeFile` truncates and
writes, so a crash midway would also leave half a file; the loop
writes beside the file and renames it over (`IO.FS.rename`).
`System.FilePath.walkDir` lists a tree, with a function that says
which folders to go into. The desktop's folder is noted as Eval.lean
compiles, as the sysroot is: in a term elaborator, `getFileName` is
the module's full path, because Lake passes Lean full paths.

[↑ Runs, requests and threads](README.md)
