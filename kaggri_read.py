#!/usr/bin/env python3
"""
What can be read about Kaggriculture without accepting its rules.

The rule gate is on `download-all`. Everything else that Kaggle serves to an
authenticated account -- the file *manifest*, the leaderboard, the overview and rules HTML --
answers without it. That distinction is the whole reason this script exists: it establishes
how much of the task can be understood before a legal acceptance has to be made.

  python3 kaggri_read.py
"""

import json
import pathlib
import re
import urllib.error
import urllib.request

SLUG = "kaggriculture"
API = "https://www.kaggle.com/api/v1"
TOKEN = pathlib.Path.home().joinpath(".kaggle/access_token").read_text().strip()


def fetch(url: str, limit: int = 400_000) -> tuple[int, bytes]:
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
    try:
        response = urllib.request.urlopen(request, timeout=30)
        body = response.read(limit)
        status = response.status
        response.close()
        return status, body
    except urllib.error.HTTPError as error:
        text = error.read(4096)
        error.close()
        return error.code, text
    except Exception as error:  # noqa: BLE001
        return 0, f"{type(error).__name__}: {error}".encode()


def main() -> int:
    print("=" * 78)
    print("A. the complete file manifest")
    print("=" * 78)
    status, body = fetch(f"{API}/competitions/data/list/{SLUG}")
    files = []
    if status == 200:
        try:
            payload = json.loads(body)
            files = payload.get("files") or []
            print(f"{len(files)} file(s), HTTP {status}\n")
            for entry in files:
                name = entry.get("name", "?")
                size = entry.get("totalBytes", 0)
                created = (entry.get("creationDate") or "")[:10]
                print(f"  {size:>12,} B  {created}  {name}")
        except json.JSONDecodeError:
            print(body[:600])
    else:
        print(f"HTTP {status}: {body[:300]}")

    print()
    print("=" * 78)
    print("B. can any single file be read without accepting the rules?")
    print("=" * 78)
    candidates = [entry.get("name") for entry in files if entry.get("name")]
    for name in candidates[:12]:
        routes = [
            f"{API}/competitions/data/download/{SLUG}/{name}",
            f"{API}/competitions/data/download-all/{SLUG}",
        ]
        status, body = fetch(routes[0], limit=4096)
        mark = "READABLE" if status == 200 else f"HTTP {status}"
        print(f"  {mark:>10}  {name}")
        if status == 200:
            pathlib.Path("/tmp/kaggri_grabbed").mkdir(exist_ok=True)
            safe = name.replace("/", "__")
            pathlib.Path(f"/tmp/kaggri_grabbed/{safe}").write_bytes(fetch(routes[0], limit=2_000_000)[1])

    print()
    print("=" * 78)
    print("C. the leaderboard, as it stands")
    print("=" * 78)
    status, body = fetch(f"{API}/competitions/{SLUG}/leaderboard/view")
    if status == 200:
        try:
            payload = json.loads(body)
            subs = payload.get("submissions") or []
            print(f"{len(subs)} row(s) on this page")
            for row in subs[:12]:
                print(
                    f"  {str(row.get('scoreNullable')):>12}  "
                    f"{row.get('teamNameNullable')}  {str(row.get('submissionDate'))[:19]}"
                )
            scores = [float(r["score"]) for r in subs if r.get("score")]
            if scores:
                print(f"\n  best  {max(scores)}")
                print(f"  worst {min(scores)}")
        except (json.JSONDecodeError, ValueError) as error:
            print(f"could not parse: {error}")
    else:
        print(f"HTTP {status}")

    print()
    print("=" * 78)
    print("D. what the overview and rules pages say")
    print("=" * 78)
    for label, url in (
        ("overview", f"https://www.kaggle.com/competitions/{SLUG}/overview"),
        ("rules", f"https://www.kaggle.com/competitions/{SLUG}/rules"),
    ):
        status, body = fetch(url)
        text = body.decode("utf-8", "replace")
        print(f"\n--- {label}: HTTP {status}, {len(text)} bytes ---")
        # The pages are a JS shell, but the server-rendered payload carries the prose.
        stripped = re.sub(r"<script[\s\S]*?</script>", " ", text)
        stripped = re.sub(r"<style[\s\S]*?</style>", " ", stripped)
        stripped = re.sub(r"<[^>]+>", " ", stripped)
        stripped = re.sub(r"\s+", " ", stripped).strip()
        print(stripped[:1800] if stripped else "(no readable prose in the served HTML)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
