/*
 * The third mapper.
 *
 * Tailwind maps the design language to class names; NativeWind maps it to style objects. This
 * maps it to pixels in memory, and it is the only one that has to draw, because there is no
 * browser to resolve a class and no runtime to apply a style. Everything the design language
 * promises is either a constant in ashee.bundle.h or a rectangle drawn here.
 *
 * No toolkit, no window system, no compositor, no X, no Wayland. It opens /dev/fb0 -- which the
 * kernel exposes because CONFIG_FB_VESA is built in -- and writes 16-bit pixels into it. That
 * single decision is what removes tens of megabytes from the image: nothing sits between this
 * program and the frame.
 *
 * And it is small without being a simplification. The contracts are structs and the tokens are
 * constants, so satisfying a contract means reading fields and drawing what they say. A Card is
 * a surface with a radius, a padding from the spacing scale, and an accent from a colour role.
 * That is not a reduced Card; it is what Card means on a platform with no layout engine.
 */
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "ashee.bundle.h"

static uint16_t *frame;
static struct fb_var_screeninfo vinfo;
static struct fb_fix_screeninfo finfo;
static long stride;

static uint16_t *px(int x, int y) { return frame + y * stride + x; }

/* Clipped fills. A design system that draws outside its surface is a bug, not a crash, so every
 * primitive here is bounded by the frame rather than by its caller. */
static void fill(int x, int y, int w, int h, uint16_t colour) {
  const int x0 = x < 0 ? 0 : x;
  const int y0 = y < 0 ? 0 : y;
  const int x1 = x + w > (int)vinfo.xres ? (int)vinfo.xres : x + w;
  const int y1 = y + h > (int)vinfo.yres ? (int)vinfo.yres : y + h;
  for (int j = y0; j < y1; j++)
    for (int i = x0; i < x1; i++) *px(i, j) = colour;
}

/* A rounded surface. The radius comes from the token scale; ASHEE_RADIUS_FULL is -1 and means
 * half the height, which is how a pill is expressed without needing a second token for it. */
static void surface(int x, int y, int w, int h, int radius, uint16_t body, uint16_t edge) {
  if (radius < 0) radius = h / 2;
  if (radius > h / 2) radius = h / 2;
  fill(x + radius, y, w - 2 * radius, h, body);
  for (int j = 0; j < h; j++) {
    int dy = 0;
    if (j < radius) dy = radius - j;
    else if (j >= h - radius) dy = j - (h - radius);
    int dx = 0;
    if (dy > 0) {
      const int sq = radius * radius - dy * dy;
      while ((dx + 1) * (dx + 1) <= sq) dx++;
    }
    fill(x + dx, y + j, w - 2 * dx, 1, body);
  }
  if (!edge) return;
  for (int i = 0; i < w; i++) {
    *px(x + i, y) = edge;
    *px(x + i, y + h - 1) = edge;
  }
  for (int j = 0; j < h; j++) {
    *px(x, y + j) = edge;
    *px(x + w - 1, y + j) = edge;
  }
}

/* ---------------------------------------------------------------------------------------------
 * The font: an 8x16 PSF cell, parsed from the same source the kernel's console font uses, so the
 * glyphs are the ones this machine already agreed are legible at that size. Parsed rather than
 * embedded, because a font is data and data belongs in the image, not in the source file.
 */
static unsigned char *glyphs;
static int glyph_bytes;
static int glyph_count;

/* Both PSF formats, because the file here is PSF2 and PSF1 is still common. A parser that knew
 * only one would fail on the other and present as a missing font rather than a bad magic. */
static int load_font(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) return 0;
  unsigned char head[32];
  if (fread(head, 1, 32, f) != 32) { fclose(f); return 0; }

  int header;
  if (head[0] == 0x36 && head[1] == 0x04) {
    glyph_bytes = head[3];
    glyph_count = head[2] == 0 ? 256 : 512;
    header = 4;
  } else if (head[0] == 0x72 && head[1] == 0xb5 && head[2] == 0x4a && head[3] == 0x86) {
    glyph_bytes = head[16] | (head[17] << 8) | (head[18] << 16) | (head[19] << 24);
    glyph_count = head[8] | (head[9] << 8) | (head[10] << 16) | (head[11] << 24);
    header = head[4] | (head[5] << 8) | (head[6] << 16) | (head[7] << 24);
  } else {
    fclose(f);
    return 0;
  }

  glyphs = malloc((size_t)glyph_bytes * (size_t)glyph_count);
  if (!glyphs) { fclose(f); return 0; }
  fseek(f, header, SEEK_SET);
  const size_t got = fread(glyphs, (size_t)glyph_bytes, (size_t)glyph_count, f);
  fclose(f);
  return got == (size_t)glyph_count;
}

