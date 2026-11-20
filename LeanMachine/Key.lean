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
  | enter | tab | backspace | delete | insert | escape
  | left | right | up | down | home | «end» | pageUp | pageDown
  | f11                      -- the loop's: full screen, which apps don't hear
  | other (code : UInt32)    -- any other key, by SDL's number for it
  deriving BEq, Inhabited, Repr

def Key.name : Key → String
  | .char ' ' => "Space"
  | .char c => c.toUpper.toString
  | .enter => "Enter"
  | .tab => "Tab"
  | .backspace => "Backspace"
  | .delete => "Delete"
  | .insert => "Insert"
  | .escape => "Esc"
  | .left => "Left"
  | .right => "Right"
  | .up => "Up"
  | .down => "Down"
  | .home => "Home"
  | .«end» => "End"
  | .pageUp => "PageUp"
  | .pageDown => "PageDown"
  | .f11 => "F11"
  | .other n => s!"key {n}"

-- "Ctrl+Shift+N"
def Key.show (k : Key) (m : Mods) : String :=
  (if m.ctrl then "Ctrl+" else "") ++ (if m.alt then "Alt+" else "") ++
  (if m.shift then "Shift+" else "") ++ k.name

-- The desktop's own keys are Ctrl+Shift and a letter: Ctrl+Shift+N opens
-- the menu of apps, M maximizes or restores the focused window, H
-- minimizes it, Z undoes. Apps hear every other key, but F11 and the
-- paste keys, which are the loop's.
def desktopKey (c : Char) (k : Key) (m : Mods) : Bool :=
  k == .char c && m == ctrlShift

-- The keys that paste: Ctrl+V, Ctrl+Shift+V (a terminal's) and
-- Shift+Insert. They're the loop's: it reads the clipboard, and the
-- focused app hears what was on it (`AppEvent.paste`), not the key.
def pasteKey (k : Key) (m : Mods) : Bool :=
  (k == .char 'v' && m.ctrl && !m.alt) || (k == .insert && m == { shift := true })

#guard pasteKey (.char 'v') { ctrl := true } && pasteKey (.char 'v') ctrlShift
#guard pasteKey .insert { shift := true }
#guard !pasteKey (.char 'v') {} && !pasteKey (.char 'v') { ctrl := true, alt := true }
#guard !pasteKey .insert {}

end LeanMachine
