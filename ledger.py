#!/usr/bin/env python3
"""
The system ledger.

One snapshot of where everything stands: every repository at its current revision, what
changed in each, and the state of every submission. Written to `reports/ledger.md` and
`reports/ledger.json` so it lands in git and stays there.

**Every field is read, never typed.** Revisions come from `git`, submission state comes from
`results/submissions.json` (which itself comes from the Kaggle API), and the rendition
measurements come from `reports/versions.json` (which itself comes from running the
renditions). A ledger a person fills in is a ledger that drifts from the truth the first
week nobody updates it.

**It is a snapshot, not a log.** Re-running it rewrites the same two files. The history of
what the system did lives in `git log`, which is the only place it can be trusted — a second
hand-maintained log would be a second thing to keep in step, and the two would disagree.

  python3 ledger.py
  python3 ledger.py --json
"""

from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

HARNESS = Path(__file__).resolve().parent
ROOT = HARNESS.parent
REPORTS = HARNESS / "reports"

# Every tree this work touches, and the repository each one answers to. `algorithm-main` is a
# worktree of `algorithm`, so it shares that repository and has no remote of its own.
REPOS = [
    ("algorithm", "Ashee-Softworks/algorithm"),
    ("algorithm-main", "(worktree of algorithm)"),
    ("asheeas", "Ashee-Softworks/asheeas"),
    ("transpiler", "Ashee-Softworks/transpiler"),
    ("arc-agi-3-staging", "Ashee-Softworks/arc-agi-3"),
    ("harness", "Ashee-Softworks/asheeas-harness"),
    ("ashee-chat", "Ashee-Softworks/ashee-chat"),
    ("kaggriculture", "Ashee-Softworks/kaggriculture"),
]

COMMITS_SHOWN = 5


def git(repo: Path, *args: str) -> str:
    if not (repo / ".git").exists():
        return ""
    try:
        return subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return ""


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def repo_state(name: str, remote: str) -> dict:
    path = ROOT / name
    if not (path / ".git").exists():
        return {"name": name, "remote": remote, "present": False, "note": "not a git repository"}

    log = []
    for line in git(path, "log", f"-{COMMITS_SHOWN}", "--pretty=%h%x09%cI%x09%s").split("\n"):
        parts = line.split("\t")
        if len(parts) >= 3:
            log.append({"sha": parts[0], "date": parts[1], "subject": parts[2]})

    dirty = [line for line in git(path, "status", "--porcelain").split("\n") if line.strip()]
    return {
        "name": name,
        "remote": remote,
        "present": True,
        "branch": git(path, "branch", "--show-current"),
        "head": git(path, "rev-parse", "HEAD")[:9],
        "headDate": git(path, "log", "-1", "--pretty=%cI"),
        "headSubject": git(path, "log", "-1", "--pretty=%s"),
        "dirtyFiles": len(dirty),
        "commits": log,
    }


def submission_state() -> dict:
    """The submission ledger, reduced to what a reader of this file needs."""
    ledger = read_json(ROOT / "kaggriculture" / "results" / "submissions.json")
    if not ledger:
        return {"present": False, "submissions": []}

    rows = []
    for entry in ledger.get("submissions", []):
        kaggle = entry.get("kaggle") or {}
        rows.append(
            {
                "submissionId": entry.get("submissionId"),
                "attemptedAt": entry.get("attemptedAt"),
                "message": entry.get("message"),
                "outcome": entry.get("outcome"),
                "agentCommit": entry.get("agentCommit"),
                "agentSha256": entry.get("agentSha256"),
                "status": kaggle.get("status"),
                "score": kaggle.get("score"),
                "history": [
                    {"at": h.get("at"), "status": h.get("status"), "score": h.get("score")}
                    for h in entry.get("history", [])
                ],
            }
        )
    return {"present": True, "submissions": rows, "refreshes": len(ledger.get("refreshes") or [])}


def episode_state() -> list:
    """The extracted episode results, which are committed beside the code."""
    found = []
    for path in sorted((ROOT / "kaggriculture" / "results" / "episodes").glob("*.json")):
        data = read_json(path)
        if not data:
            continue
        players = data.get("players") or []
        found.append(
            {
                "episode": path.stem,
                "steps": data.get("steps"),
                "rewards": [p.get("reward") for p in players],
                "quadrants": [p.get("quadrants") for p in players],
            }
        )
    return found


def rendition_state() -> dict:
    """The harness's own measurement, reduced."""
    report = read_json(HARNESS / "reports" / "versions.json")
    if not report:
        return {"present": False}
    rows = report.get("renditions", [])
    return {
        "present": True,
        "measuredOn": report.get("measuredOn"),
        "count": len(rows),
        "ran": sum(1 for row in rows if row.get("status") == "ran"),
        "meanAccuracy": round(sum(row.get("accuracy") or 0 for row in rows) / len(rows), 4) if rows else None,
        "native": (report.get("native") or {}).get("status"),
    }


