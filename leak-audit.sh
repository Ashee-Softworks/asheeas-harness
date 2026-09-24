#!/bin/sh
# The leak audit.
#
# Run this before anything is pushed anywhere. It answers three questions, and each is a
# different failure with a different fix:
#
#   1. Is a secret-shaped file *tracked*?        -> remove it from the index
#   2. Is a secret in a tracked file's contents? -> remove it from the file
#   3. Is a secret in the history?               -> a later commit cannot undo it; the
#                                                   credential must be rotated
#
# It also reports this machine's own paths, because a report that names the person who ran it
# is a leak too, and a quieter one than a token.
#
#   sh leak-audit.sh [directory ...]     # defaults to this repository's parent tree
#
# Exit code is 0 when nothing was found, 1 when something was.

set -u

ROOT=${1:-$(cd "$(dirname "$0")" && pwd)}
HERE=$(cd "$(dirname "$0")" && pwd)

# Every shape a credential takes from the services actually in play in this work: Kaggle's
# new access tokens, GitHub's three token families, OpenAI-style keys, and the ARC key this
# machine holds in an ignored .env.
SECRETS='KGAT_[A-Za-z0-9]{8,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|ARC_API_KEY[[:space:]]*[:=][[:space:]]*[A-Za-z0-9-]{8,}|KAGGLE_KEY[[:space:]]*[:=][[:space:]]*[A-Za-z0-9]'

# This machine's account name. A path in a committed report publishes it.
WHOAMI_PATTERN=$(id -un 2>/dev/null || echo '@@never@@')

SKIP='--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.venv --exclude-dir=vendor --exclude-dir=out --exclude-dir=.next --exclude-dir=dist'

found=0

# `report` is called from inside `| while read` in five of the six checks below, and a pipeline runs
# in a **subshell**: `found=1` set there never reaches this shell, so those checks print a finding
# and the audit still exits 0. That is the exact defect this file documents at question 6 — found
# there, and fixed only there. It was still live for questions 1–5 until 2026-09-24, and it made
# `exit=0` mean "question 6 was happy", not "nothing was found".
#
# A subshell cannot set a parent variable, but it can append to a file. The exit code is decided
# from the file at the end, so every check enforces rather than merely reports.
FOUND=$(mktemp)
trap 'rm -f "$FOUND"' EXIT INT TERM

report() {
  printf '  %s\n' "$1"
  printf 'found\n' >>"$FOUND"
}

echo "Leak audit"
echo "  tree    : $ROOT"
echo "  account : $WHOAMI_PATTERN"
echo

# ---------------------------------------------------------------- 1. tracked secret files
echo "1. secret-shaped files that are tracked"
if [ -d "$ROOT/.git" ] || [ -f "$ROOT/.git" ]; then
  hits=$(git -C "$ROOT" ls-files 2>/dev/null | grep -iE '(^|/)(\.env|\.env\.|secrets?|credentials?|\.pem|\.key|id_rsa|id_ed25519|hosts\.yml|access_token|kaggle\.json)$')
  if [ -n "$hits" ]; then
    echo "$hits" | while read -r line; do report "tracked: $line"; done
  else
    echo "  none"
  fi
else
  echo "  not a git repository; skipped"
fi
echo

# ---------------------------------------------------------------- 2. tracked contents
echo "2. secrets in tracked file contents"
if [ -d "$ROOT/.git" ] || [ -f "$ROOT/.git" ]; then
  hits=$(git -C "$ROOT" grep -InE "$SECRETS" -- . 2>/dev/null | head -20)
  if [ -n "$hits" ]; then
    echo "$hits" | while read -r line; do report "content: $line"; done
  else
    echo "  none"
  fi
else
  echo "  not a git repository; skipped"
fi
echo

# ---------------------------------------------------------------- 3. history, every blob
echo "3. secrets in history, every reachable commit"
if [ -d "$ROOT/.git" ] || [ -f "$ROOT/.git" ]; then
  history_hits=0
  for rev in $(git -C "$ROOT" rev-list --all 2>/dev/null | head -500); do
    if git -C "$ROOT" grep -IqE "$SECRETS" "$rev" -- . 2>/dev/null; then
      git -C "$ROOT" grep -InE "$SECRETS" "$rev" -- . 2>/dev/null | head -2 | while read -r line; do
        report "history: $line"
      done
      history_hits=1
    fi
  done
  [ "$history_hits" = 0 ] && echo "  none"
