# The harness

One command that measures every rendition of the algorithm the record names, and reports what
each competition actually is and whether this account may download it.

```sh
sh run.sh              # reconnaissance, then every rendition, then the native scoreboard
sh run.sh --skip-slow  # the same, without Kotlin's six-second build
node bench.mjs --only cpp
python3 recon.py       # reconnaissance on its own
```

## Licence

**GNU Affero General Public License, version 3 or later** (`AGPL-3.0-or-later`).
Copyright (C) 2026 Ashee Softworks. The full text is in [`LICENSE`](LICENSE).

Read it, run it, change it, sell it. The one condition is the condition that makes this AGPL
rather than GPL: **if you run a modified version and let other people use it over a network, you
must offer those users your source.** Section 13 says it in full. Running it privately, or
changing it and keeping the changes to yourself, obliges you to nothing.

**Two facts about the change, both worth knowing.** Until 2026-09-24 this repository carried
`PROPRIETARY AND CONFIDENTIAL — ALL RIGHTS RESERVED / NO LICENSE IS GRANTED`, and **that text
remains in every commit before the change** — a later commit does not unpublish it, in exactly the
way a rotated secret is not made safe by deleting the file. And the new grant cannot be recalled
either: every copy taken under AGPL-3.0 stays free, for anyone, for good. A repository's history
is the one thing on this page that is permanent in both directions.

## What else is in this repository

The harness is about a third of it. The rest is here on purpose, and it is record rather than
product.

| path | what it is |
|---|---|
| `run.sh`, `bench.mjs`, `bin/`, `native/`, `versions.json`, `reports/` | the harness: eleven renditions measured, and the committed evidence for every number in this file |
| `ashee-os/` | the OS image builder — the design system projected onto a framebuffer (rgb565, an 8×16 glyph cell) by `tools/build.mjs`, emitted as a single C header |
| `observations/` | audits written while the work was happening: four claims reported without tracing their provenance, an injection surface, a refusal, a token-accounting defect. **This is the method, not the results** — it is the part meant to be useful to someone who never speaks to anyone here |
| `announcement/` | **an unpublished draft.** Every claim in it that was not true when it was written is listed in its own "not yet true" table, and it is kept rather than removed |
| `members/` | the member roster: usernames and invite status, no credentials, and the note explaining why there are none |
| `leak-audit.sh`, `system-audit.sh`, `os-probe.sh` | the gates. `leak-audit.sh` runs before anything is pushed anywhere, and exits non-zero if it finds a credential |

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
and nowhere else. Every path in **`reports/`** is relative, so it passes question 5.

**Question 5 does not pass for the repository as a whole, and this sentence used to imply it
did.** Checked on 2026-09-24: five files under `ashee-os/` carry absolute paths containing this
machine's account name — `gui/tokens.h` in two comments, `ashee.config.mjs` in two defaults, and
`mkpendrive.sh` in an archive path. This file's own wording applies: *"A report that names the
person who ran it is a quieter leak than a token and still a leak."*

They are also a **portability defect, which now matters more than the privacy one**: a build that
reads `/home/…` cannot run on anybody else's machine, and this repository is open. The fix in each
case is small and one of three things — `${HOME}`, a path relative to the repository, or the
environment variable the code already reads (`ashee.config.mjs` takes `ASHEE_UI` that way, and only
the default is absolute).

