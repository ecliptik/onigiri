#!/usr/bin/env bash
#
# Refuses to let personal information leave this machine. This repo is
# PUBLIC, and on 2026-09-22 its whole history had to be reset because
# the author's own health figures — weight, height, age, per-day burn —
# had been pasted from device diagnostics into a plan and commit
# messages. CLAUDE.md states the rule; this enforces it.
#
# Usage:
#   scripts/check-personal-data.sh <rev-range>   # what a push would send
#   scripts/check-personal-data.sh --all         # the whole current tree
#
# Run by .githooks/pre-push (install once: scripts/install-hooks.sh).
# Checks ADDED lines and commit messages only, so synthetic values
# already in the tests don't re-trip it.
#
# Two sources of patterns:
#   - scripts/personal-terms.local (GITIGNORED): literal names, emails,
#     device names and IDs, one per line, case-insensitive. Kept out of
#     git because a committed list of them would publish them.
#     Copy scripts/personal-terms.local.example to start.
#   - the generic patterns below: Apple device UDIDs, the field=value
#     lines of the budget diagnostics, realistic body weights/heights.
#
# Copyright lines (©, "Copyright (c)") are exempt: they name the author
# on purpose. A match that is deliberately synthetic can be let through
# with PERSONAL_DATA_OK=1 — after checking that it really is.

set -uo pipefail
cd "$(dirname "$0")/.."

if [ "${PERSONAL_DATA_OK:-}" = "1" ]; then
  echo "check-personal-data: skipped (PERSONAL_DATA_OK=1)" >&2
  exit 0
fi

generic=(
  # Apple hardware UDIDs (iPhone/Watch): 0000XXXX-XXXXXXXXXXXXXXXX
  '\b0000[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12,16}\b'
  # Budget / plan diagnostics lines copied off a device
  '\b(height|age|weight(Health|Local|Synced|Fallback)?|restingEstimate|restingMeasured|rawBurn|floored|corrected|intake|deficit)=[0-9]'
  # Realistic adult body weights and heights
  '\b(9[0-9]|1[0-9][0-9]|2[0-9][0-9]|3[0-4][0-9])(\.[0-9])? ?(lb|lbs|pounds)\b'
  '\b(1[4-9][0-9]|2[01][0-9]) ?cm\b'
)

terms_file=scripts/personal-terms.local
terms=()
if [ -f "$terms_file" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$line" ] && terms+=("$line")
  done < "$terms_file"
else
  echo "check-personal-data: WARNING — $terms_file missing; names, emails and" >&2
  echo "  device names are NOT being checked. Copy the .example to create it." >&2
fi

if [ "${1:-}" = "--all" ]; then
  content="$(git grep -I -n -e '' -- . ':!scripts/personal-terms.local.example')"
else
  range="${1:?usage: $0 <rev-range> | --all}"
  # Added lines (with their file for the report) plus every commit message.
  content="$(git log --format='commit-message:%n%B' "$range" 2>/dev/null)
$(git diff --unified=0 --no-color "$range" -- . ':!scripts/personal-terms.local.example' 2>/dev/null \
    | awk '/^\+\+\+ /{file=substr($0,7); next} /^\+/{print file ": " substr($0,2)}')"
fi

# Lines that name the author deliberately.
content="$(printf '%s\n' "$content" | grep -v -E '©|Copyright \(c\)')"

found=0
report() {
  local label="$1" hits="$2"
  [ -z "$hits" ] && return
  found=1
  echo "✗ personal data ($label):" >&2
  printf '%s\n' "$hits" | head -20 | sed 's/^/    /' >&2
}
for pattern in "${generic[@]}"; do
  report "pattern $pattern" "$(printf '%s\n' "$content" | grep -E -i -- "$pattern")"
done
for term in "${terms[@]+"${terms[@]}"}"; do
  report "local term" "$(printf '%s\n' "$content" | grep -F -i -- "$term")"
done

if [ "$found" = 1 ]; then
  echo >&2
  echo "Refusing: this repo is public (CLAUDE.md, 'Never commit personal" >&2
  echo "information'). Replace real figures with their SHAPE or synthetic" >&2
  echo "values. If a match is genuinely synthetic, re-run with" >&2
  echo "PERSONAL_DATA_OK=1." >&2
  exit 1
fi
exit 0
