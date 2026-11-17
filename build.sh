#!/bin/sh
# Builds ./desktop. Needs Lean (elan), Cairo and SDL3's shared library;
# SDL3's headers aren't needed.
set -e
cd "$(dirname "$0")"
P=$(lean --print-prefix)
LIB=$(pkg-config --variable=libdir cairo)
lean Main.lean -c Main.c
"$P/bin/leanc" -O2 -c Main.c -o Main.o
cc -O2 -fPIC -I"$P/include" $(pkg-config --cflags cairo) -c shim.c -o shim.o
# Lean links against its own C runtime: name the system libraries by path
# (an -L to their directory would pull in the system's start files).
"$P/bin/leanc" Main.o shim.o -o desktop \
  "$LIB/libcairo.so.2" "$LIB/libSDL3.so.0" -Wl,--allow-shlib-undefined
