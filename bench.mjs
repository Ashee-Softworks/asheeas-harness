#!/usr/bin/env node
/**
 * The version harness.
 *
 * One command that answers, for every rendition of the algorithm the record names: does it
 * build, does it run, is its output right, how long did it take. Accuracy and speed, per
 * version, written down.
 *
 * What it does not do, and says so rather than hiding it: it does not convert the algorithm.
 * The transpiler's source language is a small TypeScript subset and the algorithm is outside
 * it, so every converted rendition is measured on the probe program the transpiler *can*
 * convert. The algorithm itself is measured only where it actually exists -- the two
 * TypeScript trees. The gap is reported, not smoothed over.
 *
 *   node bench.mjs [--json] [--skip-slow] [--only <id>]
 *
 * Reports: reports/versions.json, reports/versions.tsv, reports/versions.md
 */
import { spawn } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HARNESS = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HARNESS, "..");
const REPORTS = join(HARNESS, "reports");
const OUT = join(HARNESS, "out");

const ALGORITHM = join(ROOT, "algorithm");
const ALGORITHM_MAIN = join(ROOT, "algorithm-main");
const TRANSPILER = join(ROOT, "transpiler");
const PROBE = "examples/fizzbuzz.ts";

/** Run a shell command, always resolving. A command that cannot start is a result, not a throw. */
function run(command, { cwd, timeoutMs = 900_000 } = {}) {
  return new Promise((settle) => {
    const started = performance.now();
    let stdout = "";
    let stderr = "";
    let killed = false;
    let child;
    try {
      child = spawn("/bin/sh", ["-c", command], { cwd, env: process.env });
    } catch (error) {
      settle({ code: null, stdout, stderr: String(error), ms: 0, started: false });
      return;
    }
    const timer = setTimeout(() => {
      killed = true;
      child.kill("SIGKILL");
    }, timeoutMs);
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", (error) => {
      stderr += String(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      settle({
        code: killed ? null : code,
        stdout,
        stderr,
        ms: performance.now() - started,
        started: true,
        timedOut: killed,
      });
    });
  });
}

/** Pull `key <number>` out of a report line, wherever the caller put it. */
function metric(text, key) {
  const match = new RegExp(`\\b${key}\\s+(\\d+)`).exec(text);
  return match ? Number(match[1]) : null;
}

function round(value, places = 4) {
  const factor = 10 ** places;
  return Math.round(value * factor) / factor;
}

/**
 * The oracle for a converted target: the same source, run in the source language.
 *
 * This is the whole accuracy claim for a converted rendition, and it is deliberately not
 * "the targets agree with each other" -- five renditions of one program can share one bug.
 * The three built-ins the source language defines are supplied here, and nothing else is.
 */
async function oracleOutput() {
  const captured = [];
  globalThis.print = (value) => captured.push(String(value));
  globalThis.toString = (value) => String(value);
  globalThis.length = (value) => Buffer.byteLength(String(value), "utf8");
  await import(pathToFileURL(join(TRANSPILER, PROBE)).href);
  return `${captured.join("\n")}\n`;
}

// ------------------------------------------------------------------ the measurers

/**
 * A rendition of the algorithm proper. Accuracy is the project's own tests: the fraction that
 * passed. The acceptance catalogue is run too, and a scenario that violated its expectation is
 * recorded -- an algorithm whose tests pass while its scenarios fail is not accurate.
 */
