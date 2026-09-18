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

report() {
  found=1
  echo "  $1"
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
hits=$(grep -rIn "$WHOAMI_PATTERN" "$ROOT" $SKIP 2>/dev/null | grep -v "$HERE/leak-audit.sh" | grep -vE '\.log:' | head -20)
if [ -n "$hits" ]; then
  echo "$hits" | while read -r line; do report "machine path: $line"; done
else
  echo "  none"
fi
echo

if [ "$found" = 0 ]; then
  echo "clean: nothing to remove, nothing to rotate."
  exit 0
fi

echo "NOT CLEAN: fix the entries above before pushing anywhere."
echo "A secret in history is not fixed by a later commit; the credential must be rotated."
exit 1
