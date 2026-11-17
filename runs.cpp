// Stopping work on its own thread, with no change to Lean. A run has a stop
// flag. While the run's thread is inside `sv_guarded` or `sv_guarded_io`,
// safepoints look at the flag. Once it's raised, a stop goes two ways:
//
// - Offered: the safepoint at the start of an IO function compiled in the
//   REPL's Lean (`sv_interrupt_now`, put there by LeanMachine/Eval.lean)
//   makes that function return `IO.Error.interrupted`. Lean code sees it as
//   an error, so its `try`/`catch`/`finally` run, and the run ends the usual
//   way. Lean's elaborator is interrupted through its own cancel token
//   (LeanMachine/Runs.lean), which is the same idea.
// - Cut off: any safepoint throws a C++ exception, which the guard catches
//   at the run's edge. Unwinding skips the Lean code it passes through, so
//   what that code held is never freed, and no `finally` runs. A safepoint
//   cuts a run off at once if it can't take an offer (a pure run), 50 ms
//   after the stop if no IO function took the offer, or 500 ms after one
//   did, if the run is still going (it caught the error and went on).
//
// The safepoints are every small allocation (the linker sends Lean's
// `lean_alloc_small_object_core` through `__wrap_lean_alloc_small_object_core`
// here: `-Wl,--wrap=...` in lakefile.lean), `poll`, the safepoints the REPL's
// Lean puts in what it compiles, and the end of a masked region.
//
// Masking: a run isn't cut off between `Ref.take` and `Ref.put` (how
// `IO.Ref.modify` works: a ref left taken makes every other thread that
// reads it spin forever), nor while it holds a mutex (which would stay
// locked). The linker sends those primitives through wrappers here that
// count, per thread; a stop that comes meanwhile waits for the region's end.
//
// `IO.sleep` ends early once its run is asked to stop, so a run that sleeps
// reaches its next safepoint.
//
// The guard also keeps the run's ambient (LeanMachine/Ambient.lean) for the
// thread: Lean has no thread-locals. Compiled with the system's C++
// compiler, linked with Lean's C++ runtime; nothing here uses the C++
// library.
#include <lean/lean.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

struct Stopped {};

enum : int { RUNNING = 0, ASKED = 1, DELIVERED = 2 };

struct Flag {
  int state;              // RUNNING, then ASKED (by the loop), then DELIVERED
  uint64_t asked_ns;      // when the stop was asked for; written before state
  uint64_t delivered_ns;  // when an IO function took it as interrupted
  bool finishing;         // the run's own code is wrapping up: no cutting off
};

static const uint64_t OFFER_NS = 50 * 1000000ull;
static const uint64_t GRACE_NS = 500 * 1000000ull;

// The flag of the run this thread is in, while it's inside a guard.
static thread_local __attribute__((tls_model("initial-exec")))
  Flag *t_flag = nullptr;
static thread_local bool t_offers = false;  // the run is IO: a stop is offered first
static thread_local int t_refs = 0;         // refs taken and not yet put back
static thread_local int t_locks = 0;        // mutexes held
// The run's ambient, borrowed from the guard's caller.
static thread_local lean_object *t_ambient = nullptr;
// Off only to show, in --test, what masking prevents.
static bool g_masking = true;