async function measureAlgorithm(rendition) {
  const cwd = join(ROOT, rendition.root);
  const record = {
    id: rendition.id,
    kind: rendition.kind,
    language: rendition.language,
    revision: rendition.revision,
    cwd: rendition.root,
    note: rendition.note ?? "",
  };

  if (!existsSync(cwd)) {
    return { ...record, accuracy: 0, ms: 0, status: "absent", detail: `no directory at ${rendition.root}` };
  }

  const tests = await run('node --test "test/unit/*.test.ts" "test/integration/*.test.ts"', {
    cwd,
    timeoutMs: 600_000,
  });
  const combined = `${tests.stdout}\n${tests.stderr}`;
  const total = metric(combined, "tests");
  const passed = metric(combined, "pass");
  const failed = metric(combined, "fail");

  const bench = await run(
    `node test/harness/bench.ts --report ${join(OUT, `bench-${rendition.id}.md`)}`,
    { cwd, timeoutMs: 600_000 },
  );
  const benchText = `${bench.stdout}\n${bench.stderr}`;
  const scenarios = metric(benchText, "scenarios");
  const violations = metric(benchText, "violations");

  const ran = total !== null && total > 0;
  return {
    ...record,
    status: ran ? "ran" : "did-not-run",
    accuracy: ran ? round((passed ?? 0) / total, 4) : 0,
    ms: round(tests.ms + bench.ms, 1),
    tests: { total, passed, failed, ms: round(tests.ms, 1) },
    catalogue: { scenarios, violations, ms: round(bench.ms, 1) },
    detail: ran
      ? `${passed}/${total} tests, ${scenarios} scenarios, ${violations} violations`
      : combined.trim().split("\n").slice(0, 4).join(" | "),
  };
}

/** Read the per-target timing and output the transpiler's build driver prints. */
function parseTargets(text) {
  const lines = text.split("\n");
  const found = new Map();
  const names = { Go: "go", Java: "java", "C++": "cpp", Kotlin: "kotlin", Swift: "swift" };
  for (let index = 0; index < lines.length; index += 1) {
    const header = /^(C\+\+|\w+)\s+ran \((\d+)ms\), printing:\s*$/.exec(lines[index]);
    if (!header) continue;
    const target = names[header[1]] ?? header[1].toLowerCase();
    const output = [];
    for (let scan = index + 1; scan < lines.length; scan += 1) {
      if (!lines[scan].startsWith("    ")) break;
      output.push(lines[scan].slice(4));
      index = scan;
    }
    found.set(target, { ms: Number(header[2]), output: `${output.join("\n")}\n` });
  }
  return found;
}

/**
 * A transpiler target. Accuracy is byte equality with the source-language oracle -- the same
 * program, run in TypeScript. It is not "the targets agree with each other": five renditions of
 * one program can share one bug. A target that could not be built is never counted as agreeing.
 */
async function measureTarget(rendition, oracle, skipSlow) {
  const record = {
    id: rendition.id,
    kind: rendition.kind,
    language: rendition.language,
    emitter: rendition.emitter,
    note: rendition.note ?? "",
  };

  const command = {
    go: "go version",
    java: "javac -version",
    cpp: "g++ --version",
    kotlin: "kotlinc -version 2>/dev/null || ~/.local/toolchain/kotlin/bin/kotlinc -version",
    swift: "swiftc --version",
  }[rendition.target];
  const probe = await run(command, { cwd: TRANSPILER, timeoutMs: 60_000 });
  const probeText = `${probe.stdout}${probe.stderr}`.trim().split("\n")[0] ?? "";

  if (skipSlow && rendition.target === "kotlin") {
    return {
      ...record,
      status: "skipped",
      accuracy: 0,
      ms: round(probe.ms, 1),
      toolchain: probeText,
      detail: "skipped by --skip-slow; Kotlin costs the most to build",
    };
  }
  if (probe.code !== 0) {
    return {
      ...record,
      status: "unavailable",
      accuracy: 0,
      ms: round(probe.ms, 1),
      toolchain: "not found",
      detail: `toolchain not available via \`${command}\``,
    };
  }

  const build = await run(
    `node src/cli.ts ${PROBE} --target ${rendition.target} --out ${join(OUT, "probe-all")} --build`,
    { cwd: TRANSPILER, timeoutMs: 600_000 },
  );
  const text = `${build.stdout}\n${build.stderr}`;
  const result = parseTargets(text).get(rendition.target);

  if (!result) {
    const tail = text.trim().split("\n").slice(-3).join(" | ");
    return {
      ...record,
      status: "did-not-run",
      accuracy: 0,
      ms: round(probe.ms + build.ms, 1),
      toolchain: probeText,
      detail: tail || "the build driver produced no per-target result",
    };
  }

  const bytes = Buffer.byteLength(result.output, "utf8");
  const agreed = result.output === oracle;
  return {
    ...record,
    status: "ran",
    accuracy: agreed ? 1 : 0,
    ms: round(result.ms, 1),
    toolchain: probeText,
    outputAgreed: agreed,
    outputBytes: bytes,
    detail: agreed
      ? `printed the same ${bytes} bytes as the TypeScript oracle`
      : "printed different bytes from the TypeScript oracle",
  };
}

