# Putting a file back

Ctrl+R reloads a file as it is in the editor, saved or not, and only
Ctrl+S writes it. So until you save, the file on disk is the one git
has: `git status` says nothing has changed, and Lean Machine starts as
it always did.

## Without saving

- **The app from before a reload:** Ctrl+Shift+Z right after Ctrl+R.
  Every window that had the app gets the old one back. Your changes
  stay in the editor, so another Ctrl+R brings them back.
- **The file as it is on disk:** in the editor, Ctrl+O, then Ctrl+O
  again to leave your changes. Open the file again, and press Ctrl+R:
  the app is the file's again.
- **Everything:** quit with Esc, and start Lean Machine again. What
  you didn't save is gone, and the desktop starts with the apps it was
  built with.

## After Ctrl+S

The file has changed, and git sees it. In a terminal, in Lean
Machine's folder:

```sh
git status
```

lists the files that changed, and

```sh
git diff
```

shows how. To put a file back as git has it:

```sh
git restore LeanMachine/Apps/Clock.lean
```

Then open it again in the editor and press Ctrl+R, or start Lean
Machine again. A saved change goes into the desktop itself at its next
build (`lake build`, or `lake exe desktop`), so restore the file before
you build.

To keep your changes instead, put them on a branch of your own:

```sh
git switch -c my-clock
git commit -am "A green second hand"
git switch master
```

`git switch master` takes the files back to Lean Machine as it was,
and `git switch my-clock` brings your changes back.

[↑ Use](README.md)
