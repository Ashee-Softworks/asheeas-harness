#!/bin/sh
# The harness, in one command.
#
#   1. recon   -- what each named competition is, and whether this account may download it
#   2. bench   -- every rendition of the algorithm: build, run, accuracy, speed
#   3. build   -- the native component, and its equivalence against the TypeScript path
#
# Nothing here accepts a rule, enters a competition, forms a team or submits anything.
# Reconnaissance is read-only; the pages that need a human click are printed with their URLs.
#
#   sh run.sh              # everything
#   sh run.sh --skip-slow  # the same, without Kotlin's six-second build
#   sh run.sh --json       # ...and print the whole report as JSON

set -e

here=$(cd "$(dirname "$0")" && pwd)
cd "$here"

echo "== reconnaissance (read-only) =="
python3 recon.py

echo
echo "== every rendition, measured =="
node bench.mjs "$@"

echo
echo "== the native component =="
./out/scoreboard --selftest
echo
./out/scoreboard --sum reports/versions.tsv --digest

echo
echo "reports written to $here/reports/"
