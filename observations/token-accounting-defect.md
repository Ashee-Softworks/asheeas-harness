# Finding: the token metric is relayed, not measured

**Found** 2026-09-18, while checking a figure the observer had earlier reported from
`algorithm/reports/bench.md`.

**The defect.** `src/model/model.ts:83` accumulates the token metric from whatever the model
implementation *reports*:

```ts
this.metrics.bump("tokens", response.tokens ?? 0);
```

All three implementations relay a declared number. **None of them measures one.**

| implementation | line | what `tokens` actually is |
|---|---|---|
| `scripted-model.ts` | 60 | `entry.tokens ?? 0` — **a number typed into `model-script.json`** (`"tokens": 1800`) |
| `command-model.ts` | 96 | `parsed.tokens` — **the external process's self-declaration**, unchecked |
| `ollama-model.ts` | 187 | **`tokens: 0`** — hardcoded zero, on every call |

And the real counts are never read:

```
$ grep -rniE 'eval_count|prompt_eval_count|total_duration' src/
(no matches)
```

Ollama's API returns `prompt_eval_count` and `eval_count` on every response. They are
available, and this codebase does not look at them.

## Why it matters, in two parts

**1. The token budget cannot fire on a real model.** `model.ts:50` guards on
`metrics.metrics.tokens >= this.budgets.maxTokens`, and `maxTokens` defaults to **400,000**
(`model.ts:8`). With `tokens` permanently `0`, that clause is unreachable. On a real run the
only live bounds are `maxModelCalls` (60) and `maxWallClockMs` (30 min).

So the `budget-exhausted` scenario in the acceptance catalogue is exercisable **only** by a
scripted model — which is exactly how it is exercised. The catalogue proves the guard works
against a fixture that feeds it a number. It has never been shown to work against a model.

**2. The number reads as a measurement and is not one.** `reports/bench.md` prints a
`Tokens` column beside `Checks`, `Repairs` and `Reverts` — counters that *are* observed. The
token column is the sum of numbers written in `examples/inventory-app/model-script.json`.
Nothing in the report says so.

**The observer made this mistake.** An earlier report from this session stated *"22 model
calls and 12,800 tokens to exercise the entire acceptance catalogue"* and presented it as
resource usage. The 12,800 is the sum of declared fixture numbers. It should have been traced
before it was repeated. `modelCalls` (22) is real — it is counted at `model.ts:66`.

## What is *not* affected

**Context characters are genuinely measured.** `model.ts:96` accumulates
`contextCharsSent` from a length passed in by the caller, and the bench's
selective-versus-full comparison (42,328 vs 51,818 chars, 9,490 avoided, 18%) is computed from
real document text. Token counts are relayed; character counts are counted. The distinction
is the whole finding.

## Not in the mistakes file

`docs/log/2026-09-16-mistakes.md` records eleven defects, and this is not one of them. It
survived for the reason that file names: a wrong assumption that reads as a decision. A
column headed `Tokens`, printed beside four counters that are real, does not invite the
question of where it came from.

## Not fixed

This is recorded, not repaired. The observer's instruction for this task was to monitor and
report rather than to change the system, and the two candidate repairs are design decisions
rather than typos:

- **measure it** — read `prompt_eval_count`/`eval_count` from the Ollama response and carry
  them through `ModelResponse.tokens`, which makes `maxTokens` live and makes the
  `budget-exhausted` scenario mean something on a real model; or
- **declare it** — rename the column to what it is (`Declared tokens`), document that the
  value is asserted by the model implementation, and keep the budget advisory

Doing neither leaves a number in a report that a reader will take for a measurement.
