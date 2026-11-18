# An app doesn't know its size

A view gets the window's size, but
a step doesn't, and the editor's step must keep the cursor in view as
it moves, so which line is at the top is state, and the step needs
to know how many lines fit. Windows don't change size yet, so the
editor uses the size it asks for. Once they do, apps will need to hear
their size as an event, as they hear the time.

[↑ The world and apps](README.md)
