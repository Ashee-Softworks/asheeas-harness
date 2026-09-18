#!/usr/bin/env python3
"""
Kaggle reconnaissance, read-only.

Answers three questions per competition, and answers them from the API rather than from a
README:

  1. Does it exist, what pays, and when does it close?
  2. Has this account entered it?
  3. Has this account accepted its rules -- the thing that turns a 403 into a download?

It does not accept rules, enter competitions, form teams, or submit anything. Accepting a
competition's rules is a legal acceptance made by the account holder, so this tool reports
the URL you have to open and stops there.

  python3 recon.py                       # the named competitions
  python3 recon.py --out reports/        # where to write the report

Standard library only: urllib, json, pathlib.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

TOKEN_PATH = Path.home() / ".kaggle" / "access_token"
API = "https://www.kaggle.com/api/v1"

# The competitions named in the request, by slug. A slug that returns no exact match is
# reported as absent rather than guessed at.
NAMED = [
    "arc-prize-2026-arc-agi-2",
    "arc-prize-2026-arc-agi-3",
    "arc-prize-2026-paper-track",
    "biohub-cell-tracking-during-development",
    "enveda-CASMI26-molecule-id-mass-spectra",
    "kaggriculture",
]


def token() -> str:
    if not TOKEN_PATH.exists():
        raise SystemExit(f"no token at {TOKEN_PATH}")
    value = TOKEN_PATH.read_text().strip()
    if not value:
        raise SystemExit(f"token at {TOKEN_PATH} is empty")
    return value


def get(url: str, bearer: str, timeout: int = 20, attempts: int = 2):
    """
    Return (status, parsed-json-or-None, raw-text). Never raises for an HTTP status.

    Two attempts with a pause between them, because Kaggle throttles a burst of requests and a
    single slow socket is not evidence that the competition is absent. A request that never
    answers is retried once and then reported as unreachable -- not as a 403 and not as a 404,
    because those two mean different things and neither means "the network was slow".
    """
    last = "not attempted"
    for attempt in range(attempts):
        request = urllib.request.Request(url, headers={"Authorization": f"Bearer {bearer}"})
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read().decode("utf-8", "replace")
                try:
                    return response.status, json.loads(raw), raw
                except json.JSONDecodeError:
                    return response.status, None, raw
        except urllib.error.HTTPError as error:
            return error.code, None, error.read(65536).decode("utf-8", "replace")
        except urllib.error.URLError as error:
            last = f"{type(error).__name__}: {error.reason}"
        except (TimeoutError, OSError) as error:
            last = f"{type(error).__name__}: {error}"
        if attempt + 1 < attempts:
            time.sleep(1.5)
    return 0, None, f"unreachable after {attempts} attempts ({last})"


def status_of(url: str, bearer: str, timeout: int = 20, attempts: int = 2):
    """
    The status code, and nothing else.

    **The body is never read, and that is the point.** For a competition whose rules *are*
    accepted, `download-all` does not answer with a redirect or a listing — it streams the
    competition's dataset. Reading that body is a multi-gigabyte mistake, and it looked
    exactly like a hung network for a while. The status arrives in the response headers, so
    the connection is opened, the status is taken, and the connection is closed.

    `HEAD` is not used instead, because this route answers `404` to a `HEAD` even where a
    `GET` would be answered. A probe that changed the answer would be worse than no probe.
    """
    last = "not attempted"
    for attempt in range(attempts):
        request = urllib.request.Request(
            url, headers={"Authorization": f"Bearer {bearer}"}, method="GET"
        )
        try:
            response = urllib.request.urlopen(request, timeout=timeout)
            status = response.status
            response.close()  # the body is abandoned unread
            return status, ""
        except urllib.error.HTTPError as error:
            error.close()
            return error.code, ""
        except urllib.error.URLError as error:
            last = f"{type(error).__name__}: {error.reason}"
        except (TimeoutError, OSError) as error:
            last = f"{type(error).__name__}: {error}"
        if attempt + 1 < attempts:
            time.sleep(1.5)
    return 0, f"unreachable after {attempts} attempts ({last})"


def find(slug: str, bearer: str) -> dict:
    """Look the slug up by search and keep only an exact ref match."""
    status, body, raw = get(f"{API}/competitions/list?search={slug}&page=1", bearer)
    if status != 200 or not isinstance(body, list):
        return {
            "slug": slug,
            "found": False,
            "probeStatus": status,
            "reason": raw.strip()[:200] or "no response",
        }
    for entry in body:
        ref = (entry.get("ref") or "").rstrip("/").split("/")[-1]
        if ref == slug:
            return {"slug": slug, "found": True, "raw": entry}
    near = [((c.get("ref") or "").rstrip("/").split("/")[-1]) for c in body]
    return {"slug": slug, "found": False, "probeStatus": status, "similar": near[:6]}


def rules_probe(slug: str, bearer: str) -> dict:
    """
    Ask for the data, without taking it. 200 means the account may download. 403 means it may
    not -- which on Kaggle means the rules have not been accepted by the account holder. 404
    means there are no files to download at all (an interactive benchmark has none). Anything
    else is recorded as unknown rather than interpreted.
    """
    status, note = status_of(f"{API}/competitions/data/download-all/{slug}", bearer)
    if status == 200:
        return {
            "code": 200,
            "verdict": "accepted",
            "meaning": "this account may download; the body was not read",
        }
    if status == 403:
        return {
            "code": 403,
            "verdict": "not-accepted",
            "meaning": "the account holder has not accepted this competition's rules",
            "action": f"https://www.kaggle.com/competitions/{slug}/rules",
        }
    if status == 404:
        return {
            "code": 404,
            "verdict": "no-data",
            "meaning": "no downloadable data files; nothing is gated behind the rules here",
        }
    return {"code": status, "verdict": "unknown", "meaning": note or "no response"}


def collect() -> dict:
    bearer = token()
    entries = []
    for slug in NAMED:
        look = find(slug, bearer)
        if not look["found"]:
            entries.append(
                {
                    "slug": slug,
                    "found": False,
                    "probeStatus": look.get("probeStatus"),
                    "similar": look.get("similar", []),
                    "reason": look.get("reason"),
                }
            )
            continue
        raw = look["raw"]
        entries.append(
            {
                "slug": slug,
                "found": True,
                "id": raw.get("id"),
                "title": raw.get("title"),
                "organisation": raw.get("organizationName"),
                "category": raw.get("category"),
                "reward": raw.get("reward"),
                "metric": raw.get("evaluationMetric"),
                "maxTeamSize": raw.get("maxTeamSize"),
                "license": raw.get("licenseName"),
                "deadline": raw.get("deadline"),
                "teamCount": raw.get("teamCount"),
                "userHasEntered": raw.get("userHasEntered"),
                "userRank": raw.get("userRank"),
                "url": raw.get("url"),
                "rules": rules_probe(slug, bearer),
            }
        )
    return {
        "measuredOn": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "account": "the holder of ~/.kaggle/access_token",
        "method": "Kaggle API v1, read-only. No rules accepted, no competition entered, nothing submitted.",
        "competitions": entries,
    }


def render(data: dict) -> str:
    found = [c for c in data["competitions"] if c.get("found")]
    open_rules = [c for c in found if c["rules"]["verdict"] == "not-accepted"]
    entered = [c for c in found if c.get("userHasEntered")]
    missing = [c for c in data["competitions"] if not c.get("found")]

    lines = [
        "# Kaggle reconnaissance",
        "",
        f"Measured {data['measuredOn']}. {data['method']}",
        "",
        "## Outcome",
        "",
        "| Measure | Value |",
        "|---|---|",
        f"| Competitions looked for | {len(data['competitions'])} |",
        f"| Found | {len(found)} |",
        f"| Entered by this account | {len(entered)} |",
        f"| Rules not yet accepted | {len(open_rules)} |",
        f"| Not found | {len(missing)} |",
        "",
        "## Per competition",
        "",
        "| Competition | Prize | Entered | Rank | Rules | Deadline |",
        "|---|---|---|---|---|---|",
    ]
    for c in data["competitions"]:
        if not c.get("found"):
            lines.append(f"| `{c['slug']}` | — | — | — | **not found** | — |")
            continue
        rank = c.get("userRank") or 0
        lines.append(
            f"| [{c['title']}]({c['url']}) | {c.get('reward') or '—'} "
            f"| {'yes' if c.get('userHasEntered') else 'no'} "
            f"| {rank if rank else '—'} "
            f"| {c['rules']['verdict']} | {str(c.get('deadline') or '—')[:16]} |"
        )
    lines.append("")

    if open_rules:
        lines += [
            "## The blocker, and it is one click each",
            "",
            "These return `403 Forbidden` until the rules are accepted. The API cannot accept them",
            "for you: acceptance is a legal act by the account holder, so this tool names the page",
            "and stops. Open each, read it, click *I Understand and Accept*:",
            "",
        ]
        for c in open_rules:
            lines.append(f"- [{c['title']}]({c['rules']['action']}) — {c.get('reward')}")
        lines.append("")

    if missing:
        lines += ["## Slugs that did not resolve", ""]
        for c in missing:
            near = ", ".join(f"`{s}`" for s in c.get("similar", [])) or "nothing similar"
            if c.get("probeStatus") == 0:
                lines.append(f"- `{c['slug']}` — **unreachable**, not absent: {c.get('reason')}")
            else:
                lines.append(
                    f"- `{c['slug']}` — not found on the API (HTTP {c.get('probeStatus')}); "
                    f"similar slugs: {near}"
                )
        lines.append("")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only Kaggle reconnaissance.")
    parser.add_argument("--out", default=str(Path(__file__).parent / "reports"))
    parser.add_argument("--json", action="store_true", help="also print the raw JSON")
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    data = collect()
    (out / "competitions.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    (out / "competitions.md").write_text(render(data), encoding="utf-8")

    found = sum(1 for c in data["competitions"] if c.get("found"))
    open_rules = sum(
        1 for c in data["competitions"] if c.get("found") and c["rules"]["verdict"] == "not-accepted"
    )
    print(f"competitions found {found}/{len(data['competitions'])} · rules not accepted {open_rules}")
    print(f"report: {out / 'competitions.md'}")
    if args.json:
        print(json.dumps(data, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
