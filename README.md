# The harness

One command that measures every rendition of the algorithm the record names, and reports what
each competition actually is and whether this account may download it.

```sh
sh run.sh              # reconnaissance, then every rendition, then the native scoreboard
sh run.sh --skip-slow  # the same, without Kotlin's six-second build
node bench.mjs --only cpp
python3 recon.py       # reconnaissance on its own
```

## What it answers

| Question | Where the answer is |
|---|---|
| Is each competition real, what pays, when does it close? | `reports/competitions.md` |
| May this account download it yet? | `reports/competitions.md`, the `Rules` column |
| Which renditions of the algorithm exist, and which run? | `reports/versions.md` |
| How accurate is each, and how fast? | `reports/versions.md`, `reports/versions.tsv` |
| Is the native component's output identical to the TypeScript one? | `reports/versions.md`, the equivalence table |

## The eleven renditions

`versions.json` lists them, each with the document it is recorded in. They are **two TypeScript
trees, five emitters, and four languages that were asked for and never written**:

| # | Rendition | Exists as |
|---|---|---|
| 1 | `ts-five-commits-ago` | the requested revision of `algorithm/` |
| 2 | `ts-main` | the current tree, `algorithm-main/` |
| 3–7 | `go`, `java`, `cpp`, `kotlin`, `swift` | an emitter in `transpiler/src/emit/` |
| 8–11 | `rust`, `c`, `zig`, `python` | a name in `asheeas/languages/`, and nothing else |

There is no C rendition of the algorithm. `asheeas/languages/asheeas-c` names C as a target;
no converter for it exists, and `bench.mjs` records that as a measured zero rather than
leaving the row out.

## What accuracy means here, per row

- **A TypeScript tree** — the fraction of the project's own tests that passed. The acceptance
  catalogue runs too; a scenario that violated its expectation is recorded, because an
  algorithm whose tests pass while its scenarios fail is not accurate.
- **A converted target** — byte equality with the same program run in the *source* language.
  Not "the targets agree with each other": five renditions of one program can share one bug.
- **A rendition with no emitter** — zero. There is nothing to run, and that zero is the finding.

## What the harness does not do

1. **It does not convert the algorithm.** The transpiler refuses it, by name and by line:
   `UnsupportedConstruct: 'ExportDeclaration' statement at algorithm/src/index.ts:6:1`. Its
   source language is a small TypeScript subset. So every converted rendition is measured on
   the probe program the transpiler *can* convert, and the algorithm itself is measured only
   where it actually exists — the two TypeScript trees.
2. **It does not accept a rule, enter a competition, form a team or submit anything.**
   Accepting a competition's rules is a legal acceptance by the account holder. `recon.py`
   prints the URL and stops; it does not click.
3. **It does not sign in anywhere.** It uses the token already at `~/.kaggle/access_token`,
   on this machine, for this account.

## The native component

`native/scoreboard.cpp`, built with `g++ -std=c++20 -O2`. It is C++ rather than C because C++
is the one native rendition of the transpiler's five targets recorded as having actually run
on this host — there is no C emitter, so this is not a C rendition of the algorithm and does
not claim to be. Three jobs:

```sh
./out/scoreboard --selftest                      # digest against published vectors
./out/scoreboard --digest "the algorithm"        # must equal algorithm/src/util.ts sha256()
./out/scoreboard --sum reports/versions.tsv --digest   # score the measurements
```

`--digest` mirrors `src/util.ts: sha256()` exactly — same algorithm, same truncation to 16 hex
characters — and `bench.mjs` compares the two on fixed vectors plus `"x".repeat(4096)`, `"héllo"`
and `"AI TDD"`. Equality there is the accuracy claim for the native path.

**The speed comparison went the way it was not expected to.** `node:crypto` delegates to
OpenSSL, which uses the CPU's SHA extensions, and the native implementation here is plain
portable C++ that uses none — so the TypeScript path is the faster one by a wide margin. The
number is reported as measured, and `speedVerdict()` in `bench.mjs` exists so the wording
cannot drift into a claim that native is faster because it is native.

## Files

| Path | What it is |
|---|---|
| `run.sh` | the one command |
| `versions.json` | the eleven renditions, and where each is recorded |
| `bench.mjs` | the driver: one measurer per kind of rendition |
| `recon.py` | read-only Kaggle reconnaissance, standard library only |
| `bin/bench-sha.mjs` | the TypeScript side of the speed comparison |
| `native/scoreboard.cpp` | the native component |
| `leak-audit.sh` | the gate that runs before anything is pushed |
| `reports/` | what was measured, written on every run |
| `out/` | build scratch: the binary and the converted probe programs |

## Before this goes anywhere

```sh
sh leak-audit.sh
```

It answers five questions and exits non-zero if any of them has an answer:

1. Is a secret-shaped file **tracked**?
2. Is a secret in a **tracked file's contents**?
3. Is a secret in the **history**? — this one is the serious one, because a later commit
   cannot undo it. A credential found here must be rotated, not deleted.
4. Is a secret **anywhere in the working tree**, including ignored files?
5. Does any publishable file carry **this machine's account name**? A report that names the
   person who ran it is a quieter leak than a token and still a leak.

`reports/` is committed on purpose — it is the evidence for every number in this file, and an
evidence file that is regenerated but never committed is a claim whose proof is held locally
and nowhere else. Every path in it is relative, which is why question 5 passes.
