# The desktop

Right-click anywhere, or press Ctrl+Shift+N, for a menu of apps; choose
one to open it in a new window where the menu was. Esc closes the menu,
and so does a click off it. Drag a window by its title (not below the
taskbar: the top of the title stays above it), click one to raise it,
click the red box on a title to close it, Ctrl+Shift+Z to undo, Esc to
quit (in full screen, Esc leaves full screen first). Clock is a clock. With the pointer on the boxes of any title, each
shows what it does: × closes, − minimizes, a square maximizes, and two
squares restore a maximized window.

To resize a window, drag one of its edges or corners, or the grip in
its bottom right corner. An edge lights up when the pointer is close
enough to grab it, which includes a few pixels outside the window. On
top, only the title's thin upper rim resizes; the rest of the title
moves the window. A window can't be made smaller than 200 × 140, and
an edge stops at the edge of the desktop. One Ctrl+Shift+Z puts back
the window's old size, and its app's state with it.

To maximize a window, click the green box on its title, double-click
the title, or press Ctrl+Shift+M with the window focused. It then fills
the desktop above the bar, and its green box has a hole in it. Any of
the three restores it to where it was, and so does dragging it. Dragged
by its title, it takes its old size under the pointer; dragged by an
edge, it resizes from where it is. One Ctrl+Shift+Z undoes a maximize or
a restore.

The taskbar along the bottom has a button for each window, in the
order they were opened: a dot, then the window's title. The focused
window's button is underlined. To minimize a window, click the yellow
box on its title, press Ctrl+Shift+H with the window focused, or click
its button on the taskbar when it's the focused one. It's then only on
the taskbar, its button dimmed, and the frontmost window left has the
focus. Click its button to bring it back where it was, maximized if it
was, in front and focused. A minimized app still keeps time and
finishes what it was running. One Ctrl+Shift+Z undoes a minimize or a
bringing back.

Inspector and Notes are placeholders: click in one to drop a dot, or
type into it to see the text and the last key, with its modifiers, that
it heard. Each also shows its size and the size it last heard, which
match as you resize it.

At the right of the taskbar, a hint of the keys, and the count of
earlier worlds that undo can return to. The hint gives way when the
buttons need its room.

The Lean Machine window itself resizes and maximizes like any other
window on your screen, down to 640 × 400. As it grows, the windows in
it stay where they are; as it shrinks, its right edge and the taskbar
push them in, only as far as they have to. A maximized window fills
the new desktop. Undo doesn't change the window's size: it brings the
windows back as they were, inside the size it is now.

On GNOME's Wayland session, a long, fast drag of the window's edge can
stall for a second or two before the window catches up; a slower drag,
maximizing and F11 aren't affected ([A long, fast resize stalls on
Wayland](../design/drawing/wayland-resize-stall.md)).

To paste, copy text in any other program, then press Ctrl+V (or
Ctrl+Shift+V, or Shift+Insert) in Lean Machine: the focused window gets
the text. The editor and the REPL take it. One Ctrl+Shift+Z takes a
paste back, and leaves what you typed before it. Text you copy in the
editor or the REPL (Ctrl+C) pastes in other programs too
([A paste is an event the loop makes](../design/drawing/paste-is-an-event.md)).

F11 puts the Lean Machine window in full screen: it fills your screen,
with no frame or title, and the desktop fits itself to it as it does
to any size. F11 again, or Esc, takes it out. Apps never hear F11.

How it works: [The world and apps](../design/world/README.md)

[↑ Use](README.md)