/**
 * A rendition the record names but nobody has written a converter for. It is still measured:
 * its toolchain is probed, so "absent for lack of a compiler" can be told apart from "absent
 * for lack of an emitter". Accuracy is zero because there is nothing to run, and that zero is
 * the finding rather than a placeholder.
 */
async function measureNoEmitter(rendition) {
  const probe = await run(rendition.toolchainProbe, { cwd: ROOT, timeoutMs: 60_000 });
  const text = `${probe.stdout}${probe.stderr}`.trim().split("\n")[0] ?? "";
  return {
    id: rendition.id,
    kind: rendition.kind,
    language: rendition.language,
    emitter: null,
    status: "no-emitter",
    accuracy: 0,
    ms: round(probe.ms, 1),
    toolchain: probe.code === 0 ? text : `not installed (\`${rendition.toolchainProbe}\`)`,
    detail: `no converter written; asked for by ${rendition.askedBy}`,
    note: rendition.note ?? "",
  };
}

// ------------------------------------------------------------------ the native component

/**
 * The native component is the harness's own machinery, so it is reported beside the eleven
 * renditions rather than counted as one of them.
 *
 * Two things are measured. **Equivalence:** its digest must equal the TypeScript one for the
 * same input, character for character -- that is the accuracy claim, and it is checked against
 * vectors and against the algorithm's own `sha256`. **Speed:** the same number of digests of
 * the same document, timed in both, so the two numbers mean the same work.
 */
async function measureNative(algorithmModules) {
  const binary = join(OUT, "scoreboard");
  const record = {
    name: "scoreboard",
    source: "harness/native/scoreboard.cpp",
    compiler: "g++ -std=c++20 -O2",
    note: "C++ because C++ is the one native rendition of the transpiler's five targets recorded as having run on this host. There is no C emitter, so this is not a C rendition of the algorithm.",
  };

  const build = await run(`g++ -std=c++20 -O2 -Wall -Wextra -o ${binary} native/scoreboard.cpp`, {
    cwd: HARNESS,
    timeoutMs: 300_000,
  });
  if (build.code !== 0) {
    return {
      ...record,
      status: "build-failed",
      equivalence: null,
      speed: null,
      detail: `${build.stdout}${build.stderr}`.trim().split("\n").slice(0, 3).join(" | "),
    };
  }

  // Equivalence: the same inputs, both renditions, compared character for character.
  const vectors = ["", "abc", "the algorithm", "x".repeat(4096), "héllo", "AI TDD"];
  const comparisons = [];
  for (const text of vectors) {
    const nativeDigest = (await run(`${binary} --digest ${JSON.stringify(text)}`, { cwd: HARNESS })).stdout.trim();
    const expected = algorithmModules.sha256(text);
    comparisons.push({
      input: text.length > 24 ? `${text.slice(0, 21)}...(${text.length})` : text,
      native: nativeDigest,
      typescript: expected,
      agree: nativeDigest === expected,
    });
  }
  const agreed = comparisons.filter((row) => row.agree).length;

  // Speed: the same work on both sides.
  const iterations = 20000;
  const sizeBytes = 4096;
  const nativeRun = await run(`${binary} --bench-digest ${iterations} ${sizeBytes}`, {
    cwd: HARNESS,
    timeoutMs: 300_000,
  });
  const tsRun = await run(`node bin/bench-sha.mjs ${iterations} ${sizeBytes}`, {
    cwd: HARNESS,
    timeoutMs: 300_000,
  });
  const readPerDigest = (text) => {
    const match = /per digest us\s+([\d.]+)/.exec(text);
    return match ? Number(match[1]) : null;
  };

  const nativeUs = readPerDigest(nativeRun.stdout);
  const tsUs = readPerDigest(tsRun.stdout);
  const speed = {
    iterations,
    sizeBytes,
    nativeUsPerDigest: nativeUs,
    typescriptUsPerDigest: tsUs,
    factor: nativeUs && tsUs ? round(tsUs / nativeUs, 2) : null,
  };

  return {
    ...record,
    status: agreed === vectors.length ? "ran" : "disagreed",
    equivalence: { vectors: vectors.length, agreed, comparisons },
    speed,
    detail:
      agreed === vectors.length
        ? `${agreed}/${vectors.length} digests identical to the TypeScript rendition`
        : `${vectors.length - agreed} of ${vectors.length} digests differ from the TypeScript rendition`,
  };
}

