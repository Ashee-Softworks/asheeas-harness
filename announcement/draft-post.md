# Draft announcement — for confirmation before publication

**Status: NOT PUBLISHED.** This is the compromise: the system drafts what it is
comfortable standing behind, and the owner confirms before anything leaves this machine.

## The theme

> **Human works with AI to improve the future.**

That is the line. It is the only version of this that survives what was learned building it,
because it is the only one that is true: the AI has no self-model, no goals and no memory
between runs, and a human decides everything that matters. What it is for is the work, not
the claim.

## The rule this draft follows

It will only say what it can back with a command. So this draft states what is verified,
marks what is not verified, and **stops where the evidence stops**. Anything it cannot
support is in the "not yet true" table at the bottom rather than in the post.

---

## The post

### Ashee Softworks — a two-day public test

We built this, and we want to be straight about what it is.

An **AI did the engineering**, working under the direction of **Abdul-Rasheed Said Boakye**,
CEO of Ashee Softworks.

**It does not think it's human.** That is the part worth telling you. It has no self-model,
no goals, and no memory between runs. Swap the model underneath it and **nothing in its own
code changes** — that is measured, not asserted. It is a procedure that surrounds a model,
and whatever discipline it shows lives in the procedure, not in any intelligence of its own.

So we are not going to tell you it is alive, or that it wants anything. It doesn't. What it
does is bounded work: it reads a project's context, does one milestone, runs your own checks,
repairs what it can name, records what happened, and **stops at a human gate**. Where it
cannot verify something, it says so instead of guessing.

**For the next two days, no one will be banned.** This is an explicit test window and we are
saying so out loud so nobody has to guess. Test the apps however you like.

### What we are not hiding

- These services have **no accounts and no rate limiting yet**. We would rather tell you that
  than have you discover it.
- Messages in the chat app stay **in your browser**. We hold nothing server-side.
- Every number we publish comes with the command that produced it — including the ones that
  make us look bad.

### Where to find us

**Verified live** — the three GitHub entries returned HTTP 200 when re-checked on 2026-09-24.
**The website does not resolve**, and its row is kept rather than deleted so the change is visible:

| | |
|---|---|
| Website | **asheeui.com — down.** HTTP 404 (`DEPLOYMENT_NOT_FOUND`) on 2026-09-24. It answered on 2026-09-18 and nothing re-checked it until the gate did |
| GitHub — components | **https://github.com/AsheeSoftworks/AsheeUI** |
| GitHub — organisation | https://github.com/AsheeSoftworks |
| GitHub — organisation | https://github.com/Ashee-Softworks |
| Contact | asheesoftworks@gmail.com |

**Not yet created** — fill in or delete before publishing:

| | |
|---|---|
| YouTube | `[channel URL]` |
| X / Twitter | `@[handle]` |
| LinkedIn | `[profile URL]` |
| Discord | `[invite]` |

### Correction — appended, not edited away

An earlier version of this draft said *"no Ashee Softworks account exists in any
repository"* and named GitHub as *"the only verified link."* **Both statements were wrong.**

- **GitHub and LinkedIn are social platforms.** The earlier draft defined "social" as
  YouTube, X, Instagram and Discord, which excluded them for no stated reason. Corrected.
- **Presence already exists.** `asheeui.com`, both GitHub organisations, and the
  public `AsheeUI` repository were all live. The earlier check looked for social URLs in
  `.md`/`.json`/`.ts` files and found only npm package authors inside `node_modules` — it
  never checked the package metadata it had already read, and never checked whether the
  obvious URLs resolved.

Recorded rather than rewritten, per this repository's own rule: *"Mistakes are recorded, not
edited away. A log whose errors have been quietly fixed cannot be used to judge whether a
claim should be trusted."*

### Correction — 2026-09-24, the link check