static uint64_t now_ns() {
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

[[noreturn]] static void cut_off() {
  t_flag = nullptr;   // no second throw while unwinding
  throw Stopped{};
}

// A safepoint once the run has been asked to stop: cut it off, unless it's
// masked, wrapping up, or still within the offer or the grace.
__attribute__((noinline, cold)) static void stop_here(Flag *f) {
  if (f->finishing) return;
  if (g_masking && (t_refs > 0 || t_locks > 0)) return;
  int s = __atomic_load_n(&f->state, __ATOMIC_ACQUIRE);
  uint64_t now = now_ns();
  if (s == ASKED && (!t_offers || now - f->asked_ns >= OFFER_NS)) cut_off();
  if (s == DELIVERED && now - f->delivered_ns >= GRACE_NS) cut_off();
}

static inline void safepoint() {
  Flag *f = t_flag;
  if (f && __atomic_load_n(&f->state, __ATOMIC_RELAXED)) stop_here(f);
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

extern "C" LEAN_EXPORT uint8_t sv_safepoint(uint8_t x) {
  safepoint();
  return x;
}

// At the start of an IO function compiled in the REPL: 1 if this function
// is to return `IO.Error.interrupted`, which it is the first time one is
// reached after a stop (unless a ref is taken); otherwise a safepoint.
extern "C" LEAN_EXPORT uint8_t sv_interrupt_now(uint8_t) {
  Flag *f = t_flag;
  if (!f || !__atomic_load_n(&f->state, __ATOMIC_RELAXED)) return 0;
  if (t_offers && !f->finishing && !(g_masking && t_refs > 0) &&
      __atomic_load_n(&f->state, __ATOMIC_ACQUIRE) == ASKED) {
    f->delivered_ns = now_ns();
    __atomic_store_n(&f->state, DELIVERED, __ATOMIC_RELEASE);
    return 1;
  }
  stop_here(f);
  return 0;
}

// The run's own code is wrapping up after Lean saw the stop: no safepoint
// cuts it off from here on.
extern "C" LEAN_EXPORT lean_obj_res sv_finishing() {
  if (t_flag) t_flag->finishing = true;
  return lean_io_result_mk_ok(lean_box(0));
}

/* Masked regions. Each wrapper counts on the calling thread; leaving the
   region is a safepoint, so a stop that waited is taken there. */

extern "C" lean_object *__real_lean_st_ref_take(lean_object *r);
extern "C" lean_object *__wrap_lean_st_ref_take(lean_object *r) {
  t_refs++;
  return __real_lean_st_ref_take(r);
}

extern "C" lean_object *__real_lean_st_ref_put(lean_object *r, lean_object *a);
extern "C" lean_object *__wrap_lean_st_ref_put(lean_object *r, lean_object *a) {
  lean_object *res = __real_lean_st_ref_put(r, a);
  if (t_refs > 0) t_refs--;
  safepoint();
  return res;
}

#define LOCK(name)                                                        \
  extern "C" lean_object *__real_##name(lean_object *m);                  \
  extern "C" lean_object *__wrap_##name(lean_object *m) {                 \
    t_locks++;                                                            \
    return __real_##name(m);                                              \
  }
#define TRY_LOCK(name)                                                    \
  extern "C" uint8_t __real_##name(lean_object *m);                       \
  extern "C" uint8_t __wrap_##name(lean_object *m) {                      \
    uint8_t ok = __real_##name(m);                                        \
    if (ok) t_locks++;                                                    \
    return ok;                                                            \
  }
#define UNLOCK(name)                                                      \
  extern "C" lean_object *__real_##name(lean_object *m);                  \
  extern "C" lean_object *__wrap_##name(lean_object *m) {                 \
    lean_object *res = __real_##name(m);                                  \
    if (t_locks > 0) t_locks--;                                           \
    safepoint();                                                          \
    return res;                                                           \
  }

LOCK(lean_io_basemutex_lock)
TRY_LOCK(lean_io_basemutex_try_lock)
UNLOCK(lean_io_basemutex_unlock)
LOCK(lean_io_baserecmutex_lock)
TRY_LOCK(lean_io_baserecmutex_try_lock)
UNLOCK(lean_io_baserecmutex_unlock)
LOCK(lean_io_basesharedmutex_write)
TRY_LOCK(lean_io_basesharedmutex_try_write)
UNLOCK(lean_io_basesharedmutex_unlock_write)
LOCK(lean_io_basesharedmutex_read)
TRY_LOCK(lean_io_basesharedmutex_try_read)
UNLOCK(lean_io_basesharedmutex_unlock_read)

// `IO.sleep`: in slices, ending once the run is asked to stop.
extern "C" lean_object *__real_lean_dbg_sleep(uint32_t ms, lean_object *fn);
extern "C" lean_object *__wrap_lean_dbg_sleep(uint32_t ms, lean_object *fn) {
  Flag *f = t_flag;
  if (!f) return __real_lean_dbg_sleep(ms, fn);
  uint64_t end = now_ns() + (uint64_t)ms * 1000000ull;
  while (!__atomic_load_n(&f->state, __ATOMIC_ACQUIRE)) {
    uint64_t now = now_ns();
    if (now >= end) break;
    uint64_t left = end - now, slice = left < 5000000ull ? left : 5000000ull;
    timespec ts = {0, (long)slice};
    nanosleep(&ts, nullptr);
  }
  return __real_lean_dbg_sleep(0, fn);
}

/* A stop flag, as a Lean object. Lean frees it when nothing holds it: the
   loop's table and the run's task both do while the run lasts. */