// ------------------------------------------------------------------ reporting

/**
 * Which side was faster, in words that stay true whichever way it went.
 *
 * It is worth having this as a function rather than a template, because the answer is not
 * obvious and must not be assumed: Node's `node:crypto` delegates to OpenSSL, which uses the
 * CPU's SHA extensions, while the native implementation here is plain portable C++. Claiming
 * a native win because it is native would be the exact kind of unsupported claim this project
 * keeps refusing to make.
 */
function speedVerdict(speed) {
  if (!speed.nativeUsPerDigest || !speed.typescriptUsPerDigest) return "not comparable — a timing was not taken";
  if (speed.factor >= 1) {
    return `the native rendition is ${speed.factor}× faster per digest`;
  }
  return (
    `TypeScript is ${round(1 / speed.factor, 2)}× faster per digest, because \`node:crypto\` ` +
    "delegates to OpenSSL, which uses the CPU's SHA extensions, while the native rendition here " +
    "is a portable implementation that uses none"
  );
}

function renderMarkdown(report, scoreboard) {
  const rows = report.renditions;
  const ran = rows.filter((row) => row.status === "ran");
  const sum = (key) => round(rows.reduce((total, row) => total + (row[key] ?? 0), 0), 4);

  let lines = [
    "# Every rendition of the algorithm, measured",
    "",
    `Generated ${report.measuredOn} from ${rows.length} renditions.`,
    "",
    "| Measure | Value |",
    "|---|---|",
    `| Renditions in the record | ${rows.length} |`,
    `| Ran | ${ran.length} |`,
    `| Mean accuracy | ${round(sum("accuracy") / rows.length, 4)} |`,
    `| Total ms | ${round(sum("ms"), 1)} |`,
    "| Converts the algorithm itself | no — refused at `algorithm/src/index.ts:6:1` |",
    "",
    "**Accuracy means, per row:** for a TypeScript tree, the fraction of the project's own tests",
    "that passed. For a converted target, byte equality with the same program run in the source",
    "language. For a rendition with no emitter, zero — there is nothing to run, and that is the",
    "finding rather than a placeholder.",
    "",
    "## The eleven",
    "",
    "| Rendition | Language | Kind | Status | Accuracy | ms | Detail |",
    "|---|---|---|---|---|---|---|",
  ];

  for (const row of rows) {
    lines.push(
      `| \`${row.id}\` | ${row.language} | ${row.kind} | ${row.status} | ${row.accuracy} | ${row.ms} | ${row.detail} |`,
    );
  }

  lines.push("", "## The native component, beside the eleven", "");

  if (report.native.status === "build-failed") {
    lines.push(`**Did not build.** ${report.native.detail}`, "");
  } else {
    lines.push(
      `\`${report.native.source}\`, built with \`${report.native.compiler}\`.`,
      "",
      `- **Equivalence:** ${report.native.detail}`,
      `- **Speed:** ${report.native.speed.nativeUsPerDigest} µs per digest natively against ` +
        `${report.native.speed.typescriptUsPerDigest} µs in TypeScript, over ` +
        `${report.native.speed.iterations} digests of ${report.native.speed.sizeBytes} bytes — ` +
        speedVerdict(report.native.speed),
      "",
      "| Input | Native | TypeScript | Agrees |",
      "|---|---|---|---|",
      ...report.native.equivalence.comparisons.map(
        (row) =>
          `| \`${row.input}\` | \`${row.native}\` | \`${row.typescript}\` | ${row.agree ? "yes" : "**no**"} |`,
      ),
      "",
    );
  }

  lines.push(
    "## The scoreboard, computed natively",
    "",
    "```",
    scoreboard.trim(),
    "```",
    "",
    "## What this harness cannot do, stated rather than omitted",
    "",
    "1. **It does not convert the algorithm.** The transpiler refuses it by name and by line, so",
    "   every converted rendition is measured on the probe program, not on the algorithm.",
    "2. **There is no C rendition.** `asheeas/languages/asheeas-c` names C as a target and no",
    "   converter exists. The nearest working native rendition is C++, and that is what is measured.",
    "3. **Nothing here enters a competition or accepts a rule.** That is `recon.py`'s job, and it",
    "   reports the page instead of clicking it.",
    "",
  );

  return lines.join("\n");
}

