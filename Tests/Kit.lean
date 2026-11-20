import LeanMachine.Loop
import LeanMachine.Host
import LeanMachine.View
import LeanMachine.Eval
import Tests.Show

/-! # What the tests share

Driving the desktop and its apps from a script, with what they ask for
done at once (`settle`, `stepNow`, `answerNow`); what windows and
pictures show; where the pictures go (`testOut`); and timing. -/

namespace LeanMachine

-- How many `mono`s a picture draws: a row of a REPL is one per run.
partial def Picture.monos : Picture → Nat
  | .mono .. => 1
  | .group ps => ps.foldl (· + ·.monos) 0
  | .translate _ _ p | .clip _ _ _ _ p => p.monos
  | _ => 0

-- The texts a picture shows, in order.
partial def Picture.texts : Picture → List String
  | .text _ _ _ _ s | .textIn _ _ _ _ _ _ _ s | .mono _ _ _ _ s => [s]
  | .group ps => ps.flatMap (·.texts)
  | .translate _ _ p | .clip _ _ _ _ p => p.texts
  | _ => []

def Win.texts (w : Win) : List String := (w.app.view w.bodyW w.bodyH).texts

end LeanMachine

namespace LeanMachine.Tests

-- Waits for every run to end, up to `ms`, and tells the desktop how each
-- did; also returns the outcomes, oldest first.
partial def settle (svc : Services) (d : Desktop) (runs : Runs) (ms : Nat := 30000)
    (seen : List Event := []) : IO (Desktop × Runs × List Event) := do
  let (runs, ended) ← runs.collect
  let (d, runs) ← feed svc d runs ended
  let seen := seen ++ ended
  if runs.live.isEmpty || ms == 0 then return (d, runs, seen)
  IO.sleep 1
  settle svc d runs (ms - 1) seen

-- An app's state after `e`, with what it asks for worked out at once, on
-- this thread, outside any run.
def answerNow {σ : Type} (svc : Services) (step : σ → AppEvent → Option (σ × List Request))
    (r : σ) (e : AppEvent) : IO σ := do
  match step r e with
  | none => return r
  | some (r, asks) => asks.foldlM (init := r) fun r a => do
    let answer : Option AppEvent ← match a with
      | .run tag work => pure (some (.done tag (.value (work ())) 0))
      | .eval tag src env => do
        pure (some (.done tag (← svc.eval src env (← IO.CancelToken.new)) 0))
      | .stop tag => pure (some (.done tag (.stopped [] false) 0))
      | .read tag _ | .write tag _ _ | .list tag _ => do
        pure (some (.done tag (← (fileOutcome svc.root a).getD (pure (.failed "?"))) 0))
      -- The apps it made go nowhere: there's no world here.
      | .reload tag path src => do
        pure (some (.done tag (← svc.reload path src (← IO.CancelToken.new)).1 0))
      -- Nothing comes back from a copy, or a selection.
      | .copy text => do svc.copy text; pure none
      | .select text => do svc.select text; pure none
    match answer with
    | some answer => return ((step r answer).map (·.1)).getD r
    | none => return r

def hearNow (svc : Services) : Repl → AppEvent → IO Repl := answerNow svc Repl.step

-- The desktop after `e`, with the runs its apps ask for ended.
def stepNow (svc : Services) (d : Desktop) (e : Event) : IO Desktop := do
  let (d, runs) ← feed svc d {} [e]
  let (d, _, _) ← settle svc d runs
  return d

-- Where `--test` puts what it makes, the pictures and the editor's
-- scratch file, wherever it runs from. It's under .lake, which git
-- ignores, and can be deleted at any time.
def testOut : System.FilePath := projectRoot / ".lake" / "test"

-- The canvas as a picture in `testOut`.
def shot (c : Canvas) (name : String) : IO Unit := c.savePng (testOut / name).toString

