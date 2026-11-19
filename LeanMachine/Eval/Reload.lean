import LeanMachine.Eval.Repl

/-! # Reloading an app from its file

`reload` elaborates a file's text in the desktop's own Lean, as Lake
would compile it there, and makes a value of each app it defines. -/

namespace LeanMachine
open Lean Elab

-- What Lean said about a file, by line and column (from 0).
def remarksOf (msgs : Array Message) : IO (List Remark) :=
  msgs.toList.mapM fun m => do
    let text := (← m.data.toString).trimAscii.toString
    let said := match m.severity with
      | .information => Said.info text
      | .warning => .warning text
      | .error => .error text
    return { line := m.pos.line - 1, col := m.pos.column, said }

-- The module a file in the desktop's folder is: `LeanMachine.Apps.Clock`
-- for `LeanMachine/Apps/Clock.lean`.
def moduleOf (path : System.FilePath) : Name :=
  (path.withExtension "").components.foldl .str .anonymous

#guard moduleOf "LeanMachine/Apps/Boids/Flock.lean" == `LeanMachine.Apps.Boids.Flock

-- The constants of type `App` that `env` has beyond what it imported,
-- by name.
def appsIn (env : Environment) : List Name :=
  let names := env.constants.map₂.toList.filterMap fun (n, c) =>
    if c.type == .const ``App [] && !n.isInternal then some n else none
  (names.toArray.qsort (·.toString < ·.toString)).toList

-- Elaborates the text of a file in the desktop's own Lean, as Lake would
-- compile it there: what Lean said, the Lean after it (for the editor,
-- with `LeanMachine` open, as the desktop's own), and, if Lean found no
-- error, the apps the file defines, by name. The file's header must
-- import only what the desktop's Lean did, and the rest of the file is
-- elaborated from the root namespace, with nothing open. Each reload
-- starts again from the desktop's Lean, so the file's declarations never
-- meet an earlier reload's. A file the desktop's Lean imported can't be
-- reloaded: its declarations are there already, compiled. Stops as
-- `eval` does once `cancel` is set.
def reload (base : Task (Except IO.Error Held)) (path src : String)
    (cancel : IO.CancelToken) : IO (Outcome × List (Name × App)) := do
  let h ← IO.ofExcept (← IO.wait base)
  let have_ := h.cmd.env.header.moduleNames
  let self := moduleOf path
  if have_.contains self then
    return (.failed s!"{self} is compiled into the desktop's Lean: rebuild the desktop to \
      change it", [])
  let ictx := Parser.mkInputContext src path
  let (header, ps, headerSaid) ← Parser.parseHeader ictx
  if headerSaid.hasErrors then
    return (.reloaded (← remarksOf headerSaid.toArray) (Env.of h) [], [])
  let missing := (Elab.headerToImports header).filter (!have_.contains ·.module)
  unless missing.isEmpty do
    return (.failed s!"it imports {", ".intercalate (missing.toList.map (toString ·.module))}, \
      which the desktop's Lean doesn't: only Init and LeanMachine's modules but the apps", [])
  let s : Command.State :=
    { Command.mkState h.cmd.env {} (Elab.async.set {} false) with infoState.enabled := false }
  let (s, msgs, stopped) ← elabCommands ictx ps cancel s
  if stopped then return (.stopped [] true, [])
  let said ← remarksOf msgs
  let env := Env.of { h with cmd := { h.cmd with env := s.env } }
  if msgs.any (·.severity == .error) then return (.reloaded said env [], [])
  let mut apps := #[]
  let mut more := #[]
  for n in appsIn s.env do
    match unsafe s.env.evalConst App {} n (checkMeta := false) with
    | .ok app => apps := apps.push (n, app)
    | .error why => more := more.push { line := 0, col := 0, said := .error s!"{n}: {why}" }
  return (.reloaded (said ++ more.toList) env (apps.toList.map (·.1)), apps.toList)

end LeanMachine
