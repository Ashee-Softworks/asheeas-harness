#!/usr/bin/env bash
#
# The periodic audit. Everything here answers a question that code review cannot.
#
# Why this exists: the platform carried two access models for a hundred commits. Both were
# typed, linted, tested, and passed every check the project had. Nothing was wrong with the
# code -- what was wrong was that `decideAccess` was never called. No test asserts that a
# function is *reached*, only that it behaves when it is. That class of defect is invisible to
# a gate and obvious to an inventory.
#
# So these checks do not read the code. They count things, compare them to each other, and ask
# whether intent and implementation agree. Run it on a schedule -- and when it comes back
# quiet, run it anyway. The defects it finds are the ones that were quiet for a hundred commits.
#
#   ./system-audit.sh          # report, always exits 0
#   CI=1 ./system-audit.sh     # exits 1 on findings, for a scheduled job
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FINDINGS=0
finding() { FINDINGS=$((FINDINGS + 1)); printf '    ! %s\n' "$1"; }
ok() { printf '    . %s\n' "$1"; }
head2() { printf '\n== %s\n' "$1"; }

# 1 -------------------------------------------------------------------------------------------
head2 "1. Every directory at the root, and whether anything is looking after it"

for entry in */; do
  dir="${entry%/}"
  case "$dir" in .*|node_modules) continue ;; esac
  if [ -d "$dir/.git" ]; then
    ok "$dir (own repository)"
  elif git -C "$dir" rev-parse --show-toplevel >/dev/null 2>&1; then
    ok "$dir (inside $(git -C "$dir" rev-parse --show-toplevel))"
  else
    finding "$dir is NOT under version control -- no history, no backup, no review"
  fi
done

# 2 -------------------------------------------------------------------------------------------
head2 "2. Files a repository depends on, that live outside every repository"

# A path like ../scripts/port-sync.mjs inside a package.json script is a dependency on a
# directory that may not be cloned alongside the repo. That is how a build works on one machine
# and nowhere else.
while IFS= read -r pkg; do
  repo="$(dirname "$pkg")"
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    if [ ! -e "$repo/$ref" ]; then
      finding "$pkg references $ref, which does not resolve from $repo"
    fi
  done < <(grep -oE '\.\./[A-Za-z0-9_./-]+' "$pkg" 2>/dev/null | sort -u)
done < <(find . -maxdepth 3 -name package.json -not -path '*/node_modules/*')

# 3 -------------------------------------------------------------------------------------------
head2 "3. Broken duplicates and dead worktrees"

for d in */; do
  dir="${d%/}"
  if [ -f "$dir/.git" ]; then
    target="$(sed -n 's/^gitdir: //p' "$dir/.git")"
    if [ -n "$target" ] && [ ! -d "$target" ]; then
      finding "$dir points at a missing gitdir ($target) -- a duplicate that looks real"
    elif ! git -C "$dir" status >/dev/null 2>&1; then
      finding "$dir looks like a worktree but git cannot read it"
    fi
  fi
done

# 4 -------------------------------------------------------------------------------------------
head2 "4. Do the services agree on how a service is checked?"

declare -A seen_check=()
while IFS= read -r pkg; do
  name="$(dirname "$pkg")"
  scripts="$(grep -oE '"(test|typecheck|check-types|lint|gate)":' "$pkg" 2>/dev/null | tr -d '":' | tr '\n' ',')"
  [ -z "$scripts" ] && continue
  ok "$name: ${scripts%,}"
  for s in lint typecheck check-types test gate; do
    case ",$scripts," in *",$s,"*) seen_check["$s"]=1 ;; esac
  done
done < <(find . -maxdepth 3 -name package.json -not -path '*/node_modules/*')
for s in lint typecheck test; do
  [ -z "${seen_check[$s]:-}" ] && finding "no service has a '$s' script -- absent from the ecosystem, not just one repo"
done
if [ -n "${seen_check[check-types]:-}" ] && [ -n "${seen_check[typecheck]:-}" ]; then
  finding "two names for one check (typecheck and check-types); no single command checks everything"
fi

# 5 -------------------------------------------------------------------------------------------
head2 "5. Nothing schedules anything"

wf="$(find . -maxdepth 5 -path '*.github/workflows/*' -not -path '*/node_modules/*' 2>/dev/null | wc -l)"
if [ "$wf" -eq 0 ]; then
  finding "zero workflow files: every check in this project runs only when a person remembers"
