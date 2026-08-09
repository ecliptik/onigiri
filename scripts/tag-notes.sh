#!/usr/bin/env bash
#
# Prints a tag's release notes: the annotated message body, cleaned.
#
# The one place the notes are extracted, so the changelog file and the
# GitHub Release can never render the same tag differently.
#
#   ./scripts/tag-notes.sh v2.19.4
#
# Two things get stripped:
#
#   - Commit trailers (Co-Authored-By, Signed-off-by, the Generated-with
#     line). Fifteen tags carry them — the annotated ones up to v2.5.2
#     because the trailer was pasted into the tag message, and every
#     LIGHTWEIGHT tag because `contents` then refers to the commit
#     object, whose body is often nothing but the trailer. The practice
#     stopped at v2.16.0; this is a historical cleanup, not a policy.
#   - The PGP signature, which `%(contents:body)` already excludes on
#     signed tags (verified 2026-08-09).
#
# Prints nothing (exit 0) for a tag with no notes of its own — callers
# decide what an empty body means.

set -euo pipefail

tag=${1:?usage: tag-notes.sh <tag>}

# `$( )` strips the trailing newlines that deleting trailers leaves
# behind, so a body of nothing but trailers comes back empty.
body=$(
  git tag -l --format='%(contents:body)' "$tag" \
    | sed -E '/^(Co-[Aa]uthored-[Bb]y|Signed-off-[Bb]y):/d; /^🤖 Generated with/d'
)

[ -n "$body" ] && printf '%s\n' "$body"
exit 0
