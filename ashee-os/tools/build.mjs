#!/usr/bin/env node
/**
 * The Ashee UI bundler -- `vite build` for a design system whose output is C.
 *
 * Vite resolves an entry, transforms each module by kind, and emits a bundle for a browser. This
 * resolves an entry, transforms each module of the platform-neutral layer by kind, and emits a
 * bundle for a framebuffer. The plugins below are the transform hooks, `design` is the module
 * graph, `out` is the emitted chunk.
 *
 * What Vite has that this deliberately does not: a dev server and HMR. Not because they are hard
 * to imagine here, but because a better one exists -- the machine reboots the whole operating
 * system in 1.7 seconds. There is nothing worth hot-swapping when a cold start is that cheap,
 * and inventing a mechanism for it would be inventing a slower one.
 *
 * The rule that matters more: **a module no plugin accepts is REPORTED, not skipped.** Every
 * failure in this project's recent history had that shape -- a check that omitted something
 * silently and printed a complete-looking result. So each module prints what it extracted or why
 * it could not, and the build exits non-zero if anything went unhandled.
 */
import { readFileSync, writeFileSync, existsSync, mkdirSync, watch } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const root = resolve(new URL(".", import.meta.url).pathname, "..");
const config = (await import(pathToFileURL(join(root, "ashee.config.mjs")).href)).default;

const doWatch = process.argv.slice(2).includes("--watch");
const colour = (c, s) => (process.stdout.isTTY ? `\x1b[${c}m${s}\x1b[0m` : s);
const bold = (s) => colour("1", s);
const dim = (s) => colour("2", s);
const ok = (s) => colour("32", s);
const bad = (s) => colour("31", s);

// --- the plugins: what it accepts, how it reads it, how it emits C ----------------------------

