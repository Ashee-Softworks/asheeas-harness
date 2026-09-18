# System ledger

Snapshot taken 2026-09-18T06:15:10+00:00.

Every field is read from git, from results/submissions.json or from reports/*.json, and none is typed. This is a snapshot and is rewritten on each run; the history of what the system did lives in git log.

## Repositories

| tree | repository | branch | head | dirty | head date |
|---|---|---|---|---|---|
| `algorithm` | Ashee-Softworks/algorithm | main | `d57105c83` | 0 | 2026-09-17T20:09:33 |
| `algorithm-main` | (worktree of algorithm) |  | `` | 0 |  |
| `asheeas` | Ashee-Softworks/asheeas | main | `a94e2d305` | 0 | 2026-09-17T18:08:36 |
| `transpiler` | Ashee-Softworks/transpiler | main | `52548138c` | 0 | 2026-09-17T01:09:31 |
| `arc-agi-3-staging` | Ashee-Softworks/arc-agi-3 | main | `a56a7450f` | 5 | 2026-09-17T22:52:24 |
| `harness` | Ashee-Softworks/asheeas-harness | main | `8b61d6655` | 3 | 2026-09-18T05:32:25 |
| `ashee-chat` | Ashee-Softworks/ashee-chat | main | `15e4814aa` | 2 | 2026-09-18T05:02:19 |
| `kaggriculture` | Ashee-Softworks/kaggriculture | main | `7772ab13b` | 0 | 2026-09-18T06:14:22 |

## Submissions

| id | attempted | outcome | status | score | agent commit |
|---|---|---|---|---|---|
| 56322264 | 2026-09-18T05:59:32+00:00 | accepted | complete | 484.7 | `f23571e75` |

### Episodes

| episode | steps | rewards | quadrants |
|---|---|---|---|
| 110329561 | 720 | [3869.0, 3869.0] | [['NW', 'NE'], ['NW', 'NE']] |
| 110330784 | 720 | [4087.0, 91360.0] | [['NW', 'NE'], ['NW', 'NE', 'SW']] |

## Renditions measured

- measured 2026-09-18T05:06:22.503Z
- 11 renditions, 7 ran
- mean accuracy 0.6364
- native component: ran

## Competitions

| competition | found | prize | entered | rank | rules |
|---|---|---|---|---|---|
| `arc-prize-2026-arc-agi-2` | True | 700,000 Usd | False | — | not-accepted |
| `arc-prize-2026-arc-agi-3` | True | 850,000 Usd | True | 2704 | accepted |
| `arc-prize-2026-paper-track` | True | 450,000 Usd | False | — | not-accepted |
| `biohub-cell-tracking-during-development` | True | 60,000 Usd | False | — | not-accepted |
| `enveda-CASMI26-molecule-id-mass-spectra` | True | 50,000 Usd | False | — | not-accepted |
| `kaggriculture` | True | 50,000 Usd | False | — | not-accepted |

## Recent commits, by tree

**`algorithm`** — chore(reports): commit the scenario bench, and record that it overwrote a different one

- `d57105c` 2026-09-17T20:09:33 chore(reports): commit the scenario bench, and record that it overwrote a different one
- `578c581` 2026-09-17T14:26:35 feat(record): join the action table to the engine, and write the first integration test
- `06c71e2` 2026-09-17T06:01:04 feat(record): the action table -- good, bad, neutral, explanation and error
- `0f9c263` 2026-09-17T04:54:54 fix(vendor): stop recording fetched runners as unresolvable gitlinks
- `88ecf1c` 2026-09-17T03:22:27 Fix formatter violation in the second-opinion usage line

**`algorithm-main`** — 


**`asheeas`** — chore(gitignore): keep the algorithm CLI's cache out of the composition

- `a94e2d3` 2026-09-17T18:08:36 chore(gitignore): keep the algorithm CLI's cache out of the composition
- `92dd163` 2026-09-17T18:05:29 fix(user-prompt): verification.json was unparseable, so the algorithm could never read it
- `db42f49` 2026-09-17T17:59:37 chore: commit Ashee's note in PROJECT.md, found uncommitted
- `b753204` 2026-09-17T17:58:42 docs(inherited): how I introduce myself to the team, in my own words
- `4b0273a` 2026-09-17T11:05:39 chore(gitignore): keep the nested client clone out of the composition

**`transpiler`** — feat(frontend): open the type environment — Node types, NodeNext resolution, .ts specifiers — while the runtime stays closed

- `5254813` 2026-09-17T01:09:31 feat(frontend): open the type environment — Node types, NodeNext resolution, .ts specifiers — while the runtim
- `31958da` 2026-09-16T21:34:17 chore(transpiler): verified improvement, round 1 — 26 file(s) changed (4/4 gates passed)
- `c5f65e3` 2026-09-16T20:52:36 docs(transpiler): admin guide, journal, decision records DD-001..DD-003 recording what F-001 forced
- `c06007f` 2026-09-16T20:21:53 chore(transpiler): verified improvement, round 1 — 2 file(s) changed (4/4 gates passed)
- `2f86e05` 2026-09-16T18:11:01 chore(transpiler): verified improvement, round 1 — 2 file(s) changed (4/4 gates passed)

**`arc-agi-3-staging`** — docs: how to test ARC-AGI-3 against their server, with the output it actually produced

- `a56a745` 2026-09-17T22:52:24 docs: how to test ARC-AGI-3 against their server, with the output it actually produced
- `3f8e953` 2026-09-17T20:10:23 feat: the ARC-AGI-3 harness, written blind and frozen before any game is observed

**`harness`** — feat(recon): find out what a competition is before agreeing to its terms

- `8b61d66` 2026-09-18T05:32:25 feat(recon): find out what a competition is before agreeing to its terms
- `47a19f7` 2026-09-18T05:07:54 chore(reports): the measurements, re-taken
- `6ebb903` 2026-09-18T04:58:29 feat(harness): measure every rendition of the algorithm, and read the competitions before entering them

**`ashee-chat`** — feat(chat): a local-model interface on Next and AsheeUI, straight to the model

- `15e4814` 2026-09-18T05:02:19 feat(chat): a local-model interface on Next and AsheeUI, straight to the model

**`kaggriculture`** — feat(results): a submission ledger, the episode analyses, and the real outcome

- `7772ab1` 2026-09-18T06:14:22 feat(results): a submission ledger, the episode analyses, and the real outcome
- `f23571e` 2026-09-18T05:30:31 feat(kaggriculture): an agent, and a local harness that runs Kaggle's own interpreter
