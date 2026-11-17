// Stopping work on its own thread, with no change to Lean. A run has a stop
// flag. While the run's thread is inside `sv_guarded` or `sv_guarded_io`,
// safepoints check the flag and throw a C++ exception, which the guard
// catches at the run's edge. The safepoints are every small allocation (the
// linker sends Lean's `lean_alloc_small_object_core` through
// `__wrap_lean_alloc_small_object_core` here: `-Wl,--wrap=...` in
// lakefile.lean) and `poll` (LeanMachine/Busy.lean). The guard also keeps
// the run's ambient (LeanMachine/Ambient.lean) for the thread: Lean has no
// thread-locals.
//
// Unwinding skips the Lean code it passes through, so what that code held is
// never freed, and a Lean `try`/`finally` doesn't run: this is a C++
// exception, not a Lean one. Compiled with the system's C++ compiler, linked
// with Lean's C++ runtime; nothing here uses the C++ library.
#include <lean/lean.h>
#include <stdlib.h>

struct Stopped {};

// The flag of the run this thread is in, while it's inside a guard.
static thread_local __attribute__((tls_model("initial-exec")))
  int *t_flag = nullptr;
// The run's ambient, borrowed from the guard's caller.
static thread_local lean_object *t_ambient = nullptr;

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

static lean_object *mk_some(lean_object *v) {
  lean_object *some = lean_alloc_ctor(1, 1, 0);
  lean_ctor_set(some, 0, v);
  return some;
}

// `f x` with the run's flag and ambient set for this thread; null if a
// safepoint found the flag raised first.
static lean_object *apply_guarded(b_lean_obj_arg flag, b_lean_obj_arg ambient,
                                  lean_obj_arg f, lean_obj_arg x) {
  int *prev = t_flag;
  lean_object *prev_ambient = t_ambient;
  t_flag = flag_of(flag);
  t_ambient = ambient;
  lean_object *r;
  try {
    r = lean_apply_1(f, x);
  } catch (Stopped &) {
    r = nullptr;
  }
  t_flag = prev;
  t_ambient = prev_ambient;
  return r;
}

// `some (work ())`, or `none` if a safepoint found the flag raised first.
extern "C" LEAN_EXPORT lean_obj_res sv_guarded(b_lean_obj_arg f,
                                               lean_obj_arg work, lean_obj_arg) {
  lean_object *r = apply_guarded(f, nullptr, work, lean_box(0));
  return lean_io_result_mk_ok(r ? mk_some(r) : lean_box(0));
}

// Runs the IO action `act` with `ambient` lent to it: `some` its value,
// `none` if it was stopped, or the error it threw.
extern "C" LEAN_EXPORT lean_obj_res sv_guarded_io(b_lean_obj_arg f,
    b_lean_obj_arg ambient, lean_obj_arg act, lean_obj_arg w) {
  lean_object *r = apply_guarded(f, ambient, act, w);
  if (!r) return lean_io_result_mk_ok(lean_box(0));
  if (!lean_io_result_is_ok(r)) return r;
  lean_object *v = lean_io_result_get_value(r);
  lean_inc(v);
  lean_dec(r);
  return lean_io_result_mk_ok(mk_some(v));
}

// The ambient of the run this thread is in: `some` it, or `none`.
extern "C" LEAN_EXPORT lean_obj_res sv_ambient(lean_obj_arg) {
  lean_object *a = t_ambient;
  if (!a) return lean_io_result_mk_ok(lean_box(0));
  lean_inc(a);
  return lean_io_result_mk_ok(mk_some(a));
}
