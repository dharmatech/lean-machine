# Exiting with a run going

Lean's `main` calls
`lean_finalize_task_manager` on its way out, but that doesn't wait for
dedicated threads: quitting with a `spin` going exits at once. The
loop raises every run's flag first anyway.

[↑ Runs, requests and threads](README.md)
