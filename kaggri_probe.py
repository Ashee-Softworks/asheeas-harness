#!/usr/bin/env python3
"""
Everything the API will say about one competition, without entering it.

Read-only. It asks for the listing record, the data file list, and the rules page's own
description of itself, and prints whatever comes back -- including the refusals, because a
403 here is information about the competition's state and not an error in this script.

  python3 kaggri_probe.py
"""

import json
import pathlib
import urllib.error
import urllib.request

SLUG = "kaggriculture"
API = "https://www.kaggle.com/api/v1"
TOKEN = pathlib.Path.home().joinpath(".kaggle/access_token").read_text().strip()


def head(url: str, method: str = "GET") -> tuple[int, str]:
    """Status and the first kilobyte of the body, or the error message. Body never fully read."""
    request = urllib.request.Request(
        url, headers={"Authorization": f"Bearer {TOKEN}"}, method=method
    )
    try:
        response = urllib.request.urlopen(request, timeout=25)
        body = response.read(4096).decode("utf-8", "replace")
        status = response.status
        response.close()
        return status, body
    except urllib.error.HTTPError as error:
        text = error.read(4096).decode("utf-8", "replace")
        error.close()
        return error.code, text
    except Exception as error:  # noqa: BLE001
        return 0, f"{type(error).__name__}: {error}"


def main() -> int:
    print("=" * 72)
    print("1. the listing record")
    print("=" * 72)
    status, body = head(f"{API}/competitions/list?search={SLUG}&page=1")
    print(f"HTTP {status}")
    try:
        listings = json.loads(body)
        for entry in listings:
            ref = (entry.get("ref") or "").rstrip("/").split("/")[-1]
            if ref != SLUG:
                continue
            for key in (
                "title", "description", "organizationName", "category", "reward",
                "evaluationMetric", "maxTeamSize", "teamCount", "enableTeamModel",
                "licenseName", "deadline", "url", "userHasEntered", "userRank", "id",
            ):
                if key in entry:
                    print(f"  {key:20} = {entry[key]}")
            tags = entry.get("tags") or []
            print(f"  {'tags':20} = {[t.get('name') for t in tags][:12]}")
    except json.JSONDecodeError:
        print(body[:800])

    print()
    print("=" * 72)
    print("2. the routes that matter, and what they answer right now")
    print("=" * 72)
    routes = [
        ("data file list", f"{API}/competitions/data/list/{SLUG}"),
        ("download all", f"{API}/competitions/data/download-all/{SLUG}"),
        ("leaderboard", f"{API}/competitions/{SLUG}/leaderboard/view"),
        ("the rules page", f"https://www.kaggle.com/competitions/{SLUG}/rules"),
        ("the data page", f"https://www.kaggle.com/competitions/{SLUG}/data"),
        ("the overview page", f"https://www.kaggle.com/competitions/{SLUG}/overview"),
    ]
    for label, url in routes:
        status, body = head(url)
        first = body.strip().split("\n")[0][:220] if body.strip() else "(empty body)"
        print(f"  {label:20} HTTP {status:>4}  {first}")

    print()
    print("=" * 72)
    print("3. is there a public simulation package the task runs on?")
    print("=" * 72)
    for name in ("kaggriculture", "kaggle-kaggriculture", "kaggri", "kaggle-environments"):
        status, body = head(f"https://pypi.org/pypi/{name}/json")
        verdict = "not published" if status == 404 else f"published (HTTP {status})"
        print(f"  pypi {name:24} {verdict}")

    status, body = head("https://api.github.com/search/repositories?q=kaggriculture")
    try:
        payload = json.loads(body)
        total = payload.get("total_count", "?")
        print(f"  github 'kaggriculture'      {total} repositor{'y' if total == 1 else 'ies'}")
        for item in (payload.get("items") or [])[:8]:
            print(f"      {item['full_name']}  ({item.get('language')})  {item.get('description')}")
    except json.JSONDecodeError:
        print(f"  github search failed: HTTP {status} {body[:200]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
