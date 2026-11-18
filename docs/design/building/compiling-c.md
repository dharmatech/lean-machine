# Compiling C

`leanc`'s bundled clang has no system headers
(`math.h`), so the lakefile compiles `shim.c` with the system `cc`.

[↑ Building and linking](README.md)