-- An app after `e`, with what it asks for worked out at once, on this
-- thread. The apps a reload makes go nowhere: there's no world here.
def appNow (svc : Services) (a : App) (e : AppEvent) : IO App :=
  answerNow svc (fun (a : App) e => a.step e) a e

-- An editor after `evs`, with what it asks for worked out at once.
def editorNow (svc : Services) (e : Editor) (evs : List AppEvent) : IO Editor :=
  evs.foldlM (answerNow svc Editor.step) e

-- The desktop after each of `lines` is typed into the REPL, a press in
-- its body first, and the runs it asks for have ended; and what came
-- back from them, oldest first.
def typedInRepl (svc : Services) (d : Desktop) (lines : List String) :
    IO (Desktop × List Event) := do
  let mut d := d
  let mut seen := []
  for line in lines do
    let (d', runs) ← feed svc d {} [.press 120 200, .text line, .key .enter {}]
    let (d', _, ended) ← settle svc d' runs
    d := d'; seen := seen ++ ended
  return (d, seen)

-- The memory the process holds (its resident set), in MB.
def rssMB : IO Nat := do
  let s ← IO.FS.readFile "/proc/self/status"
  let line := ((s.splitOn "\n").find? (·.startsWith "VmRSS:")).getD ""
  let kb := ((line.drop 6).trimAscii.toString.takeWhile Char.isDigit).toNat!
  return kb / 1024

-- Microseconds a call of `act`, over `n` calls. `act` gets the call's
-- number, so that the work in it can't be done once for all.
def usPer (n : Nat) (act : Nat → IO Unit) : IO Float := do
  let t0 ← IO.monoNanosNow
  for i in [0:n] do act i
  return ((← IO.monoNanosNow) - t0).toFloat / n.toFloat / 1000

-- Milliseconds since `t0`, a time from `IO.monoNanosNow`.
def msSince (t0 : Nat) : IO Nat := return ((← IO.monoNanosNow) - t0) / 1000000

-- Windows by their titles: where one is, and what it shows.
def winTitled (d : Desktop) (title : String) : Option Win := d.now.windows.find? (·.title == title)
def rectOf (d : Desktop) (title : String) : String :=
  ((winTitled d title).map (showRect ·.rect)).getD "no such window"
-- What a window shows on a line that starts with `s`.
def says (d : Desktop) (title s : String) : String :=
  ((((winTitled d title).map (·.texts)).getD []).find? (·.startsWith s)).getD "?"
-- A press at (x, y), the pointer moved (dx, dy) in two motions, and a release.
def dragBy (x y dx dy : Float) : List Event :=
  [.press x y, .motion (x + dx / 2) (y + dy / 2), .motion (x + dx) (y + dy),
   .release (x + dx) (y + dy)]
-- The desktop after `es`, with nothing its apps ask for done.
def steps (d : Desktop) (es : List Event) : Desktop := es.foldl Desktop.step d
def undoKey : Event := .key (.char 'z') ctrlShift
-- Ctrl+Shift+M and Ctrl+Shift+H: the focused window maximized, or
-- minimized.
def maximizeKey : Event := .key (.char 'm') ctrlShift
def minimizeKey : Event := .key (.char 'h') ctrlShift
-- A press and a release at (x, y).
def click (x y : Float) : List Event := [.press x y, .release x y]
-- A press on the middle of item `i` of a menu opened at (x, y).
def menuItem (x y : Float) (i : Nat) : Event := .press (x + 20) (Menu.itemY ⟨x, y⟩ i + itemH / 2)
-- The title of the focused window, or "nothing".
def focused (d : Desktop) : String :=
  ((d.now.windows.find? (·.id == d.now.focus)).map (·.title)).getD "nothing"
-- The line numbers the gutter of the editor window titled `title` shows.
def lineNumbers (d : Desktop) (title : String) : List String :=
  (((winTitled d title).map (·.texts)).getD []).filter fun s =>
    s.length == gutterCols - 1 && !s.trimAscii.isEmpty && s.trimAscii.toString.all Char.isDigit

end LeanMachine.Tests
