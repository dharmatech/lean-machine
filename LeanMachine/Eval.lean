import LeanMachine.Eval.Repl
import LeanMachine.Eval.Reload

/-! # Eval: Lean in the desktop's own process

With its parts in Eval/, the only modules that import Lean. A REPL's
`Env` holds Lean's command state: the environment and the scopes its
lines leave open, and the tokenizer and completion that read them. The
desktop's own Lean imports Init and the desktop's modules once, in the
background, with `LeanMachine` open; every REPL starts from it.

A line is elaborated on the calling thread, which is a run's, so that a
stop reaches it and the run's ambient is there. `Elab.process` won't do:
it elaborates each command in a task on Lean's pool of threads. Nor will
the older `Frontend.processCommands`, which runs on the calling thread
but loses every message. `runCommands` parses and elaborates itself.

The REPL's Lean compiles with one more pass than Lean's own: every
function it compiles starts at a safepoint, so that its loops can be
stopped, and an IO function returns `IO.Error.interrupted` there when a
stop is offered (LeanMachine/Safepoint.lean).

The parts: Eval/Safepoints.lean, the extra compiler pass;
Eval/Tokens.lean, a line's tokens; Eval/Names.lean, completion;
Eval/Repl.lean, a REPL's Lean and `eval`; Eval/Reload.lean, an app
reloaded from its file. `projectRoot` stays here: it's two folders up
from this file, so it can't move into Eval/. -/

namespace LeanMachine
open Lean Elab

-- The desktop's own folder, where its lakefile is, read while this module
-- was compiled (Lake hands Lean the module's full path): the paths of
-- files that apps read and write start there.
elab "sourceRoot%" : term => do
  let file : System.FilePath := ← IO.FS.realPath (← getFileName)
  return mkStrLit ((file.parent.bind (·.parent)).getD ".").toString

def projectRoot : System.FilePath := sourceRoot%

end LeanMachine
