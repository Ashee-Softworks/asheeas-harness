#!/usr/bin/env node
/**
 * bench-sha — the TypeScript side of the native speed comparison.
 *
 * It does exactly what `native/scoreboard.cpp --bench-digest` does, using the algorithm's own
 * `sha256` from `algorithm/src/util.ts`, so the two timings measure the same work and can be
 * put in the same table.
 *
 *   node bin/bench-sha.mjs [iterations] [bytesPerDocument]
 */
import { sha256 } from "../../algorithm/src/util.ts";

const iterations = Number(process.argv[2] ?? 20000);
const sizeBytes = Number(process.argv[3] ?? 4096);
const document = "x".repeat(sizeBytes);

const started = performance.now();
let last = "";
for (let index = 0; index < iterations; index += 1) {
  last = sha256(document);
}
const elapsed = performance.now() - started;

const fixed = (value, places) => value.toFixed(places);
console.log(`iterations            ${iterations}`);
console.log(`bytes per document    ${sizeBytes}`);
console.log(`total ms              ${fixed(elapsed, 3)}`);
console.log(`per digest us         ${fixed((elapsed * 1000) / iterations, 3)}`);
console.log(`digests per second    ${fixed(iterations / (elapsed / 1000), 1)}`);
console.log(`last digest           ${last}`);
