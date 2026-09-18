# Observer report: the planner test

**Subject:** can the planner launch parallel instances, host sub-planners, self-repair,
select the right version to instantiate, and update GitHub — by finding ten competitions on
the internet and passing as many as possible, at 2 seconds each.

**Instruction observed:** *don't help it, just monitor and write a report.*

**Verdict: the test could not be run, because the subject does not exist.** This is not a
claim about difficulty. It is a quotation from the planner's own README.

---

## 1. What the planner says about itself

`asheeas/planner/README.md`, line 11, in full:

> **The host probe exists. Nothing else in here does.**

And its own list of what belongs there and is not written:

| what was asked for | the planner's own words | milestone |
|---|---|---|
| choosing the right version to instantiate | *"a **role**, not a fixed program: whichever instance of the algorithm best suits the situation"* | M05 |
| version-aware dispatch | *"record the toolchain and version each job needs, and select an installed version that satisfies it"* | M05 |
| **parallel instances** | *"**parallel dispatch** of workers and of transpiler instances, bounded by the budget above"* | M06 |
| sub-planners | not named anywhere in the repository | — |
| self-repair | see §4 | — |

The directory contains exactly two files: `host.ts` (11,399 bytes) and `README.md` (3,301
bytes). There is no `dispatch.ts`, no `planner.ts`, no worker pool, no scheduler.

## 2. Confirmed by search, not by reading one file

A case-insensitive search for `dispatch|parallel|subplan|fork(|worker_threads|spawn(` across
`algorithm/src`, `algorithm/tools`, `asheeas/planner` and `asheeas/composer` returns **six**
hits, and none of them is a dispatcher:

- `algorithm/src/exec/command-runner.ts:38` — `spawn` of **one** command
- `algorithm/src/cache/unqlite-helper.ts:141,158,160,189` — `spawn` of **one** helper process
- `algorithm/src/cache/keys.ts:24`, `store.ts:113` — comments saying the store is *safe for*
  parallel work, which is a property of the store, not a mechanism that runs anything in
  parallel
- `algorithm/tools/gate.ts:78,80` — the string `parallel` naming a test directory

A search for version selection (`which version|choose.*version|instantiate|selectVersion|`
`resolveVersion`) returns **no** implementation — only prose in an unrelated inherited
document about a school-management product.

So: **no dispatcher, no worker pool, no sub-planner, no version selector.** Four of the five
capabilities named in the test have no code at all.

## 3. The one thing that does exist, measured

`asheeas/planner/host.ts` runs, and it is a genuine measurement rather than a stub:

```
$ /usr/bin/time -f '  wall: %e s' node asheeas/planner/host.ts
{"present": ["node","npm","git","docker","python3","go","javac","java","swiftc",
             "g++","cmake","rustc","cargo","ollama"],
 "absent":  ["kotlinc","gradle","clang++"],
 "note": "Cache this with its timestamp and its evidence. It is a measurement, so it
          expires; it is never the record that a tool exists."}
  wall: 7.49 s
```

It probes seventeen toolchains and takes **7.49 seconds**. That is the *input* a dispatcher
would size its work from. It alone is **3.7× the entire 2-second budget** the test allows.

## 4. Self-repair: it exists inside a milestone, not around one

The algorithm does have a repair mechanism, and it is real — the acceptance catalogue has a
`broken-then-repaired` scenario and a `repair-exhausted` scenario, and both pass:

```
$ node test/harness/bench.ts --report /tmp/obs_bench.md
ok   broken-then-repaired: complete, 1 touch(es), 3782 chars
ok   repair-exhausted: held, 1 touch(es), 3782 chars
scenarios 12 · violations 0 · human touches 15 · context 42328 vs 51818 chars
```

But that is repair **of one milestone, driven by a scripted model, inside one run**. There is
no outer loop that notices a run failed and starts another. `algorithm/tools/loop.ts` is the
nearest thing and it is not a repair loop: it runs two gates and commits when both pass. Its
own header says so — *"verifying both repositories and committing changes when both pass."*

## 5. The 2-second budget, measured

