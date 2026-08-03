#!/usr/bin/env bash
# Asserts on repo wiring rather than on code.
#
# Wiring is what rots: a pin reverted to `@v4` or a deleted Dependabot entry is a
# one-line change whose absence is completely silent — nothing fails, the supply
# chain just quietly goes back to being mutable. This makes that fail CI.
#
# Deliberately standalone and dependency-free: the composition test runs inside a
# privileged Pegasus/HTCondor container, which is the wrong place (and far too slow
# a feedback loop) for a check that only reads two files. This repo has no Python
# package and no pytest, so a shell script matching composition-test.sh's `fail()`
# idiom is the local convention. (#1)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS="$REPO/.github/workflows"
DEPENDABOT="$REPO/.github/dependabot.yml"

fail() { echo "CI HYGIENE FAILED: $*" >&2; exit 1; }

# --- 1. Every action ref must be a full 40-hex commit SHA with a `# vX.Y.Z` note.
#
# A tag is mutable: `@v4` means "whatever v4 points at when the job runs".
# actions/checkout@v6 really did move (df4cb1c 2026-06-02 -> d23441a 2026-07-16)
# with no signal to consumers, so this is not hypothetical. The version comment is
# required too — a bare SHA is unreadable, and the version is what makes a bump
# reviewable.
#
# Match on the whole line, not a `-o` extraction: the SHA and its `# vX.Y.Z`
# comment have to be checked together, and cutting the line at the SHA would
# discard the very comment being asserted.
refs=$(grep -rhE '^[[:space:]]*(- )?uses:' "$WORKFLOWS" \
  | sed -E 's/^[[:space:]]*(- )?uses:[[:space:]]*//' || true)

# Anti-vacuous: if the parser stops matching, this script would pass forever.
[ -n "$refs" ] || fail "no \`uses:\` refs found under $WORKFLOWS — this check is asserting nothing"

unpinned=""
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  case "$ref" in ./*) continue ;; esac  # local path, not a registry ref
  grep -qE '^[^@[:space:]]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v?[0-9]' <<<"$ref" \
    || unpinned+="    $ref"$'\n'
done <<<"$refs"

[ -z "$unpinned" ] || fail "actions not pinned to a commit SHA with a version comment:
$unpinned
A tag or branch is mutable, so the code CI runs can change with no commit here. Use:
    uses: owner/action@<40-hex-sha> # vX.Y.Z"

# --- 2. Something must bump those pins.
#
# A SHA never moves, including past a security fix, so pinning without Dependabot
# just trades a mutable-tag hole for a staleness one. The two are one control.
[ -f "$DEPENDABOT" ] || fail "no .github/dependabot.yml: the actions here are pinned to SHAs, so nothing ever bumps them"
grep -qE '^[[:space:]]*-[[:space:]]*package-ecosystem:[[:space:]]*"?github-actions"?' "$DEPENDABOT" \
  || fail "dependabot.yml has no \`github-actions\` entry, so the SHA-pinned actions are never bumped"

# --- 3. The group pattern must actually match every action in use.
#
# An ecosystem entry whose group patterns don't match an action leaves it outside
# the grouped PR, silently. `*` is the only pattern with no such failure mode;
# `actions/*` would exclude the first action from another owner.
grep -qE '^[[:space:]]+-[[:space:]]*"\*"[[:space:]]*$' "$DEPENDABOT" \
  || fail "the github-actions group pattern is not \"*\", so an action from outside actions/ would silently fall outside the group"

echo "CI hygiene OK: $(wc -l <<<"$refs" | tr -d ' ') action ref(s) pinned, Dependabot covers them"