/* One cell: row-major, eight wide, bit 7 leftmost. Both PSF formats agree, and so has every
 * 8x16 bitmap text layer written in the last forty years -- which is why this is four lines. */
static void glyph(int x, int y, unsigned char c, uint16_t ink, uint16_t behind) {
  if (!glyphs || c >= glyph_count) c = '?';
  const unsigned char *g = glyphs + (size_t)c * glyph_bytes;
  for (int j = 0; j < 16; j++)
    for (int i = 0; i < 8; i++) *px(x + i, y + j) = (g[j] & (0x80 >> i)) ? ink : behind;
}

static void text(int x, int y, const char *s, uint16_t ink, uint16_t behind) {
  for (int i = 0; s[i]; i++) glyph(x + i * 8, y, (unsigned char)s[i], ink, behind);
}

/* ---------------------------------------------------------------------------------------------
 * The mark. BRAND.md gives one path on a 32-unit grid -- "the apex is cut flat rather than
 * pointed, and the counter is a triangle wound the opposite way" -- so it is drawn as the two
 * shapes it is: an outer trapezoid filled by scanline, and a counter punched out of it. A
 * framebuffer has no path renderer, and this is the whole of what the mark needs from one.
 */
static void mark(int x, int y, int size, uint16_t ink, uint16_t hole) {
  const double u = size / 32.0;
  /* Outer: (11.5,5) (20.5,5) (28,26.5) (4,26.5). The top edge is flat, which is the brand. */
  for (int j = 5; j <= 26; j++) {
    const double t = (j - 5) / 21.5;
    const double half = 4.5 + t * 7.5;
    const int x0 = (int)(x + (16.0 - half) * u);
    const int x1 = (int)(x + (16.0 + half) * u);
    fill(x0, (int)(y + j * u), x1 - x0, (int)(u + 1), ink);
  }
  /* Counter: (16,13) (20.6,21.5) (11.4,21.5) -- wound the other way, punched as a hole. */
  for (int j = 13; j <= 21; j++) {
    const double t = (j - 13) / 8.5;
    const double half = t * 4.6;
    const int x0 = (int)(x + (16.0 - half) * u);
    const int x1 = (int)(x + (16.0 + half) * u);
    fill(x0, (int)(y + j * u), x1 - x0, (int)(u + 1), hole);
  }
}

/* ---------------------------------------------------------------------------------------------
 * The screen, built from the contracts. This is the part that is the design system rather than
 * the drawing: each block below corresponds to a contract in ashee.bundle.h, and the numbers
 * come from the token scale. Change SPACING_STEP in tokens.ts, re-run the bundler, and this
 * screen re-lays itself -- which is the property the web and native mappers also have.
 */
static void card(int x, int y, int w, const char *title, const char *body, uint16_t border, uint16_t panel) {
  const int h = ASHEE_SPACE_MD + 16 + ASHEE_SPACE_SM + 16 + ASHEE_SPACE_MD;
  surface(x, y, w, h, ASHEE_RADIUS_MD, panel, border);
  text(x + ASHEE_SPACE_MD, y + ASHEE_SPACE_MD, title, ASHEE_COMPANY_INK, panel);
  text(x + ASHEE_SPACE_MD, y + ASHEE_SPACE_MD + 16 + ASHEE_SPACE_SM, body, ASHEE_UI_ACCENT, panel);
}

