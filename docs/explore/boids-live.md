# Change Boids while it flies

Boids' app, `LeanMachine/Apps/Boids.lean`, can be reloaded from the
editor while the flock flies. Its simulation stays compiled underneath,
so the reloaded flock flies as fast as before.

Right-click the desktop and pick Boids, then right-click again and pick
Editor. In the editor, type `apps/boids.lean` and press Enter. Then try
these changes. After each, press Ctrl+R in the editor: every Boids
window starts again with the new code. Ctrl+R reloads the file as it is
in the editor; nothing is saved unless you press Ctrl+S.

- **Green birds.** Near the end, in `Boid.picture`, change the dot's
  yellow, `0xe0af68`, to `0x9ece6a`.
- **Longer heading lines.** In the same place, change
  `b.velocity * (4 : Float)` to `(10 : Float)`.
- **A new key.** In `State.heard`, under the line for `'d'`, add:

  ```lean
      | .char 'x' => some { s with flock := s.flock.map fun b => { b with velocity := -b.velocity } }
  ```

  Reload, click the Boids window, and press X: every bird turns around.
- **A change the file's checks catch.** In `State.start`, change
  `Flock.scatter 150` to `300`. Nothing reloads: the `#guard`s at the
  end of the file expect 150 birds, and their lines are marked. The
  flock flies on with the code it had.
- **Undo.** Ctrl+Shift+Z brings back the Boids from before the last
  reload.
- **The simulation.** Press Ctrl+O (twice if the file has changes),
  type `boids/flock`, press Enter, then Ctrl+R. The editor says
  Flock.lean is compiled into the desktop's Lean: rebuild the desktop
  to change it.

The simulation is in the REPL too. Right-click, REPL, and type:

```lean
(Boids.Flock.demo.stepOn {} 100 100).map (·.position)
```

## Where next

- Each reload starts the flock over: the new code can't read the old
  state ([No state carries over](../design/reloading/no-state-carries-over.md)).
- [A compiled simulation under a reloaded app](../design/reloading/compiled-under-reloaded.md):
  why the simulation isn't reloaded too.
- [Using Boids](../use/boids.md): its keys.

[↑ Explore](README.md)
