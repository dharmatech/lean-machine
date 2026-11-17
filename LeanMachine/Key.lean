/-! # Keys: which key went down, and the modifiers held with it

Characters arrive as text (`AppEvent.text`), the way the keyboard layout
and input method made them. A key says which key went down, for editing
and commands: Backspace, the arrows, Ctrl+C. -/

namespace LeanMachine

-- The modifier keys held with a key; either side's counts.
structure Mods where
  ctrl : Bool := false
  shift : Bool := false
  alt : Bool := false
  deriving BEq, Inhabited, Repr

def ctrlShift : Mods := { ctrl := true, shift := true }

inductive Key where
  | char (c : Char)          -- a key with a character on it, lower case
  | enter | tab | backspace | delete | escape
  | left | right | up | down | home | «end» | pageUp | pageDown
  | other (code : UInt32)    -- any other key, by SDL's number for it
  deriving BEq, Inhabited, Repr

def Key.name : Key → String
  | .char ' ' => "Space"
  | .char c => c.toUpper.toString
  | .enter => "Enter"
  | .tab => "Tab"
  | .backspace => "Backspace"
  | .delete => "Delete"
  | .escape => "Esc"
  | .left => "Left"
  | .right => "Right"
  | .up => "Up"
  | .down => "Down"
  | .home => "Home"
  | .«end» => "End"
  | .pageUp => "PageUp"
  | .pageDown => "PageDown"
  | .other n => s!"key {n}"

-- "Ctrl+Shift+N"
def Key.show (k : Key) (m : Mods) : String :=
  (if m.ctrl then "Ctrl+" else "") ++ (if m.alt then "Alt+" else "") ++
  (if m.shift then "Shift+" else "") ++ k.name

-- The desktop's own keys are Ctrl+Shift and a letter: Ctrl+Shift+N opens
-- the menu of apps, Ctrl+Shift+Z undoes. Apps hear every other key.
def desktopKey (c : Char) (k : Key) (m : Mods) : Bool :=
  k == .char c && m == ctrlShift

end LeanMachine
