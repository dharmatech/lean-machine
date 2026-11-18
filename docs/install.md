# Install and run

So far Lean Machine is only tested on Ubuntu 26.04.

## What it needs

Needs Lean 4.36 through elan (`lean-toolchain` pins it), Cairo, SDL3's
shared library, and a C++ compiler (`c++`). SDL3's headers
(`libsdl3-dev`) are not needed. The desktop reads the .olean files of
the Lean it was built with when it runs, so that toolchain must stay
installed.

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
SDL_VIDEO_DRIVER=dummy .lake/build/bin/desktop --frames 20   # the same, with no display
```

More on `--test`: [What `--test` checks](design/testing.md)

Next: [Use](use/README.md)

[↑ Lean Machine](../README.md)