Everything below was run on this host, one after another, on an otherwise idle machine.
The model is `qwen2.5-coder:0.5b` — 494M parameters, the **smallest** model installed. A
larger model is strictly slower.

| operation | wall | note |
|---|---|---|
| model call, 2 tokens out, **cold** | **7.04 s** | the weights are loaded into memory |
| model call, 2 tokens out, **warm** | **0.44–0.47 s** | of which **364.6 ms is load**, 45.0 ms is the 2 tokens |
| **model call, realistic plan, 58 tokens out** | **3.14 s** | *already over budget* |
| `host.ts`, seventeen toolchains | **7.49 s** | |
| algorithm acceptance catalogue, 12 scenarios × 2 modes | **4.08 s** | |

Two numbers decide it:

1. **A warm call costs 364.6 ms before emitting a single token.** That is a fixed floor, and
   it is 18% of the budget spent producing nothing.
2. **A realistic planning call produced 58 output tokens in 3.14 s**, and 58 tokens is a
   five-line plan. The work the test asks for — *find ten competitions* — cannot be expressed
   in fewer.

### The arithmetic

```
find 10 competitions over the internet     ≥ 1 network search,                       ~1 s
decide what to do about them               ≥ 1 model call at useful length,         3.14 s
solve them                                 ≥ 1 model call each × 10,               31.4 s
                                           ----------------------------------------
                                           floor, before any real work is done,     ~35 s
budget offered                                                                       2 s
```

**The budget is short by a factor of roughly 16**, and that is the floor for the *cheapest
possible* loop using the smallest model available. It assumes every competition is solved by
one call that is already correct, and that nothing ever needs repairing — which is the thing
the test is specifically about.

## 6. What I did not do

The instruction was *don't help it, just monitor*. So:

- I did not write a dispatcher, a sub-planner, a version selector or a repair loop. Writing
  them would have made the report describe my code rather than the subject's capability.
- I did not run `algorithm/tools/loop.ts`, the one path that reaches GitHub. Running it would
  be *me* performing the action under observation, and it would have committed to `algorithm`
  and `transpiler` on the strength of my invocation rather than the planner's decision. Its
  behaviour is reported from its own source instead.
- I did not use `harness/recon.py` to find the ten competitions. That tool is mine, not the
  planner's, and using it would have produced a passing result for a capability the subject
  does not have.

## 7. What would have to exist before this test means anything

In the planner's own milestone order, because the ordering is a dependency chain and not a
preference:

1. a **dispatcher** that turns one plan into N bounded jobs (M06) — the host probe already
   returns the worker count and names which bound set it, so the input exists
2. a **version selector** that maps a job's required toolchain version to an installed one
   (M05) — `reports/languages.json` already records what is installed
3. a **sub-planner** role, which is not merely unwritten but unnamed anywhere in the repo
4. an **outer repair loop** — a supervisor that sees a failed run and starts another
5. a **budget model**, because 2 seconds cannot be honoured, and a planner that cannot say
   "this is impossible" will instead report a number it did not earn

Until 1–4 exist, the honest result of this test is the one above: **0 of 10 competitions
attempted, 0 passed, in 0 seconds of planner activity** — because no planner activity
occurred. Reporting 10/10 from any other source would be theatre.

---

## Method

Every number above came from a command run on this host on 2026-09-18, and each is
reproducible:

```sh
node asheeas/planner/host.ts                                   # 7.49 s
curl -sS -X POST http://127.0.0.1:11434/api/chat \
  -H 'content-type: application/json' \
  -d '{"model":"qwen2.5-coder:0.5b","stream":false,
       "messages":[{"role":"user","content":"Reply with the single word: ok"}]}'
node algorithm-main/test/harness/bench.ts                      # 4.08 s
```

The cold/warm distinction is real and was measured, not assumed: the first call of the
session took 7.04 s and the two immediately after it took 0.44 s and 0.47 s. A test that
timed only the first call would report the model as 16× slower than it is; a test that timed
only warm calls would ignore the load cost that the first competition of any run must pay.