static lean_external_class *flag_class = nullptr;
static void flag_finalize(void *p) { free(p); }
static void flag_foreach(void *, b_lean_obj_arg) {}
static Flag *flag_of(b_lean_obj_arg f) { return (Flag *)lean_get_external_data(f); }

// Called only by the loop, on one thread, so the class is registered once.
extern "C" LEAN_EXPORT lean_obj_res sv_flag_new() {
  if (!flag_class)
    flag_class = lean_register_external_class(flag_finalize, flag_foreach);
  Flag *f = (Flag *)calloc(1, sizeof(Flag));
  return lean_io_result_mk_ok(lean_alloc_external(flag_class, f));
}

// Only the loop raises flags, so only it moves a flag from RUNNING.
extern "C" LEAN_EXPORT lean_obj_res sv_flag_raise(b_lean_obj_arg f) {
  Flag *p = flag_of(f);
  if (__atomic_load_n(&p->state, __ATOMIC_ACQUIRE) == RUNNING) {
    p->asked_ns = now_ns();
    __atomic_store_n(&p->state, ASKED, __ATOMIC_RELEASE);
  }
  return lean_io_result_mk_ok(lean_box(0));
}

static lean_object *mk_some(lean_object *v) {
  lean_object *some = lean_alloc_ctor(1, 1, 0);
  lean_ctor_set(some, 0, v);
  return some;
}

// `f ()` with the run's flag and ambient set for this thread; null if a
// safepoint cut it off.
static lean_object *apply_guarded(b_lean_obj_arg flag, b_lean_obj_arg ambient,
                                  bool offers, lean_obj_arg f) {
  Flag *prev = t_flag;
  lean_object *prev_ambient = t_ambient;
  bool prev_offers = t_offers;
  int prev_refs = t_refs, prev_locks = t_locks;
  t_flag = flag_of(flag);
  t_ambient = ambient;
  t_offers = offers;
  t_refs = t_locks = 0;
  lean_object *r;
  try {
    r = lean_apply_1(f, lean_box(0));
  } catch (Stopped &) {
    r = nullptr;
  }
  t_flag = prev;
  t_ambient = prev_ambient;
  t_offers = prev_offers;
  t_refs = prev_refs;
  t_locks = prev_locks;
  return r;
}

// `some (work ())`, or `none` if a safepoint cut it off. Pure work can't
// take a stop as an error, so it isn't offered one.
extern "C" LEAN_EXPORT lean_obj_res sv_guarded(b_lean_obj_arg f, lean_obj_arg work) {
  lean_object *r = apply_guarded(f, nullptr, false, work);
  return lean_io_result_mk_ok(r ? mk_some(r) : lean_box(0));
}

// Runs the IO action `act` with `ambient` lent to it: `some` its value,
// `none` if a safepoint cut it off, or the error it threw.
extern "C" LEAN_EXPORT lean_obj_res sv_guarded_io(b_lean_obj_arg f,
    b_lean_obj_arg ambient, lean_obj_arg act) {
  lean_object *r = apply_guarded(f, ambient, true, act);
  if (!r) return lean_io_result_mk_ok(lean_box(0));
  if (!lean_io_result_is_ok(r)) return r;
  lean_object *v = lean_io_result_get_value(r);
  lean_inc(v);
  lean_dec(r);
  return lean_io_result_mk_ok(mk_some(v));
}

// The ambient of the run this thread is in: `some` it, or `none`.
extern "C" LEAN_EXPORT lean_obj_res sv_ambient() {
  lean_object *a = t_ambient;
  if (!a) return lean_io_result_mk_ok(lean_box(0));
  lean_inc(a);
  return lean_io_result_mk_ok(mk_some(a));
}

/* For --test: what masking prevents. */

extern "C" LEAN_EXPORT lean_obj_res sv_set_masking(uint8_t on) {
  g_masking = on;
  return lean_io_result_mk_ok(lean_box(0));
}

// Is the ref taken: emptied by `Ref.take`, and not yet put back? Reading
// it with `get` would wait for ever.
extern "C" LEAN_EXPORT lean_obj_res sv_ref_taken(b_lean_obj_arg r) {
  bool taken = __atomic_load_n(&lean_to_ref(r)->m_value, __ATOMIC_ACQUIRE) == nullptr;
  return lean_io_result_mk_ok(lean_box(taken));
}