const plugins = [
  {
    name: "tokens",
    accepts: (file) => file === "tokens.ts",
    transform(source) {
      const output = [];
      const refused = [];
      const lines = source.split("\n");
      for (let i = 0; i < lines.length; i += 1) {
        const open = lines[i].match(/^export const ([A-Z0-9_]+) = \{$/);
        if (open) {
          const entries = [];
          let j = i + 1;
          for (; j < lines.length && !/^\} as const;/.test(lines[j]); j += 1) {
            const pair = lines[j].match(/^\s*"?([^":]+)"?:\s*([^,]+),\s*$/);
            if (pair) entries.push([pair[1], pair[2].trim()]);
            else if (lines[j].trim() !== "") refused.push(`${j + 1}: ${lines[j].trim()}`);
          }
          output.push({ kind: "map", name: open[1], entries });
          i = j;
          continue;
        }
        const scalar = lines[i].match(/^export const ([A-Z0-9_]+) = (\d+);$/);
        if (scalar) output.push({ kind: "scalar", name: scalar[1], value: Number(scalar[2]) });
      }
      return { output, refused };
    },
    emit(output, target, emit) {
      emit("/* --- tokens: the design language's vocabulary --- */");
      const PX_RADIUS = { none: 0, xs: 2, sm: 4, md: 6, lg: 8, xl: 12, full: -1 };
      const PX_FONT = { xs: 8, sm: 12, md: 16, lg: 20, xl: 24, "2xl": 32, "3xl": 40 };

      /* Two shapes, and the distinction is the whole fix.
       *
       * A map of NUMBERS is a measurement, and a measurement becomes a constant: spacing in
       * pixels, a breakpoint width, an elevation level.
       *
       * A map of NAMES is vocabulary -- `solid`, `bordered`, `primary`, `semibold`. Those are
       * not values to convert, they are words to keep, and every language can hold a word. This
       * bundler threw on FONT_WEIGHT_STEP because it only knew how to make numbers, and the
       * throw blocked the whole token set. It was the wrong error: four weight *names* are
       * perfectly expressible here. Whether a platform can *render* four weights is the
       * mapper's business and is recorded in ashee.matrix, not decided by the emitter.
       */
      /* Hoisted out of the loop below: the pixel pass further down uses it too, and a helper
       * scoped to one loop is a helper that vanishes at the line you need it. That is the
       * "key is not defined" this build failed with on its first run. */
      const key = (k) => k.replace(/\W/g, "").toUpperCase();

      for (const decl of output) {
        if (decl.kind === "scalar") {
          emit(`#define ASHEE_${decl.name} ${decl.value}`);
          continue;
        }

        const prefix = decl.name.replace(/_STEP$/, "");
        const numeric = decl.entries.every(([, v]) => /^-?\d+$/.test(v));

        if (numeric) {
          for (const [k, v] of decl.entries) emit(`#define ASHEE_${prefix}_${key(k)} ${v}`);
          continue;
        }

        /* RADIUS and FONT_SIZE are name-maps that resolve to pixels below, so they are values
         * here rather than vocabulary. Emitting an enum for them too would declare
         * ASHEE_RADIUS_MD as an enumerator and then redefine it as a number -- two names for
         * one thing, which is the drift this whole exercise keeps finding. */
        if (prefix === "RADIUS" || prefix === "FONT_SIZE") continue;

        emit(`typedef enum ashee_${prefix.toLowerCase()}_t {`);
        emit(`  ${decl.entries.map(([k]) => `ASHEE_${prefix}_${key(k)}`).join(", ")}`);
        emit(`} ashee_${prefix.toLowerCase()}_t;`);
      }

      /* The measurements a platform has to resolve into its own unit. Spacing is the shared
       * vocabulary -- "step 4", not "1rem" or "16dp" -- so this is where a step becomes pixels,
       * and the mapper is the only thing that knows how many pixels a step is worth here. */
      emit("");
      emit("/* Resolved for this target: steps to pixels, radii and type sizes to pixels. */");
      const spacing = output.find((d) => d.name === "SPACING_STEP");
      for (const [k, v] of spacing?.entries ?? []) {
        emit(`#define ASHEE_SPACE_${key(k)} ${Number(v) * target.pxPerStep}`);
      }
      const radii = output.find((d) => d.name === "RADIUS_STEP");
      for (const [k] of radii?.entries ?? []) emit(`#define ASHEE_RADIUS_${key(k)} ${PX_RADIUS[k] ?? 0}`);
      const fonts = output.find((d) => d.name === "FONT_SIZE_STEP");
      for (const [k] of fonts?.entries ?? []) emit(`#define ASHEE_FONT_${key(k)} ${PX_FONT[k] ?? 16}`);

      /* What this platform cannot express, stated rather than discovered later. FONT_WEIGHT
       * resolves to a single weight here; the mapper ignores the value and every weight draws
       * the same. That is "nearest equivalent" per contracts.ts, and it belongs on the record. */
      emit("");
      emit("/* NOT EXPRESSIBLE HERE: FONT_WEIGHT declares " +
        (output.find((d) => d.name === "FONT_WEIGHT_STEP")?.entries.length ?? 0) +
        " weights; this target renders 1. Every weight selects it. See ashee.matrix. */");

      return `${output.length} declarations`;
    },
  },
  {
    name: "contracts",
    accepts: (file) => file === "contracts.ts",
    transform(source) {
      const output = [];
      const re = /export interface (\w+)Contract(?: extends (\w+)Contract)? \{([\s\S]*?)\n\}/g;
      for (const m of source.matchAll(re)) {
        const props = [];
        for (const p of m[3].matchAll(/^\s*\/\*\*[\s\S]*?\*\/\s*(\w+)\??:\s*([\s\S]*?);/gm)) {
          props.push({ name: p[1], type: p[2].trim().replace(/\s+/g, " ") });
        }
        output.push({ name: m[1], extends: m[2] ?? null, props });
      }
      return { output, refused: [] };
    },
    emit(output, target, emit) {
      emit("/* --- contracts: what each component promises, which both platforms already agree on. */");
      emit("/*     Satisfying these in C is the third implementation, not a rewrite of the others. */");
      emit("");
      for (const c of output) {
        emit(`typedef struct ashee_${c.name.toLowerCase()}_t {`);
        if (c.extends) emit(`  ashee_${c.extends.toLowerCase()}_t themed;`);
        for (const p of c.props) {
          const isText = /string|ReactNode/.test(p.type);
          const t = isText ? "const char *" : "int";
          emit(`  ${t} ${p.name};${p.type ? `  /* ${p.type.slice(0, 68)} */` : ""}`);
        }
        emit(`} ashee_${c.name.toLowerCase()}_t;`);
        emit("");
      }
      return `${output.length} contracts`;
    },
  },
];

// --- resolve, transform, bundle ---------------------------------------------------------------
function build() {
  const t0 = Date.now();
  console.log();
  console.log(`  ${bold("ashee-ui")} ${dim(`building for ${config.target.pixel}`)}`);
  console.log();

  const chunks = [];
  let failures = 0;
  let transformed = 0;

  for (const file of config.design) {
    const path = join(config.designRoot, file);
    const label = file.padEnd(14);

    // Not found and not accepted are different, and are reported differently. Collapsing them
    // would blame the design system for a path this build got wrong.
    if (!existsSync(path)) {
      console.log(`  ${bad("×")} ${label} ${bad("not found")} ${dim(path)}`);
      failures += 1;
      continue;
    }
    const plugin = plugins.find((p) => p.accepts(file));
    if (!plugin) {
      console.log(`  ${bad("×")} ${label} ${bad("no plugin accepts this module")}`);
      failures += 1;
      continue;
    }

    const read = plugin.transform(readFileSync(path, "utf8"));
    const lines = [];
    let note;
    try {
      note = plugin.emit(read.output, config.target, (l) => lines.push(l));
    } catch (err) {
      console.log(`  ${bad("×")} ${label} ${bad(err.message)}`);
      failures += 1;
      continue;
    }

    const refused = (read.refused ?? []).length;
    if (refused > 0) {
      console.log(`  ${bad("!")} ${label} ${dim((note ?? "").padEnd(16))} ${bad(`${refused} shapes refused`)}`);
      failures += 1;
      continue;
    }
    chunks.push({ file, lines });
    transformed += 1;
    console.log(`  ${ok("✓")} ${label} ${dim((note ?? "").padEnd(16))} ${dim(`${lines.length} lines emitted`)}`);
  }

  // The entry. Reported when absent, because a bundler that quietly bundles nothing is the
  // failure this project keeps rediscovering.
  if (existsSync(join(root, config.entry))) {
    console.log(`  ${ok("✓")} ${config.entry.padEnd(14)} ${dim("entry")}`);
  } else {
    console.log(`  ${dim("!")} ${config.entry.padEnd(14)} ${dim("no entry yet -- the design language is bundled alone")}`);
  }

  return { chunks, failures, transformed, t0 };
}