else
  ok "$wf workflow file(s)"
fi

# 6 -------------------------------------------------------------------------------------------
head2 "6. Configuration the code requires, and whether it is written down"

declared="$(grep -rhoE 'process\.env\.[A-Z0-9_]+' --include='*.ts' --include='*.tsx' --include='*.mjs' --include='*.js' \
  --exclude-dir=node_modules --exclude-dir=.next --exclude-dir=.venv --exclude-dir=.git \
  --exclude-dir=dist --exclude-dir=build --exclude-dir=vendor \
  --exclude-dir=.vercel --exclude-dir=.turbo \
  . 2>/dev/null | sed 's/process\.env\.//' | sort -u)"
if [ -z "$declared" ]; then
  ok "no environment variables read from source"
else
  for var in $declared; do
    case "$var" in NODE_ENV|VERCEL|CI|PORT|HOME) continue ;; esac
    if ! grep -rqE "(^|[^A-Z_])$var" --include='.env.example' --include='*.md' . 2>/dev/null; then
      finding "$var is read from the environment and appears in no .env.example or document"
    fi
  done
fi

# 7 -------------------------------------------------------------------------------------------
head2 "7. Values that decide something public, and whether any test covers them"

cdt="asheeas/workspaces/asheesms/repo/apps/platform"
if [ -f "$cdt/test/countdown.test.ts" ]; then
  if grep -q 'delete process.env.LAUNCH_DATE' "$cdt/test/countdown.test.ts"; then
    finding "the countdown test DELETES LAUNCH_DATE, so nothing validates the configured launch date. A malformed one (2026-09-2O) parses to NaN, silently falls back to the default, and the public page counts to the wrong day with no test failing."
  fi
fi

# 8 -------------------------------------------------------------------------------------------
head2 "8. Archives sitting next to the source they were made from"

shopt -s nullglob
for zip in *.zip; do
  finding "$zip ($(du -h "$zip" | cut -f1)) sits beside the live directory: two candidate sources, no way to tell which is current, and it predates later changes"
done
shopt -u nullglob

# 9 -------------------------------------------------------------------------------------------
head2 "9. State left in the working tree"

count="$(find . -maxdepth 4 \( -name '__pycache__' -o -name '.pytest_cache' -o -name '.venv' -o -name '.next' \) -not -path '*/node_modules/*' 2>/dev/null | wc -l)"
ok "$count cache/venv directories present; checking each is ignored by the repo it sits in"
while IFS= read -r d; do
  repo="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$repo" ]; then
    # **The path has to be asked about in the repository's own terms.** `$d` is written relative to
    # this script's working directory, and `git -C "$repo"` resolves a relative path against a
    # *different* root — so the first version of this check asked about
    # `arc-agi-3-staging/arc-agi-3-staging/__pycache__`, matched nothing, and reported seven
    # directories as unignored that git's own answer says are ignored. A gate that names problems
    # that are not there is the same defect as one that stays silent about problems that are:
    # the person reading it cannot tell which findings to act on.
    #
    # Checked 2026-09-24 against `git check-ignore -v` for all seven paths: every one matched a
    # pattern in its own `.gitignore`.
    absolute="$(cd "$d" 2>/dev/null && pwd)"
    relative="${absolute#"$repo"/}"
    if ! git -C "$repo" check-ignore -q "$relative" 2>/dev/null; then
      finding "$d is NOT ignored by $repo"
    fi
  fi
done < <(find . -maxdepth 4 \( -name '.venv' -o -name '.next' -o -name '__pycache__' \) -not -path '*/node_modules/*' 2>/dev/null)

# 10 ------------------------------------------------------------------------------------------
head2 "10. A shell environment that outlived the task that needed it"

if [ -n "${VIRTUAL_ENV:-}" ]; then
  finding "VIRTUAL_ENV is set to $VIRTUAL_ENV in this shell. A python environment activated for one job stays active for every later command in the same shell, which is how unrelated work starts failing for reasons that look like something else."
fi

# ---------------------------------------------------------------------------------------------
printf '\n'
if [ "$FINDINGS" -eq 0 ]; then
  echo "system-audit: clear"
  exit 0
fi
echo "system-audit: $FINDINGS finding(s)"
if [ -n "${CI:-}" ]; then exit 1; fi
exit 0
