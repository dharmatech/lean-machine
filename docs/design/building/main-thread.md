# Lean's main thread

Lean 4.36 runs `main` on a thread of its own.
SDL wants its window and events on the process's main thread, and the
GTK plugin that draws a window's title bar on GNOME/Wayland won't start
anywhere else (`Failed to load plugin 'libdecor-gtk.so': failed to init`,
then no title bar). `LEAN_MAIN_USE_THREAD=0` keeps `main` on the main
thread; only `0` does, not `false` or `1`. `shim.c` sets it in a
constructor that runs before `main`.

[↑ Building and linking](README.md)
