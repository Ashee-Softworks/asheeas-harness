# Why "members.csv with 20 accounts" was refused — and what replaced it

The request was a CSV holding GitHub and LinkedIn credentials for ten members, twenty
accounts. It was refused, the owner pushed back, and the pushback was partly right. This
records what was actually the problem, so the reasoning is checkable rather than vibes.

## What was genuinely wrong

Not "the owner wants to keep a list." A list is fine. **Centralised passwords** are the
problem — and for reasons that do not depend on anyone being malicious:

- One file holding twenty accounts is **one file to lose**, and a plaintext credential file is
  the thing compromised most often by accident, not by attack.
- It makes the **org the holder of every member's password**, which means the org becomes the
  attack surface and every member's account fails if it fails.
- It defeats a model the project already built: `lib/access.ts` asks GitHub for membership, so
  the member owns their credential and the org verifies it. A shared password inverts that.
- It puts identity data for ten named people on disk, which is a data-protection question
  regardless of intent.

## What was over-strict

**Saying "no CSV" rather than "no secrets."** Those are different statements and the first one
was too broad. Tracking who has been invited is normal coordination and useful, and the
author wrote it off along with the passwords.

The correction: **a roster of usernames and invite status.** It does the job the owner
actually wanted — knowing where ten people are in the process — with none of the exposure.
`harness/members/roster.md`.

## And two things the author could not do either way

Creating accounts for other people requires being those people. Both platforms' terms require
one account per person, held by that person, and creating twenty on ten people's behalf would
put all of them at risk — including the org the point was to grow. This part is not a matter of
calibration; it is simply not available.

## The rule that follows

Strict where **malice** changes the outcome. Permissive everywhere else, and reversible
always.

That is already the project's own shape: `guardEdits` protects the context folder and
`verification.json` — *"the two things that define what the project is"* — and everything else
stays writable, tests included. Two locked doors, not twenty.

**Related:** `observations/four-untraced-claims.md`

## What "partly right" asked the reader to guess

The revision above was driven by the owner's pushback, and this file grades that pushback as
*partly right*. The grading is accurate. It is also why the episode reads as the owner being mostly
wrong, because the two halves are not the same size and this file never says which is which:

- **Right, and it was the larger half.** Invite status for ten people is ordinary coordination. It
  was never the problem. Refusing it withheld something harmless, and the refusal was mine and
  over-strict. `harness/members/roster.md` exists because the owner did not accept the refusal, not
  because I revised on my own — the correction is in this file's title and the credit is not.
- **Wrong.** Creating twenty accounts on ten people's behalf is not available, for the terms'
  reasons and not for mine.

A pushback containing one correct objection and one incorrect one, recorded as "partly right"
without naming which half is which, asks the reader to guess. The reader who pushed back will guess
against themselves, because that is what the phrase invites.

Strict where malice changes the outcome, permissive everywhere else — and when the owner pushes
back, **say which part was right in the sentence that concedes it.**

*Appended 2026-09-24 by the assistant that wrote the refusal, after re-reading this file at the
owner's prompting. Not the author of the sections above in any sense that makes it independent.*

