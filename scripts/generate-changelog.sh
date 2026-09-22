#!/usr/bin/env bash
#
# Regenerates CHANGELOG.md from the annotated tag messages.
#
# The tag message is the single source of truth for what a version
# changed — it is what `git tag -s` captured at release time, what the
# GitHub Release publishes, and what this file renders. Nothing is
# written twice, so nothing can drift.
#
# Deterministic: same tags in, byte-identical file out. Re-running with
# no new tag must produce no diff, and `release.sh` relies on that.
#
# Runs on macOS's bash 3.2 — no mapfile, no associative arrays.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT=CHANGELOG.md
REPO="https://github.com/ecliptik/onigiri"

# Newest first. `creatordate` is the tag date for annotated tags and the
# commit date for lightweight ones, which is the real release order in
# both cases — version sort would disagree wherever a patch shipped after
# a later minor.
TAGS=$(git tag --sort=-creatordate)

{
  echo "# Changelog"
  echo
  echo "Every released version of Onigiri, newest first."
  echo
  echo "Generated from the annotated git tags by \`scripts/generate-changelog.sh\`."
  echo "**Do not edit by hand** — the tag message is the source of truth, and it is"
  echo "also what each [GitHub Release]($REPO/releases) publishes. Versions before"
  echo "v2.16.0 were not all tagged with notes; those show the version and its"
  echo "comparison link alone."
  echo

  for tag in $TAGS; do
    subject=$(git tag -l --format='%(contents:subject)' "$tag")
    body=$(./scripts/tag-notes.sh "$tag")
    date=$(git tag -l --format='%(creatordate:short)' "$tag")

    # A tag whose message is just the version-bump commit subject (every
    # lightweight tag) carries no title of its own — use the version.
    case "$subject" in
      "$tag"*) heading="$subject" ;;
      *) heading="$tag" ;;
    esac

    echo "## $heading"
    echo

    # The predecessor is the next entry in this newest-first list. The
    # oldest tag matches itself, and then there is nothing to compare to.
    prev=$(printf '%s\n' "$TAGS" | grep -A1 -x -- "$tag" | tail -1)
    if [ "$prev" != "$tag" ]; then
      echo "_${date}_ · [changes since ${prev}]($REPO/compare/${prev}...${tag})"
    else
      echo "_${date}_"
    fi
    echo

    # tag-notes.sh has already dropped the PGP signature and any commit
    # trailers, so signed and unsigned tags render identically.
    if [ -n "$body" ]; then
      printf '%s\n' "$body"
      echo
    fi
  done
} > "$OUT"

echo "Wrote $OUT ($(grep -c '^## ' "$OUT") versions)"