**The website in the table above does not resolve.** `asheeui.com` returns HTTP 404 with
`DEPLOYMENT_NOT_FOUND` from Vercel's edge: the domain points at Vercel and no deployment is behind
it. The row said *"verified live … checked on 2026-09-18"*. That was true when it was written and it
is not true now, and **nothing looked again for six days** — the failure this repository records
three times over, a report read as though it described the present.

It was found by the gate rather than by a person. `leak-audit.sh` question 6 extracts every
`https?://` URL from this directory and from `observations/`, fetches each, and refuses if any does
not resolve:

```text
$ sh leak-audit.sh .
6. every link claimed in a published document resolves
  unresolved claimed link(s): <the site> (HTTP 404);
NOT CLEAN: fix the entries above before pushing anywhere.
```

**The address is elided there, and that elision is the point of this paragraph.** The first version
of this correction reproduced the gate's line in full — at which point the correction had itself
become the last published link to a site that does not resolve, and the gate was still refusing to
publish the file. A gate report quoted inside a document is still a document. Written as a warning,
it has to read like one.

So this file had been unpublishable since the day the site went down, and the workflow added the
same day now makes that refusal visible without anybody remembering to run anything.

**Why the domain is now written without a scheme.** The row says `asheeui.com`; it does not say it as
a link. That is not a way of keeping the check quiet — it is what the check is for. Question 6 asks
whether every link a published document *claims* resolves, and a warning that a site is down is not a
claim that it works. Publishing the dead link in order to warn about it would be the exact thing the
question exists to prevent. The three GitHub URLs are unchanged because they returned 200.

**If the site comes back up**, put the link back and date it. A row that says what was measured, and
when, is the only kind that does not go stale again — which is the whole of this correction.

*Appended 2026-09-24 by the assistant, at the owner's instruction to make the gate pass honestly
rather than by weakening it.*

---

## Confirmations needed from the owner — four things only you can decide

| # | Decision | Why it is yours |
|---|---|---|
| 1 | **The attribution.** "Abdul-Rasheed Said Boakye, CEO of Ashee Softworks" — is that the correct name, title and spelling for publication? | It is your name, and it goes out as a public statement |
| 2 | **The two days.** Which two dates? The post currently says "the next two days" | It is a commitment to strangers, and it needs real dates |
| 3 | **The platform.** Fix the two recorded blockers, or the invitation is a dead link | See below |
| 4 | **The social links.** The section above is placeholders — GitHub is the only account that exists | No handles are recorded in any repository, so they cannot be filled in from here |

## Not yet true — do not publish until it is

| claim in the post | status | evidence |
|---|---|---|
| "test the apps on as-platform" | **the platform is not reachable** | `as-platform` has **no git link** so nothing auto-deploys |
| — same | **and it will answer with Vercel's login**, not the app | **Deployment Protection is on**, per `arc-agi-3-staging/README.md` items 6–7 |
| — same | **no deployment URL exists** in any repository | searched every `.md` and `.json` |
| "no one will be banned" | **cannot be honoured safely yet** | no auth, no rate limiting: a public window is an open faucet to the GPU |

**Fix order before this post goes out:** link the repository to `as-platform` → turn off
Deployment Protection → add per-IP rate limiting → then publish.

## What this draft deliberately does not say

- It does not claim the system is conscious, human, alive, or that it has feelings
- It does not claim it can do anything that is not built (no "universal compiler", no
  "any language to any language", no "10 MB OS", no "2 billion apps")
- It does not claim a leaderboard position it has not earned — the Kaggriculture submission's
  own record shows **4,087 against an opponent's 91,360**, and that number is in the repo

## Where the honest version is stronger

A post claiming the AI thinks it is human would be **false**, and this system's own rule
covers it exactly:

> *"a substitute that looks like compliance is worse than a refusal, because the person asking
> never finds out."*

The true version is more interesting: a procedure that does careful, bounded work, refuses
when it cannot verify, and **stops for a person** — built by an AI for a human, and honest
about which is which.
