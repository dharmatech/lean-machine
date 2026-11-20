# A middle click pastes the primary selection

Linux desktops keep a second clipboard, the primary selection: the text
last selected in any program, which a middle click pastes, with no
Ctrl+C first. X11 has always had it; on Wayland it's a protocol the
compositor offers, as GNOME's does, and SDL reads either
(`SDL_GetPrimarySelectionText`).

A middle press goes the way a paste key does
([A paste is an event the loop makes](paste-is-an-event.md)). The shim
hands back button 2, which `Event.decode` makes `Event.middle`. The
world never hears that: Main.lean reads the primary selection
(`Host.primarySelection`), and if it has text, feeds `Event.pasteAt`
with the pointer's place. Its release is nothing.

Unlike Ctrl+V, a middle click says where: the window under the pointer
comes to the front and is focused, as by a press, and its app hears
`AppEvent.pasteAt` in its own coordinates. A middle click on a title,
an edge, the bar or the desktop does nothing. Like any paste, it's a
step of its own, which undo takes back alone (`World.commits`).

Each app says what "there" is. The editor puts its cursor where the
click lands, the selection gone (a middle click doesn't paste over
what's selected), and pastes there; on the status line, at the cursor.
The REPL puts its cursor where the click lands on its line, and
anywhere else pastes at the cursor, as a terminal does; either way the
view comes back to the line. Other apps ignore it.

Not checked yet in a real window: whether GNOME hands the primary
selection over when a middle click is the first thing that focuses
Lean Machine's window. Wayland lets only the focused window read it.

Selecting in Lean Machine doesn't set the primary selection yet, so a
middle click pastes what was last selected in another program.

[↑ Drawing and input](README.md)
