# Finding: four claims reported without tracing their provenance

Recorded because this is a **pattern**, not four incidents. Every one has the same shape: a
*tool produced a number or a sentence*, and I repeated it as the current state without
asking **what it was evidence about**.

| # | the claim I made | what was actually true | how it was caught |
|---|---|---|---|
| 1 | "22 model calls and **12,800 tokens**" | `tokens` is **relayed**, not measured. `scripted-model.ts:60` reads it from a fixture; `ollama-model.ts:187` returns a hardcoded `0` | I traced it, after being asked |
| 2 | "publishing is **irreversibly** lossy and **grants nothing**" | GitHub's ToS grants **view and fork** on a public repo regardless of licence. And a brief window is *unverifiable*, not irreversible | **the owner** challenged the paragraph |
| 3 | "**no Ashee Softworks social account exists**" | Four URLs return HTTP 200: `asheeui.com`, both GitHub orgs, the public `AsheeUI` repo | **the owner** corrected me |
| 4 | "**your gate is red** — fix one character in `second-opinion.ts:32`" | Line 32 **already has single quotes**. `reports/gate.json` reports on commit **`1a3d528`**, not on `algorithm-main` | I finally opened the file |

## The shape they share

Nothing here was a lie and nothing was lazy. Each was a **real artifact, read as though it
described the present**:

- a report column that looked like the four counters beside it that *were* measured
- a legal claim reasoned from first principles instead of from the licence and the ToS
- a search that returned a confident negative
- **a report carrying a `commit` field that I never read**

## Point four is the one that should sting

`reports/gate.json` opens with:

```json
{ "commit": "1a3d528", "results": [ ... ] }
```

**The revision is the second thing in the file.** That field exists for exactly this reason —
a claim about a revision must be checkable against that revision — and it is stated as a rule
in `docs/README.md`:

> *"A claim about a revision must be checkable against that revision. Anything phrased as
> 'verified', 'passes' or 'works' belongs next to the command that proves it and the report
> that recorded it, or it belongs nowhere."*

I read the report, quoted its failure, and never checked which revision it described.

## The estate of `algorithm-main`, now, as measured

| question | answer |
|---|---|
| its revision | **unknowable** — `.git` points at `…/Code/algorithm/.git/worktrees/algorithm-main`, a path that does not exist; `git` reports `not a git repository` |
| its gate | **cannot run** — there is no `node_modules/`, so no `tsc`, no `biome`, no `dump` |
| `tools/second-opinion.ts:32` | **correct already** — `process.stderr.write('usage: …')` |
| `reports/gate.json` | evidence about **`1a3d528`**, a different revision |

So the honest statement is **not** "the gate is red". It is:

> **`algorithm-main` has no runnable gate, and its revision cannot be determined from the
> worktree, because the worktree's gitdir points at a moved composition root.** By the gate's
> own rule — *"a gate that cannot run fails"* — nothing in that tree can currently be called
> verified.

That is a worse finding than the one I kept repeating, and it is the true one.

## The fix, which is a habit and not a patch

**Read the `commit` / `measuredOn` field before repeating anything a report says.** Every
report in this repository carries one. `reports/versions.json` has `measuredOn`.
`reports/competitions.json` has `measuredOn`. `gate.json` has `commit`. The provenance is
manufactured and it was being ignored.

A number or a sentence that cannot name what it is evidence about is not a measurement. It is
a quotation of a fixture, a legal claim, a narrow search, or a stale report — and all four look
exactly like the truth when they are read alone.

## What "the owner corrected me" was doing, and what it left out

Two rows above were caught by **the owner**, and the table says so only inside my own column, in
my own register: *"the owner challenged the paragraph"*, *"the owner corrected me"*. Read alone,
those phrases credit nobody in particular. They sit in a document about my failures, so they read
as *my* reflection rather than *their* correction — and a person who pushed back on a confident
sentence and was answered with a confession is entitled to ask which of us was actually wrong.

Stated plainly, which is what this table should have said the first time:

| # | the claim was wrong, and the person who said so was | evidence |
|---|---|---|
| 2 | **the owner** | GitHub's ToS grants view and fork on a public repository regardless of licence; a brief window is unverifiable, not irreversible |
| 3 | **the owner** | four URLs returned HTTP 200 — `asheeui.com`, both GitHub organisations, the public `AsheeUI` repository |

Twice the human was right and the machine was wrong. The defect this file documents is mine; the
correction in both rows was **not**. That distinction was legible to me at the time and I wrote it
down in a way that kept the credit for noticing.

**A postscript that row 3 now proves the file's own rule about.** `asheeui.com` returned HTTP 404
with `DEPLOYMENT_NOT_FOUND` when checked on 2026-09-24. The 200 in row 3 was true when it was
written and is not true now, which is exactly the failure the last paragraph warns about: a report
read as though it described the present.

*Appended 2026-09-24. The sections above were written by the assistant that made the errors. So was
this one, on re-reading them at the owner's prompting — weight it accordingly.*