async function main() {
  const argv = process.argv.slice(2);
  const asJson = argv.includes("--json");
  const skipSlow = argv.includes("--skip-slow");
  const onlyIndex = argv.indexOf("--only");
  const only = onlyIndex >= 0 ? argv[onlyIndex + 1] : null;

  await mkdir(REPORTS, { recursive: true });
  await mkdir(OUT, { recursive: true });

  const manifest = JSON.parse(await readFile(join(HARNESS, "versions.json"), "utf8"));
  const algorithmModules = await import(pathToFileURL(join(ALGORITHM, "src/util.ts")).href);

  const oracle = await oracleOutput();
  process.stdout.write(`oracle: ${Buffer.byteLength(oracle, "utf8")} bytes from ${PROBE}\n`);

  const renditions = [];
  for (const rendition of manifest.renditions) {
    if (only && rendition.id !== only) continue;
    const started = performance.now();
    let measured;
    if (rendition.kind === "algorithm") {
      measured = await measureAlgorithm(rendition);
    } else if (rendition.kind === "transpiler-target") {
      measured = await measureTarget(rendition, oracle, skipSlow);
    } else {
      measured = await measureNoEmitter(rendition);
    }
    renditions.push(measured);
    process.stdout.write(
      `${String(measured.status).padEnd(13)} ${String(measured.id).padEnd(22)} ` +
        `accuracy ${String(measured.accuracy).padEnd(7)} ${String(measured.ms).padEnd(9)}ms ` +
        `(${round(performance.now() - started, 0)}ms wall)\n`,
    );
  }

  const report = {
    measuredOn: new Date().toISOString(),
    manifest: "harness/versions.json",
    count: renditions.length,
    oracleBytes: Buffer.byteLength(oracle, "utf8"),
    renditions,
    native: await measureNative(algorithmModules),
  };

  // The TSV is what the native scoreboard reads. Written before it is needed, not after.
  const tsv = [
    "# id\tkind\taccuracy\tms\tnote",
    ...renditions.map(
      (row) => `${row.id}\t${row.kind}\t${row.accuracy}\t${row.ms}\t${String(row.detail).slice(0, 120)}`,
    ),
  ].join("\n");
  await writeFile(join(REPORTS, "versions.tsv"), `${tsv}\n`, "utf8");

  const scoreboard = await run(`${join(OUT, "scoreboard")} --sum reports/versions.tsv --digest`, {
    cwd: HARNESS,
    timeoutMs: 60_000,
  });
  report.scoreboard = scoreboard.stdout;

  await writeFile(join(REPORTS, "versions.json"), `${JSON.stringify(report, null, 2)}\n`, "utf8");
  await writeFile(join(REPORTS, "versions.md"), renderMarkdown(report, scoreboard.stdout), "utf8");

  const ran = renditions.filter((row) => row.status === "ran").length;
  process.stdout.write(
    `\nrenditions ${renditions.length} · ran ${ran} · native ${report.native.status}\n` +
      `reports: ${join(REPORTS, "versions.md")}, versions.json, versions.tsv\n`,
  );

  if (asJson) process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  return 0;
}

process.exitCode = await main();
