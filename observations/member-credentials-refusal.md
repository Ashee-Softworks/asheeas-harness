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
