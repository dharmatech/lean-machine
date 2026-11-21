# Pictures, from the REPL

Everything the desktop draws is a `Picture`: circles, rectangles, lines
and text, as plain data. In the REPL you can make one and open it in a
window of its own. Change a number, paste it again, and see what
changed.

Copy each block below, click in the REPL (right-click the desktop and
pick REPL if none is open), press Ctrl+V, then Enter. A block that
opens a window opens it over the REPL, in front and focused: drag it
aside by its title to keep it in view, and click the REPL again before
you paste the next block.

First, a definition the others use. `picture` opens a window that
shows what `draw` makes at the window's width and height:

```lean
def picture (title : String) (draw : Float → Float → Picture) : IO Unit :=
  launch (App.of title () (fun _ _ => none) fun _ => draw)
```

It's an app whose state is `()`, which no event changes
(`fun _ _ => none`), and whose view draws the same thing in any state.

## A circle

```lean
picture "Dot" fun w h => .circle (w / 2) (h / 2) 40 0x9ece6a
```

- `(w / 2, h / 2)` is the middle of the window, 40 the radius, and
  `0x9ece6a` a green, written as `0xRRGGBB`.
- Resize the window: the circle stays in the middle, since the window
  asks for its picture again at every size.
- Change `40` to `90`, or the colour to `0xf7768e` (red), and paste it
  again. Each paste opens a new window, in the same place; the old one
  stays as it was, under it.

## Several shapes

```lean
picture "Shapes" fun w h => .group [
  .rect 20 20 140 90 10 0x7aa2f7,
  .ring (w - 80) 70 45 6 0xe0af68,
  .line 20 (h - 30) (w - 20) (h - 30) 4 0xf7768e,
  .text 34 72 20 0x1a1b26 "a box"]
```

- `.group` draws its list in order, each on top of the ones before:
  the text is on the box, so swap them and it's hidden.
- `.rect` is its corner, size, the radius of its corners, and its
  colour; try a radius of `0`, or `45`.
- The ring and the line are placed from the right and the bottom
  (`w - 80`, `h - 30`): make the window wider and they follow.

## Many, made by a function

```lean
picture "Sun" fun w h =>
  let n := 24
  .group <| (List.range n).map fun i =>
    let a := 2 * pi * i.toFloat / n.toFloat
    .line (w / 2) (h / 2) (w / 2 + 90 * a.cos) (h / 2 + 90 * a.sin) 3 0xe0af68
```

- `n` lines, evenly around a circle. Try `n := 60`, or `n := 5`.
- Try `150` in place of both `90`s: lines that go past the window's
  edge are cut off there.

## Text

```lean
picture "Hello" fun w h => .textIn 0 0 w h 28 .center 0xc0caf5 "Hello from the REPL"
```

- `.textIn` centres the text in a box, here the whole window. Resize
  it: the text stays in the middle. Try `.left` or `.right`.

## The desktop, in a picture

In the REPL, `world` is the desktop as it was when you pressed Enter.
Here are its windows, at a quarter of their size:

```lean
do
  let ws := (← world).windows
  picture "Map" fun _ _ => .group <| ws.map fun (win : Win) =>
    let (x, y, w, h) := (win.x / 4, win.y / 4, win.w / 4, win.h / 4)
    .group [.rect x y w h 3 0x7aa2f7, .rect (x + 1) (y + 1) (w - 2) (h - 2) 3 0x24283b,
            .text (x + 4) (y + 12) 10 0xc0caf5 win.title]
```

- Each window is two boxes, a blue one and a dark one just inside it,
  which leaves a blue edge. They're drawn back to front, as the desktop
  draws them.
- `(win : Win)` tells Lean what `win` is; without it, Lean can't tell
  what `win.x` means.
- Move a window: the map stays as it was. It holds the windows as they
  were when it was made, not the desktop as it is now. Paste it again
  for a new map.

## Colours

The desktop's own colours, to try in place of the ones above:
`0xc0caf5` (white), `0x7aa2f7` (blue), `0x7dcfff` (cyan), `0x9ece6a`
(green), `0xe0af68` (yellow), `0xf7768e` (red), `0xbb9af7` (purple),
`0x414868` (grey), `0x1a1b26` (the window's background).

## Where next

- [A spinner](spinner.md): a picture that changes with time.
- [A slider](slider.md): a picture that changes as you drag.
- Every kind of picture: `LeanMachine/Picture.lean`.
- Ctrl+Shift+Z takes back the last thing that happened: right after a
  paste, the window it opened. Press it again and again to go back past
  the clicks and pastes, to before `picture` was defined.

[↑ Explore](README.md)
