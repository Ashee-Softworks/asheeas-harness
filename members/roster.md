# Member roster

**No passwords. No tokens. No API keys. That is the whole design, and it costs nothing.**

The reason is not that members are untrustworthy — it is that a central password file is a
liability whether or not anyone is malicious. Laptops get lost, files get committed by
accident, backups leak. A roster of *usernames and status* has none of that exposure and is
more useful, because the credential lives with its owner and `lib/access.ts` can ask GitHub
for the truth instead of trusting a copy of it.

Track the **invite**, not the **secret**.

```
member,github_username,invite_sent,date_sent,joined_org,two_factor,linkedin,notes
Member-01,,n,,,,"",each member creates their own GitHub account, then adds their own SSH key
Member-02,,n,,,,"",
Member-03,,n,,,,"",
Member-04,,n,,,,"",
Member-05,,n,,,,"",
Member-06,,n,,,,"",
Member-07,,n,,,,"",
Member-08,,n,,,,"",
Member-09,,n,,,,"",
Member-10,,n,,,,"",
```

## Onboarding, per member — about 4 minutes each

1. **They create their own GitHub account.** Free. One account per person is GitHub's term;
   one person creating ten would risk all of them, including the org.
2. **They add their own SSH key** (`ssh-keygen -t ed25519`, then paste the `.pub`).
3. **You invite them** to `Ashee-Softworks` — Settings → People → Invite.
4. **They enable 2FA.** Required by the org, and it is what makes a leaked password survivable.
5. **Same for LinkedIn** — each person creates their own profile.
6. Fill in their username above. Nothing else to hand over.

## The access model, corrected

**An earlier version of this file said inviting a member to the GitHub org is sufficient.
That was wrong, and it was wrong in the most expensive way: it was checkable and it was not
checked.**

There are **two access models in the platform, and the one that is documented is not the one
that runs.**

| file | what it would gate on | reached by a request? |
| --- | --- | --- |
| `lib/access.ts` — `decideAccess(login, token)` | **GitHub org membership** | **No.** Nothing calls it. |
| `lib/credentials.ts` + `middleware.ts` + `app/api/enter/route.ts` | a **bearer token** whose SHA-256 is in `ASHEE_ACCESS_TOKENS` | **Yes.** This is the real door. |

`decideAccess` asks `https://api.github.com/orgs/Ashee-Softworks/memberships/{login}` and needs
a GitHub credential passed **in as arguments**. Nothing in the request path obtains one. The
middleware calls `verifySession` (an HMAC check over a cookie) and `/api/enter` calls
`verifyToken` (a hash comparison). `access.ts` supplies `HOLDING_PAGE` and the `ORGANISATION`
label and is otherwise **dead code on the request path**.

So onboarding is **two** steps, not one:

1. **Invite to the org** — necessary, and not sufficient. This satisfies `access.ts`, which
   nothing consults.
2. **Issue an access token** and add its hash to `ASHEE_ACCESS_TOKENS`. **This is what
   actually admits anyone.** Without it a member of the org is redirected to the holding page
   exactly like a stranger.

And `lib/workspaces.ts` publishes the opposite to the world:

> *"A single access gate in front of every service, **decided by organisation membership**"*

That sentence is not true of the running system. A non-member holding a token gets in; a member
without one does not.

## Consequences worth knowing before ten people are onboarded

- **A session is not tied to a person.** `/api/enter` signs `{ login: ORGANISATION, expiresAt }`
  — the *same* login for every token. `x-ashee-session` is therefore a constant, "who is in"
  cannot be answered, and a per-member feature has no foundation to build on.
- **Rotating a token does not revoke anyone.** Sessions are signed cookies, 14 days, with no
  store and no denylist. Change `ASHEE_ACCESS_TOKENS` and every already-issued cookie still
  works until it expires. There is currently **no way to lock anyone out.**
- **Both of these fail closed**, which is right. They do not fail *safe* for revocation.

The roster below stays useful for coordination. It is not, and never was, the authorisation
source.

