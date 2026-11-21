import Tests.Kit

/-! # `--test`: pictures

Every `lean` block of docs/explore/pictures.md, read from the page and
pasted into the REPL as the page says: a click in the REPL, a paste,
Enter. It prints what came back from each, the windows they opened and
which has the focus, and writes the desktop after them all
(`pictures.png`); then undoes, and says what each undo took back. -/

namespace LeanMachine.Tests

-- The blocks of `lean` code in a Markdown text, in order.
def leanBlocks (md : String) : List String := Id.run do
  let mut blocks : List String := []
  let mut block : Option (Array String) := none
  for line in md.splitOn "\n" do
    let fence := line.trimAscii.toString
    match block with
    | none => if fence == "```lean" then block := some #[]
    | some ls =>
      if fence == "```" then
        blocks := blocks ++ [String.intercalate "\n" ls.toList]; block := none
      else block := some (ls.push line)
  return blocks

def testPictures (c : Canvas) (svc : Services) : IO Unit := do
  IO.println "pictures, pasted from docs/explore/pictures.md:"
  let page ← IO.FS.readFile (projectRoot / "docs" / "explore" / "pictures.md")
  let mut d := steps start [.tick ⟨10, 8, 30⟩]
  for b in leanBlocks page do
    let some w := winTitled d "REPL" | throw (IO.userError "no REPL")
    let (x, y) := (w.bodyX + 10, w.bodyY + 10)
    let (d', runs) ← feed svc d {} [.press x y, .release x y, .paste b, .key .enter {}]
    let (d', _, ended) ← settle svc d' runs
    d := d'
    IO.println s!"  {((b.splitOn "\n").headD "").quote}: {ended.map (·.showDone)}; \
      focus on {focused d}"
  IO.println s!"  windows: {d.now.windows.map (·.title)}"
  render c d.view; shot c "pictures.png"
  -- The windows the page opened, which all open in the same place,
  -- moved apart to see each.
  let opened := d.now.windows.filter (·.origin.isNone) |>.zipIdx.map fun (w, i) =>
    { w with x := 5 + 425 * (i % 3).toFloat, y := 10 + 275 * (i / 3).toFloat }
  render c { d with now := { d.now with windows := opened } }.view; shot c "pictures-apart.png"
  let mut u := d
  for _ in [0:3] do
    u := u.step undoKey
    IO.println s!"  undo: windows {u.now.windows.map (·.title)}"

end LeanMachine.Tests