// --- the palette, read from the declared source rather than copied from it ---------------------
function palette() {
  const hexes = [...readFileSync(config.brand, "utf8").matchAll(/#([0-9A-Fa-f]{6})/g)].map((m) => m[1].toUpperCase());
  const NEED = ["FB923C", "0B0F14", "EA580C", "FFFFFF"];
  if (!NEED.every((h) => hexes.includes(h))) return null;
  const rgb565 = (h) => {
    const r = parseInt(h.slice(0, 2), 16);
    const g = parseInt(h.slice(2, 4), 16);
    const b = parseInt(h.slice(4, 6), 16);
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
  };
  const d = (n, h) => `#define ${n} 0x${rgb565(h).toString(16).toUpperCase().padStart(4, "0")}  /* #${h} */`;
  return [d("ASHEE_UI_ACCENT", "FB923C"), d("ASHEE_UI_INK", "0B0F14"), d("ASHEE_COMPANY_ACCENT", "EA580C"), d("ASHEE_COMPANY_INK", "FFFFFF")];
}

/** Contrast, computed here. A design language's value is its rules; a rule that cannot be
 *  checked is an intention, and BRAND.md makes a claim this build is able to verify. */
function contrast(a, b) {
  const lum = (h) => {
    const ch = (v) => {
      const c = v / 255;
      return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * ch(parseInt(h.slice(0, 2), 16)) + 0.7152 * ch(parseInt(h.slice(2, 4), 16)) + 0.0722 * ch(parseInt(h.slice(4, 6), 16));
  };
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

function run() {
  const { chunks, failures, transformed, t0 } = build();
  const colours = palette();
  if (colours === null) {
    console.log(`  ${bad("×")} palette        ${bad("BRAND.md no longer declares all four values")}`);
  }

  const text = [
    "/*",
    ` * ${config.name} -- generated by tools/build.mjs. DO NOT EDIT.`,
    " *",
    " * Bundled from the AsheeUI shared layer, which depends on nothing, for a framebuffer.",
    " * The palette is read from BRAND.md at build time rather than copied, so the two cannot",
    " * disagree about what the accent is.",
    " */",
    "#ifndef ASHEE_BUNDLE_H",
    "#define ASHEE_BUNDLE_H",
    "",
    ...chunks.flatMap((c) => [`/* === ${c.file} === */`, ...c.lines, ""]),
    "/* --- palette, in the framebuffer's own pixel format --- */",
    ...(colours ?? []),
    "",
    "#endif",
    "",
  ].join("\n");

  mkdirSync(dirname(join(root, config.out)), { recursive: true });
  writeFileSync(join(root, config.out), text);

  console.log();
  let failed = failures + (colours === null ? 1 : 0);
  for (const [label, a, b] of [
    ["AsheeUI accent on ink", "FB923C", "0B0F14"],
    ["company accent on white", "EA580C", "FFFFFF"],
  ]) {
    const r = contrast(a, b);
    const pass = r >= 4.5;
    console.log(`  ${pass ? ok("✓") : bad("×")} ${label.padEnd(26)} ${r.toFixed(2)}:1 ${dim(pass ? "" : "< 4.5:1 for normal text")}`);
    if (!pass) failed += 1;
  }

  console.log();
  console.log(`  ${dim("modules")} ${transformed} transformed${failed ? `, ${failed} failed` : ""}`);
  console.log(`  ${dim("output ")} ${config.out}  ${bold(`${(Buffer.byteLength(text) / 1024).toFixed(1)} kB`)}`);
  console.log(`  ${dim("target ")} ${config.target.cell.w}x${config.target.cell.h} cells, ${config.target.pixel}`);
  console.log();
  if (failed > 0) {
    console.log(`  ${bad(bold(`${failed} problem(s) -- written, but not complete`))}`);
    console.log();
    return 1;
  }
  console.log(`  ${ok(bold(`built in ${Date.now() - t0}ms`))}`);
  console.log();
  return 0;
}

const status = run();
if (doWatch) {
  console.log(`  ${dim("watching the platform-neutral layer. the HMR equivalent here is a 1.7s reboot.")}`);
  console.log();
  for (const file of config.design) {
    const path = join(config.designRoot, file);
    if (existsSync(path)) watch(path, { persistent: true }, () => run());
  }
} else {
  process.exit(status);
}
