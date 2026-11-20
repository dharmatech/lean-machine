# Copy and cut are requests

Ctrl+C copies what's selected to the clipboard, the one other programs
paste from, and Ctrl+X cuts it: copies it, then takes it out of the
file as one edit. The status line says how much (`copied 7 lines`).

The clipboard is outside the world, so an app can't write it. It asks:
`Request.copy` with the text, which the loop does at once
(`Runs.handle`, through `Services.copy`, which is `Host.setClipboard`,
`SDL_SetClipboardText` in shim.c). Nothing comes back, as nothing can go
wrong that the app could act on. A paste goes the other way as an
event, because reading the clipboard has to happen when the key comes
([A paste is an event the loop makes](../drawing/paste-is-an-event.md)).

Ctrl+C already stopped a reload. Like a terminal that copies with a
selection and interrupts without one, Ctrl+C copies when something is
selected and stops a reload when nothing is. Ctrl+Shift+C only copies,
for when you want to copy during a reload. Ctrl+Shift and a letter are
otherwise the desktop's, but C isn't one of its letters.

The REPL copies the same way, but ends its selection when it does
([Copying from the REPL](../lean/copying-from-the-repl.md)).

Undo takes back what a cut did to the file, like any edit, but not the
clipboard: what was copied stays there.

Before the window opens, as in `--test`, a copy goes nowhere, so the
tests read the text from the request itself. Under SDL's offscreen
driver, which keeps a clipboard of its own, text with "é", "✓" and a
newline, set and read back through the shim, came back the same.

[↑ The editor](README.md)
