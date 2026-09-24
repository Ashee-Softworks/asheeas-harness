/**
 * The Ashee OS Project -- build configuration.
 *
 * Read by `tools/build.mjs`. The shape is deliberate and it is the Vite shape: a design system
 * to resolve, an entry to bundle, a target to emit for, and a plugin per kind of module.
 *
 * `design` is the platform-neutral layer, taken from the AsheeUI repository rather than copied
 * into this one. Copying it would be the drift decision 0003 forbids -- "two sources of one
 * palette drift" -- so this reads it where it lives and fails if it is not there.
 *
 * `target` is not a browser, and that is the point. A browser target means React, a CSS engine
 * and a JS runtime; this target means a region of memory and an 8x16 glyph. The design language
 * is identical either way, because AsheeUI's shared layer "depends on nothing".
 */
export default {
  name: "ashee-os",

  /**
   * Where AsheeUI lives on this machine. Overridable with ASHEE_UI=/path.
   *
   * The default is assembled from `$HOME` rather than written as an absolute path. It resolves to
   * the same directory before and after; what changed is that this published file no longer carries
   * the account name of the machine it was written on. That matters twice: `leak-audit.sh`
   * question 5 exists for exactly this, and a stranger who clones the repository cannot use a path
   * that names somebody else's home directory.
   */
  designRoot:
    process.env.ASHEE_UI ??
    `${process.env.HOME}/Documents/Ashee-Softworks/AsheeUI/ashee-ui/packages/shared/src`,

  /** The palette's declared source of truth, per BRAND.md. Overridable with ASHEE_BRAND=/path. */
  brand:
    process.env.ASHEE_BRAND ??
    `${process.env.HOME}/Documents/Ashee-Softworks/my_new_folder/brand/BRAND.md`,

  /**
   * The platform-neutral layer, in dependency order. Each is transformed by the plugin whose
   * `accepts` matches it; a module no plugin accepts is REPORTED, never skipped.
   */
  design: ["tokens.ts", "contracts.ts", "cascade.ts", "matrix.ts"],

  /** The screen, written against the contracts. Absent today, and reported rather than ignored. */
  entry: "gui/screen.ui.ts",

  /** One header, because the consumer is a C compiler. */
  out: "gui/ashee.bundle.h",

  target: {
    /** The framebuffer's pixel: 5 red, 6 green, 5 blue. */
    pixel: "rgb565",
    /** An 8x16 bitmap font cell -- the only typography scale a bitmap font can express. */
    cell: { w: 8, h: 16 },
    /** Tailwind's spacing step at a 16px root. */
    pxPerStep: 4,
  },
};
