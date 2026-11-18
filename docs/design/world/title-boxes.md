# A title's boxes say what they do

The three boxes on a title are red, green and yellow on the focused
window and grey on the others, so colour alone doesn't say what a box
does: not on a window that isn't focused, not to someone who can't tell
red from green, and not to someone who doesn't know that yellow
minimizes here. So with the pointer on any of the three, all three are
in colour and each shows a glyph: × closes, − minimizes, a square
maximizes, and on a maximized window two squares, one behind the
other, restore. Away from them, a title is as plain as before. macOS
does the same, and so does Schevana's mac style.

The view decides it from the pointer the world already keeps
(`World.boxesLit`), as it lights the edge under the pointer, so it adds
no state and undo doesn't see it. It asks `World.grabAt`, as a press
would, so the glyphs show exactly where a click would hit a box: not
on the title's top rim or the right edge, which resize, and not on a
box another window covers.

[↑ The world and apps](README.md)
