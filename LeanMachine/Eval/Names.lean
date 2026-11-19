import LeanMachine.Eval.Tokens

/-! # Names, for completion

`completeIn`: what a name being typed could become in a REPL's Lean.
The names the REPLs' Lean imported are indexed by namespace once
(`nameIndex`), and every REPL shares the index; what a REPL defined is
looked up in its own environment. -/

namespace LeanMachine
open Lean Elab

-- The names completion offers from what the REPLs' Lean imports, by the
-- namespace they're in: `Nat` ↦ `succ`, `add`, …; namespaces are names
-- in the namespace around them. Made once, in a task of its own once the
-- desktop's own Lean is imported, and shared by every REPL, as Lean's
-- language server keeps the "eligible header declarations" once.
-- Each name says whether it's a theorem's, which completion offers last.
abbrev NameIndex := Std.HashMap Name (List (String × Bool))

-- Does completion offer the constant `n`? Not what Lean's own completion
-- leaves out (`Meta.allowCompletion`: auxiliary recursors, matchers,
-- internal names), nor private names, nor names that need «».
def offered (env : Environment) (n : Name) : Bool :=
  match n with
  | .str _ s => isPlainName s && !isPrivateName n && Meta.allowCompletion env n
  | _ => false

-- The index of the constants `env` imported.
def nameIndex (env : Environment) : NameIndex := Id.run do
  let mut index : NameIndex := {}
  let mut spaces : Std.HashSet Name := {}
  for (n, c) in env.constants.map₁ do
    let .str p last := n | continue
    unless offered env n do continue
    index := index.insert p ((last, c matches .thmInfo _) :: index.getD p [])
    -- The namespaces it's in, each once, unless a namespace is also a
    -- constant (`Picture.brecOn`, whose equations are in it), which is
    -- offered or not as a constant, as in Lean's own completion.
    let mut ns := p
    while !spaces.contains ns do
      let .str q s := ns | break
      spaces := spaces.insert ns
      if isPlainName s && !env.contains ns then
        index := index.insert q ((s, false) :: index.getD q [])
      ns := q
  return index

-- What `word`, an identifier being typed, could become in `cmd`: `word`
-- with its last part finished as a name in the namespace its other parts
-- name, written from the current namespace, one around it, the root, or
-- an open one, as Lean would resolve it. A protected name needs its
-- namespace even when it's open. With no namespace, keywords too.
-- Sorted, theorems after the rest: they outnumber definitions, and a
-- line more often wants a definition.
def completeIn (cmd : Command.State) (index : Task NameIndex) (table : Parser.TokenTable)
    (word : String) : Array String := Id.run do
  let parts := word.splitOn "."
  let part := parts.getLastD ""
  let qualText := String.ofList (word.toList.take (word.length - part.length))
  let qual : Name := parts.dropLast.foldl Name.str Name.anonymous
  let scope := cmd.scopes.head!
  let env := cmd.env
  let rec around : Name → List Name
    | n@(.str p _) => n :: around p
    | _ => []
  let spaces : List (Name × Bool) :=
    (around scope.currNamespace ++ [Name.anonymous]).map (·, false) ++
    scope.openDecls.filterMap fun | .simple ns _ => some (ns, true) | _ => none
  -- Each name, and whether it's a theorem's.
  let mut out : Std.HashMap String Bool := {}
  for (ns, opened) in spaces do
    let space := ns ++ qual
    let fits (last : String) : Bool :=
      last.startsWith part &&
      !(opened && qual.isAnonymous && isProtected env (.str space last))
    for (last, thm) in index.get.getD space [] do
      if fits last then out := out.insert (qualText ++ last) thm
    -- What the REPL defined.
    for (n, c) in env.constants.map₂ do
      if let .str p last := n then
        if p == space && fits last && offered env n then
          out := out.insert (qualText ++ last) (c matches .thmInfo _)
  if qual.isAnonymous then
    for d in scope.openDecls do
      if let .explicit (.str .anonymous s) _ := d then
        if s.startsWith part then out := out.insert s false
    if !part.isEmpty then
      for tk in table.findPrefix part do
        if isWord tk then out := out.insert tk false
  return (out.toArray.qsort fun (a, t) (b, u) => (!t && u) || (t == u && a < b)).map (·.1)

end LeanMachine
