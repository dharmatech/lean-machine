# Install and run

So far Lean Machine is only tested on Ubuntu 26.04.

## What it needs

- Lean 4.36, through elan (`lean-toolchain` pins it)
- Cairo, with its headers, found through `pkg-config`
- SDL3's shared library (its headers, `libsdl3-dev`, are not needed)
- a C compiler (`cc`) and a C++ compiler (`c++`)

The desktop reads the .olean files of the Lean it was built with when it
runs, so that toolchain must stay installed.

## Installing what it needs

### Ubuntu 26.04

A fresh Ubuntu 26.04 desktop already has Cairo's library and the fonts
the desktop draws with. This installs the rest, with curl and git:

```sh
sudo apt install build-essential pkg-config libcairo2-dev libsdl3-0 curl git
```

Then install Lean by following
[lean-lang.org's install page](https://lean-lang.org/install/). Lean
Machine only needs elan, Lean's toolchain manager, from it: check that
`lake --version` works in a new terminal. The first build fetches Lean
4.36 itself, as `lean-toolchain` names it.

Other systems haven't been tried yet.

## Get the code

```sh
git clone https://github.com/dharmatech/lean-machine.git
cd lean-machine
```

## Build and run

```sh
lake build                 # writes .lake/build/bin/desktop
.lake/build/bin/desktop
```

`lake exe desktop` does both: it builds if anything changed, then runs
the desktop with any arguments that follow.

## Other ways to run

```sh
.lake/build/bin/desktop --test        # the pure world, driven by a script of events
.lake/build/bin/desktop --frames 20   # stops after 20 frames
.lake/build/bin/desktop --bench       # times Boids' step, at 150 to 1000 boids
SDL_VIDEO_DRIVER=dummy .lake/build/bin/desktop --frames 20   # the same, with no display
```

More on `--test`: [What `--test` checks](design/testing.md)
More on `--bench`: [How fast a step is](design/boids/step-speed.md)

Next: [Use](use/README.md)

[↑ Lean Machine](../README.md)