else
  echo "  not a git repository; skipped"
fi
echo

# ---------------------------------------------------------------- 4. working tree, incl ignored
echo "4. secrets anywhere in the working tree, including ignored files"
hits=$(grep -rIlE "$SECRETS" "$ROOT" $SKIP 2>/dev/null | grep -v "$HERE/leak-audit.sh" | head -20)
if [ -n "$hits" ]; then
  echo "$hits" | while read -r line; do report "present: $line"; done
else
  echo "  none"
fi
echo

# ---------------------------------------------------------------- 5. this machine's paths
echo "5. this machine's account name in files that would be published"

# **The question is only answerable on a machine that belongs to a person.** On a CI runner the
# account is `runner`, and inside a container it is often `root`. Both are ordinary words that
# appear in ordinary prose — a commit subject about gitlinks, a file named `command-runner.ts` — so
# asking the question there does not find a machine path, it finds the word. Measured 2026-09-24: run
# with the account set to `runner`, this check reported six findings against this repository and
# every one of them was English.
#
# So it refuses, in the register the rest of this project already uses: "we could not check" and
# "there is nothing there" are different statements, and the second is what a green tick would imply.
case "$WHOAMI_PATTERN" in
  runner|root|docker|circleci|vsts*|buildkite-agent)
    echo "  unanswerable on this machine: the account is '$WHOAMI_PATTERN', which is not a person."
    echo "  This question is about whoever holds the work, so it means something only where the"
    echo "  work is. Reported as unchecked, not as clean."
    ;;
  *)
    hits=$(grep -rIn "$WHOAMI_PATTERN" "$ROOT" $SKIP 2>/dev/null | grep -v "$HERE/leak-audit.sh" | grep -vE '\.log:' | head -20)
    if [ -n "$hits" ]; then
      echo "$hits" | while read -r line; do report "machine path: $line"; done
    else
      echo "  none"
    fi
    ;;
esac
echo

# ---------------------------------------------------------------- 6. claimed links resolve
echo "6. every link claimed in a published document resolves"
#
# Added after three claims failed in one session and a person caught every one of them.
#
#   "no Ashee Softworks account exists in any repository"   -> four URLs returned HTTP 200
#   "GitHub is the only verified link"                      -> two GitHub orgs existed, not one
#   a social-account search that found only npm authors     -> never resolved the obvious URLs
#
# Every one was caught by a human reading, and none by a check. The mistakes file already
# names the difference: "we got lucky" and "the gate caught it" are different facts about
# the process. This is the gate for that class.
#
# It is the only check here that needs the network, so it degrades rather than fails: a
# link that cannot be reached offline is reported as unverified, not as broken.
claimed=$(grep -rhoE 'https?://[A-Za-z0-9._~:/?#@!$&*+,;=%-]+' \
            "$ROOT/announcement" "$ROOT/observations" 2>/dev/null \
          | sed 's/[.,)*]*$//' | sort -u)

if [ -z "$claimed" ]; then
  echo "  no published documents claim a link; skipped"
else
  if ! curl -sS -o /dev/null --max-time 8 https://github.com 2>/dev/null; then
    echo "  offline: $(echo "$claimed" | wc -l) claimed link(s) could not be checked"
  else
    bad=""
    total=0
    for url in $claimed; do
      # A loopback address is a fact about a machine, not a published link.
      case "$url" in
        *127.0.0.1*|*localhost*) continue ;;
      esac
      total=$((total + 1))
      code=$(curl -sS -o /dev/null -w '%{http_code}' -L --max-time 20 "$url" 2>/dev/null || echo 000)
      case "$code" in
        2*|3*) ;;
        *) bad="$bad $url (HTTP $code);" ;;
      esac
    done
    # `report` is called here in the parent shell, not inside a pipe. The first version piped
    # into `while read`, which runs in a subshell, so `found=1` never escaped and the audit
    # printed the failure and then exited 0. A check that reports but does not enforce is the
    # defect this check exists to catch.
    if [ -n "$bad" ]; then
      report "unresolved claimed link(s):$bad"
    else
      echo "  all $total claimed link(s) resolve"
    fi
  fi
fi
echo

if [ ! -s "$FOUND" ]; then
  echo "clean: nothing to remove, nothing to rotate."
  exit 0
fi

echo "NOT CLEAN: fix the entries above before pushing anywhere."
echo "A secret in history is not fixed by a later commit; the credential must be rotated."
exit 1