def competitor_state() -> dict:
    """Reconnaissance, which is regenerated on every harness run."""
    data = read_json(HARNESS / "reports" / "competitions.json")
    if not data:
        return {"present": False}
    return {
        "present": True,
        "measuredOn": data.get("measuredOn"),
        "competitions": [
            {
                "slug": row.get("slug"),
                "found": row.get("found"),
                "reward": row.get("reward"),
                "entered": row.get("userHasEntered"),
                "rank": row.get("userRank"),
                "rules": (row.get("rules") or {}).get("verdict"),
            }
            for row in data.get("competitions", [])
        ],
    }


def build() -> dict:
    return {
        "snapshotAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "note": (
            "Every field is read from git, from results/submissions.json or from "
            "reports/*.json, and none is typed. This is a snapshot and is rewritten on each "
            "run; the history of what the system did lives in git log."
        ),
        "repositories": [repo_state(name, remote) for name, remote in REPOS],
        "submissions": submission_state(),
        "episodes": episode_state(),
        "renditions": rendition_state(),
        "competitions": competitor_state(),
    }


def render(data: dict) -> str:
    lines = [
        "# System ledger",
        "",
        f"Snapshot taken {data['snapshotAt']}.",
        "",
        data["note"],
        "",
        "## Repositories",
        "",
        "| tree | repository | branch | head | dirty | head date |",
        "|---|---|---|---|---|---|",
    ]
    for repo in data["repositories"]:
        if not repo.get("present"):
            lines.append(f"| `{repo['name']}` | {repo['remote']} | — | — | — | {repo.get('note')} |")
            continue
        lines.append(
            f"| `{repo['name']}` | {repo['remote']} | {repo.get('branch')} | "
            f"`{repo.get('head')}` | {repo.get('dirtyFiles')} | {str(repo.get('headDate'))[:19]} |"
        )

    lines += ["", "## Submissions", ""]
    submissions = data.get("submissions") or {}
    if not submissions.get("present") or not submissions.get("submissions"):
        lines += ["None recorded.", ""]
    else:
        lines += ["| id | attempted | outcome | status | score | agent commit |", "|---|---|---|---|---|---|"]
        for row in submissions["submissions"]:
            lines.append(
                f"| {row.get('submissionId') or '—'} | {row.get('attemptedAt', '—')} | "
                f"{row.get('outcome', '—')} | {row.get('status', '—')} | "
                f"{row.get('score') if row.get('score') is not None else '—'} | "
                f"`{(row.get('agentCommit') or '—')[:9]}` |"
            )
        lines.append("")

    episodes = data.get("episodes") or []
    if episodes:
        lines += ["### Episodes", "", "| episode | steps | rewards | quadrants |", "|---|---|---|---|"]
        for row in episodes:
            lines.append(
                f"| {row['episode']} | {row.get('steps')} | {row.get('rewards')} | {row.get('quadrants')} |"
            )
        lines.append("")

    lines += ["## Renditions measured", ""]
    renditions = data.get("renditions") or {}
    if renditions.get("present"):
        lines += [
            f"- measured {renditions.get('measuredOn')}",
            f"- {renditions.get('count')} renditions, {renditions.get('ran')} ran",
            f"- mean accuracy {renditions.get('meanAccuracy')}",
            f"- native component: {renditions.get('native')}",
            "",
        ]
    else:
        lines += ["No measurement yet.", ""]

    lines += ["## Competitions", ""]
    competitions = data.get("competitions") or {}
    if competitions.get("present"):
        lines += ["| competition | found | prize | entered | rank | rules |", "|---|---|---|---|---|---|"]
        for row in competitions["competitions"]:
            lines.append(
                f"| `{row.get('slug')}` | {row.get('found')} | {row.get('reward') or '—'} | "
                f"{row.get('entered')} | {row.get('rank') or '—'} | {row.get('rules')} |"
            )
        lines.append("")
    else:
        lines += ["No reconnaissance yet.", ""]

    lines += ["## Recent commits, by tree", ""]
    for repo in data["repositories"]:
        if not repo.get("present"):
            continue
        lines += [f"**`{repo['name']}`** — {repo.get('headSubject', '')}", ""]
        for commit in repo.get("commits", []):
            lines.append(f"- `{commit['sha']}` {commit['date'][:19]} {commit['subject'][:110]}")
        lines.append("")

    return "\n".join(lines)


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Snapshot the system ledger.")
    parser.add_argument("--json", action="store_true", help="print the JSON as well")
    args = parser.parse_args()

    REPORTS.mkdir(parents=True, exist_ok=True)
    data = build()
    (REPORTS / "ledger.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    (REPORTS / "ledger.md").write_text(render(data), encoding="utf-8")

    present = [r for r in data["repositories"] if r.get("present")]
    clean = sum(1 for r in present if r.get("dirtyFiles") == 0)
    submissions = len((data.get("submissions") or {}).get("submissions") or [])
    print(
        f"trees {len(present)} · clean {clean} · submissions {submissions} · "
        f"episodes {len(data.get('episodes') or [])}"
    )
    print(f"report: {REPORTS / 'ledger.md'}")

    if args.json:
        print(json.dumps(data, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