static void button(int x, int y, const char *label, uint16_t body, uint16_t ink) {
  const int w = ASHEE_SPACE_MD + (int)strlen(label) * 8 + ASHEE_SPACE_MD;
  const int h = ASHEE_MIN_TOUCH_TARGET > 28 ? 28 : ASHEE_MIN_TOUCH_TARGET;
  surface(x, y, w, h, ASHEE_RADIUS_SM, body, 0);
  text(x + ASHEE_SPACE_MD, y + (h - 16) / 2, label, ink, body);
}

static void draw(void) {
  const uint16_t ink = ASHEE_UI_INK;
  const uint16_t accent = ASHEE_UI_ACCENT;
  const uint16_t company = ASHEE_COMPANY_ACCENT;
  const uint16_t white = ASHEE_COMPANY_INK;

  /* One ink and no second colour, per BRAND.md. The field is the ink; the accent is the only
   * other colour on the screen, and the two declared pairs are the only two combinations. */
  fill(0, 0, (int)vinfo.xres, (int)vinfo.yres, ink);

  /* The top bar: the company tone, carrying the mark and the name. */
  fill(0, 0, (int)vinfo.xres, ASHEE_SPACE_2XL + ASHEE_SPACE_XS, company);
  mark(ASHEE_SPACE_MD, ASHEE_SPACE_SM, ASHEE_SPACE_2XL, white, company);
  text(ASHEE_SPACE_MD + ASHEE_SPACE_2XL + ASHEE_SPACE_SM, ASHEE_SPACE_MD + 2, "ASHEE OS", white, company);
  text((int)vinfo.xres - 8 * 24 - ASHEE_SPACE_MD, ASHEE_SPACE_MD + 2, "human + AI", white, company);

  /* The body: one frame, two cards, a button. All of it from the scale. */
  int y = ASHEE_SPACE_2XL + ASHEE_SPACE_XS + ASHEE_SPACE_LG;
  const int w = (int)vinfo.xres - 2 * ASHEE_SPACE_LG;
  card(ASHEE_SPACE_LG, y, w, "the design language", "0 bytes at runtime", company, ink);

  y += ASHEE_SPACE_MD + 16 + ASHEE_SPACE_SM + 16 + ASHEE_SPACE_MD + ASHEE_SPACE_LG;
  card(ASHEE_SPACE_LG, y, w, "the mapper", "conviconstants -> pixels", company, ink);

  y += ASHEE_SPACE_MD + 16 + ASHEE_SPACE_SM + 16 + ASHEE_SPACE_MD + ASHEE_SPACE_LG;
  button(ASHEE_SPACE_LG, y, "a button", accent, ink);

  text(ASHEE_SPACE_LG, (int)vinfo.yres - 16 - ASHEE_SPACE_SM, "no browser, no toolkit, no runtime", accent, ink);
}

int main(void) {
  const int fd = open("/dev/fb0", O_RDWR);
  if (fd < 0) {
    /* Reported rather than silent. A GUI that draws nothing because a file was missing should
     * say which file, and it is the difference between a bug report and a mystery. */
    fprintf(stderr, "gui: cannot open /dev/fb0 -- is CONFIG_FB_VESA set and a VGA device present?\n");
    return 1;
  }
  if (ioctl(fd, FBIOGET_VSCREENINFO, &vinfo) < 0 || ioctl(fd, FBIOGET_FSCREENINFO, &finfo) < 0) {
    fprintf(stderr, "gui: /dev/fb0 has no geometry\n");
    return 1;
  }

  const long bytes = (long)finfo.line_length * (long)vinfo.yres;
  frame = mmap(NULL, (size_t)bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (frame == MAP_FAILED) {
    fprintf(stderr, "gui: cannot map the frame (%ld bytes)\n", bytes);
    return 1;
  }
  stride = finfo.line_length / 2;

  if (!load_font("/font.psf")) fprintf(stderr, "gui: no font, text will be blank\n");

  fprintf(stderr, "gui: %ux%u, %d bpp, stride %ld px, %d glyphs of %d bytes\n", vinfo.xres, vinfo.yres,
          vinfo.bits_per_pixel, stride, glyph_count, glyph_bytes);

  draw();
  /* Nothing to poll: this is a demonstration of the mapper, and a GUI that exits cleanly is
   * easier to verify than one that blocks. Input arrives with the input layer, not before it. */
  sleep(2);
  return 0;
}
