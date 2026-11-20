# A paste is an event the loop makes

Ctrl+V, Ctrl+Shift+V (a terminal's) and Shift+Insert paste
(`pasteKey`). They're the loop's, like F11: Main.lean reads the
clipboard through SDL (`Host.clipboard`, `SDL_GetClipboardText` in
shim.c), and the focused app hears `AppEvent.paste` with the text, not
the key. An empty clipboard, or one with no text on it, sends nothing.

Why the loop, and not a request the app makes:

- Apps stay pure. The clipboard belongs to the rest of your screen, and
  reading it is I/O, like reading a file.
- Every app has the same paste keys, and none has to ask for them.
- A paste is one step in the world, and undo takes it back on its own
  (`World.commits`): text typed before it stays.
- Tests hand the text over as `Event.paste`. Without a window, as in
  `--test`, the clipboard is empty.

Pasted text comes from anywhere, so each app tidies it first
(`pastedLines`): lines end at "\n", "\r\n" or "\r"; a tab becomes two
spaces, as Lean takes no tabs ("tabs are not allowed"); other control
characters go, so a terminal's colour codes lose their Esc.

The editor puts the lines in the file at the cursor, keeping their own
indent (`Buffer.paste`), and reads each with what the line before left
open (`Buffer.relexAbove`), so a comment pasted across lines is
coloured as one. The REPL takes one line, ignoring blank lines around
it; several lines only leave a note for now.

On GNOME's Wayland session, in a real window, `Host.clipboard` read the
same 949 bytes as `wl-paste`, from a copy in Chromium that had HTML on
the clipboard too: SDL takes the plain text. Wayland lets only the
focused window read the clipboard, and a paste key always comes to it.

[↑ Drawing and input](README.md)
