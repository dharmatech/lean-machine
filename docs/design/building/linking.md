# Linking

Lean's toolchain links against its own C library. Name a
system library by path with `-Wl,--allow-shlib-undefined`; an `-L` to
`/usr/lib/x86_64-linux-gnu` pulls in the system's start files and fails.
That C library is old: no `gettid` (use `syscall(SYS_gettid)`).

[↑ Building and linking](README.md)
