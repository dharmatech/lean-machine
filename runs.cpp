// Stopping work on its own thread, with no change to Lean. A run has a stop
// flag. While the run's thread is inside `sv_guarded`, safepoints check the
// flag and throw a C++ exception, which `sv_guarded` catches at the run's
// edge. The safepoints are every small allocation (the linker sends Lean's
// `lean_alloc_small_object_core` through `__wrap_lean_alloc_small_object_core`
// here: `-Wl,--wrap=...` in lakefile.lean) and `poll` (LeanMachine/Busy.lean).
//
// Unwinding skips the Lean code it passes through, so what that code held is
// never freed, and a Lean `try`/`finally` doesn't run: this is a C++
// exception, not a Lean one. Compiled with the system's C++ compiler, linked
// with Lean's C++ runtime; nothing here uses the C++ library.
#include <lean/lean.h>
#include <stdlib.h>

struct Stopped {};

// The flag of the run this thread is in, while it's inside `sv_guarded`.
static thread_local __attribute__((tls_model("initial-exec")))
  int *t_flag = nullptr;

static inline void safepoint() {
  int *f = t_flag;
  if (f && __atomic_load_n(f, __ATOMIC_RELAXED)) {
    t_flag = nullptr;   // no second throw while unwinding
    throw Stopped{};
  }
}

extern "C" lean_object *__real_lean_alloc_small_object_core(unsigned sz);

extern "C" lean_object *__wrap_lean_alloc_small_object_core(unsigned sz) {
  safepoint();
  return __real_lean_alloc_small_object_core(sz);
}

extern "C" LEAN_EXPORT lean_obj_res sv_poll(lean_obj_arg x) {
  safepoint();
  return x;
}

/* A stop flag, as a Lean object. Lean frees it when nothing holds it: the
   loop's table and the run's task both do while the run lasts. */

static lean_external_class *flag_class = nullptr;
static void flag_finalize(void *p) { free(p); }
static void flag_foreach(void *, b_lean_obj_arg) {}
static int *flag_of(b_lean_obj_arg f) { return (int *)lean_get_external_data(f); }

// Called only by the loop, on one thread, so the class is registered once.
extern "C" LEAN_EXPORT lean_obj_res sv_flag_new(lean_obj_arg) {
  if (!flag_class)
    flag_class = lean_register_external_class(flag_finalize, flag_foreach);
  int *f = (int *)calloc(1, sizeof(int));
  return lean_io_result_mk_ok(lean_alloc_external(flag_class, f));
}

extern "C" LEAN_EXPORT lean_obj_res sv_flag_raise(b_lean_obj_arg f, lean_obj_arg) {
  __atomic_store_n(flag_of(f), 1, __ATOMIC_RELAXED);
  return lean_io_result_mk_ok(lean_box(0));
}

// `some (work ())`, or `none` if a safepoint found the flag raised first.
extern "C" LEAN_EXPORT lean_obj_res sv_guarded(b_lean_obj_arg f,
                                               lean_obj_arg work, lean_obj_arg) {
  int *prev = t_flag;
  t_flag = flag_of(f);
  try {
    lean_object *r = lean_apply_1(work, lean_box(0));
    t_flag = prev;
    lean_object *some = lean_alloc_ctor(1, 1, 0);
    lean_ctor_set(some, 0, r);
    return lean_io_result_mk_ok(some);
  } catch (Stopped &) {
    t_flag = prev;
    return lean_io_result_mk_ok(lean_box(0));
  }
}
