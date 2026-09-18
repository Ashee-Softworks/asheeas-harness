# Every rendition of the algorithm, measured

Generated 2026-09-18T05:06:22.503Z from 11 renditions.

| Measure | Value |
|---|---|
| Renditions in the record | 11 |
| Ran | 7 |
| Mean accuracy | 0.6364 |
| Total ms | 37125.7 |
| Converts the algorithm itself | no — refused at `algorithm/src/index.ts:6:1` |

**Accuracy means, per row:** for a TypeScript tree, the fraction of the project's own tests
that passed. For a converted target, byte equality with the same program run in the source
language. For a rendition with no emitter, zero — there is nothing to run, and that is the
finding rather than a placeholder.

## The eleven

| Rendition | Language | Kind | Status | Accuracy | ms | Detail |
|---|---|---|---|---|---|---|
| `ts-five-commits-ago` | TypeScript | algorithm | ran | 1 | 19237.7 | 117/117 tests, 12 scenarios, 0 violations |
| `ts-main` | TypeScript | algorithm | ran | 1 | 9193.3 | 117/117 tests, 12 scenarios, 0 violations |
| `go` | Go | transpiler-target | ran | 1 | 253 | printed the same 72 bytes as the TypeScript oracle |
| `java` | Java | transpiler-target | ran | 1 | 811 | printed the same 72 bytes as the TypeScript oracle |
| `cpp` | C++ | transpiler-target | ran | 1 | 591 | printed the same 72 bytes as the TypeScript oracle |
| `kotlin` | Kotlin | transpiler-target | ran | 1 | 6060 | printed the same 72 bytes as the TypeScript oracle |
| `swift` | Swift | transpiler-target | ran | 1 | 655 | printed the same 72 bytes as the TypeScript oracle |
| `rust` | Rust | named-no-emitter | no-emitter | 0 | 289.4 | no converter written; asked for by asheeas/languages/asheeas-rust, algorithm REQ-036 |
| `c` | C | named-no-emitter | no-emitter | 0 | 8.2 | no converter written; asked for by asheeas/languages/asheeas-c |
| `zig` | Zig | named-no-emitter | no-emitter | 0 | 22.4 | no converter written; asked for by asheeas/languages/asheeas-zig |
| `python` | Python | named-no-emitter | no-emitter | 0 | 4.7 | no converter written; asked for by asheeas/languages/asheeas-python, algorithm REQ-040 |

## The native component, beside the eleven

`harness/native/scoreboard.cpp`, built with `g++ -std=c++20 -O2`.

- **Equivalence:** 6/6 digests identical to the TypeScript rendition
- **Speed:** 24.162 µs per digest natively against 5.234 µs in TypeScript, over 20000 digests of 4096 bytes — TypeScript is 4.55× faster per digest, because `node:crypto` delegates to OpenSSL, which uses the CPU's SHA extensions, while the native rendition here is a portable implementation that uses none

| Input | Native | TypeScript | Agrees |
|---|---|---|---|
| `` | `e3b0c44298fc1c14` | `e3b0c44298fc1c14` | yes |
| `abc` | `ba7816bf8f01cfea` | `ba7816bf8f01cfea` | yes |
| `the algorithm` | `0907994f66a3e4a2` | `0907994f66a3e4a2` | yes |
| `xxxxxxxxxxxxxxxxxxxxx...(4096)` | `a2e659dacb4691e8` | `a2e659dacb4691e8` | yes |
| `héllo` | `3c48591d8d098a45` | `3c48591d8d098a45` | yes |
| `AI TDD` | `58c2d9ac24a067f9` | `58c2d9ac24a067f9` | yes |

## The scoreboard, computed natively

```
rendition             kind                accuracy  ms
--------------------------------------------------------------
ts-five-commits-ago   algorithm           1.0000    19237.7
ts-main               algorithm           1.0000    9193.3
go                    transpiler-target   1.0000    253.0
java                  transpiler-target   1.0000    811.0
cpp                   transpiler-target   1.0000    591.0
kotlin                transpiler-target   1.0000    6060.0
swift                 transpiler-target   1.0000    655.0
rust                  named-no-emitter    0.0000    289.4
c                     named-no-emitter    0.0000    8.2
zig                   named-no-emitter    0.0000    22.4
python                named-no-emitter    0.0000    4.7

renditions            11
mean accuracy         0.6364
total ms              37125.7
fastest that ran      go (253.0 ms)
slowest that ran      ts-five-commits-ago (19237.7 ms)
report digest         dfd2f52b7eca824d
scoreboard ms         0.120
```

## What this harness cannot do, stated rather than omitted

1. **It does not convert the algorithm.** The transpiler refuses it by name and by line, so
   every converted rendition is measured on the probe program, not on the algorithm.
2. **There is no C rendition.** `asheeas/languages/asheeas-c` names C as a target and no
   converter exists. The nearest working native rendition is C++, and that is what is measured.
3. **Nothing here enters a competition or accepts a rule.** That is `recon.py`'s job, and it
   reports the page instead of clicking it.
