// The only C: a Cairo canvas, and one SDL3 host window that shows it and
// hands back events. SDL3's headers aren't installed, so the few calls and
// event offsets used are declared here (the same offsets Schevana v0 reads).
#include <lean/lean.h>
#include <cairo.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>

// Lean runs `main` on a thread of its own unless told not to. SDL wants its
// window and events on the process's main thread, and the GTK plugin that
// draws a Wayland window's title bar won't start anywhere else. This runs
// before main and leaves an explicit setting alone.
__attribute__((constructor)) static void keep_main_thread(void) {
  setenv("LEAN_MAIN_USE_THREAD", "0", 0);
}

/* ---------------------------------------------------------------- Cairo */

static lean_external_class *canvas_class = NULL;
static void canvas_finalize(void *p) { cairo_destroy((cairo_t *)p); }
static void canvas_foreach(void *p, b_lean_obj_arg f) {}
static cairo_t *cr_of(b_lean_obj_arg c) { return lean_get_external_data(c); }
static lean_obj_res unit(void) { return lean_io_result_mk_ok(lean_box(0)); }

static void set_rgb(cairo_t *cr, uint32_t rgb) {
  cairo_set_source_rgb(cr, ((rgb >> 16) & 255) / 255.0,
                       ((rgb >> 8) & 255) / 255.0, (rgb & 255) / 255.0);
}

LEAN_EXPORT lean_obj_res sv_canvas_new(uint32_t w, uint32_t h, lean_obj_arg io) {
  if (!canvas_class)
    canvas_class = lean_register_external_class(canvas_finalize, canvas_foreach);
  cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
  cairo_t *cr = cairo_create(s);
  cairo_surface_destroy(s);   // the context keeps it
  return lean_io_result_mk_ok(lean_alloc_external(canvas_class, cr));
}

LEAN_EXPORT lean_obj_res sv_fill_rect(b_lean_obj_arg c, double x, double y,
    double w, double h, double r, uint32_t rgb, lean_obj_arg io) {
  cairo_t *cr = cr_of(c);
  cairo_new_sub_path(cr);
  cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
  cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
  cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
  cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
  cairo_close_path(cr);
  set_rgb(cr, rgb);
  cairo_fill(cr);
  return unit();
}

LEAN_EXPORT lean_obj_res sv_text(b_lean_obj_arg c, double x, double y,
    double size, uint32_t rgb, b_lean_obj_arg s, lean_obj_arg io) {
  cairo_t *cr = cr_of(c);
  cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL,
                         CAIRO_FONT_WEIGHT_BOLD);
  cairo_set_font_size(cr, size);
  set_rgb(cr, rgb);
  cairo_move_to(cr, x, y);
  cairo_show_text(cr, lean_string_cstr(s));
  return unit();
}

LEAN_EXPORT lean_obj_res sv_save_png(b_lean_obj_arg c, b_lean_obj_arg path,
                                     lean_obj_arg io) {
  cairo_surface_write_to_png(cairo_get_target(cr_of(c)), lean_string_cstr(path));
  return unit();
}

/* ----------------------------------------------------------------- SDL3 */

typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef struct SDL_Texture SDL_Texture;
extern bool SDL_Init(uint32_t flags);
extern SDL_Window *SDL_CreateWindow(const char *title, int w, int h,
                                    uint64_t flags);
extern SDL_Renderer *SDL_CreateRenderer(SDL_Window *win, const char *name);
extern SDL_Texture *SDL_CreateTexture(SDL_Renderer *r, uint32_t format,
                                      int access, int w, int h);
extern bool SDL_UpdateTexture(SDL_Texture *t, const void *rect,
                              const void *pixels, int pitch);
extern bool SDL_RenderTexture(SDL_Renderer *r, SDL_Texture *t,
                              const void *src, const void *dst);
extern bool SDL_RenderPresent(SDL_Renderer *r);
extern bool SDL_WaitEventTimeout(void *event, int32_t ms);
extern bool SDL_PollEvent(void *event);
extern const char *SDL_GetError(void);

#define SDL_INIT_VIDEO 0x20u
#define SDL_PIXELFORMAT_ARGB8888 0x16362004u   // Cairo's ARGB32, same bytes
#define SDL_TEXTUREACCESS_STREAMING 1

static SDL_Renderer *host_renderer = NULL;
static SDL_Texture *host_texture = NULL;

static lean_obj_res sdl_error(void) {
  return lean_io_result_mk_error(
    lean_mk_io_user_error(lean_mk_string(SDL_GetError())));
}

LEAN_EXPORT lean_obj_res sv_host_open(b_lean_obj_arg title, uint32_t w,
                                      uint32_t h, lean_obj_arg io) {
  if (!SDL_Init(SDL_INIT_VIDEO)) return sdl_error();
  SDL_Window *win = SDL_CreateWindow(lean_string_cstr(title), w, h, 0);
  if (!win) return sdl_error();
  host_renderer = SDL_CreateRenderer(win, NULL);
  if (!host_renderer) return sdl_error();
  host_texture = SDL_CreateTexture(host_renderer, SDL_PIXELFORMAT_ARGB8888,
                                   SDL_TEXTUREACCESS_STREAMING, w, h);
  if (!host_texture) return sdl_error();
  return unit();
}

LEAN_EXPORT lean_obj_res sv_host_present(b_lean_obj_arg c, lean_obj_arg io) {
  cairo_surface_t *s = cairo_get_target(cr_of(c));
  cairo_surface_flush(s);
  SDL_UpdateTexture(host_texture, NULL, cairo_image_surface_get_data(s),
                    cairo_image_surface_get_stride(s));
  SDL_RenderTexture(host_renderer, host_texture, NULL, NULL);
  SDL_RenderPresent(host_renderer);
  return unit();
}

static lean_obj_res event4(double kind, double a, double b, double c) {
  lean_object *arr = lean_alloc_sarray(sizeof(double), 4, 4);
  double *p = lean_float_array_cptr(arr);
  p[0] = kind; p[1] = a; p[2] = b; p[3] = c;
  return lean_io_result_mk_ok(arr);
}

static float f32_at(const uint8_t *e, int i) { float f; memcpy(&f, e + i, 4); return f; }
static uint32_t u32_at(const uint8_t *e, int i) { uint32_t u; memcpy(&u, e + i, 4); return u; }

// The next event as [kind, a, b, c]; kind 0 is "none before the timeout".
// A timeout of 0 only polls.
LEAN_EXPORT lean_obj_res sv_host_event(uint32_t timeout, lean_obj_arg io) {
  uint64_t buf[16];             // SDL_Event is a 128-byte union
  uint8_t *e = (uint8_t *)buf;
  for (;;) {
    bool got = timeout ? SDL_WaitEventTimeout(e, (int32_t)timeout)
                       : SDL_PollEvent(e);
    if (!got) return event4(0, 0, 0, 0);
    switch (u32_at(e, 0)) {
      case 0x100: return event4(1, 0, 0, 0);                         // quit
      case 0x401: return event4(2, f32_at(e, 28), f32_at(e, 32), e[24]); // press
      case 0x402: return event4(3, f32_at(e, 28), f32_at(e, 32), e[24]); // release
      case 0x400: return event4(4, f32_at(e, 28), f32_at(e, 32), 0);  // motion
      case 0x300: return event4(5, u32_at(e, 28), 0, 0);             // key
      default: continue;
    }
  }
}
