#!/usr/bin/env bash
# One-time, per clone: point git at the committed hooks (.githooks/).
# Git never runs hooks that arrive with a clone, so this must be run by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
echo "Hooks installed (core.hooksPath=.githooks)."
[ -f scripts/personal-terms.local ] || echo "Now create scripts/personal-terms.local from the .example."
