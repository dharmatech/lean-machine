# Reloads held by undo

Each reload is a step undo can return to,
and the apps in the worlds undo keeps hold the Lean they were made
in. 40 reloads of Clock.lean added 11 to 16 MB; 10 of Editor.lean,
about 90 MB, 9 MB each. Undo keeps 500 worlds, so many reloads of a
big file would add up; Lean frees an environment once nothing refers
to it.

[↑ Reloading](README.md)
