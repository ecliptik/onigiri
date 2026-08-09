# PLAN — Actual GitHub Releases, and a changelog worth reading (2026-08-09)

> **SHIPPED** 2026-08-09. Decisions taken (the user): publish only the
> versions that already have notes, generate `CHANGELOG.md`, drive it
> from a local script rather than CI.
>
> One delta from the plan as written. It said 15 tags carried real notes,
> counted as "annotated with a non-empty body". Measuring through
> `tag-notes.sh` instead — which is what actually gets published — the
> number is **25**: the count was off by one (16, not 15), and nine
> LIGHTWEIGHT tags turn out to carry real notes too, because for a
> lightweight tag `%(contents)` resolves to the version-bump COMMIT,
> whose body is often a genuine summary (v2.8.0–v2.11.1). Publishing
> those is the same principle, not a wider one: never fabricate notes,
> always publish notes that exist. The remaining 20 tags have nothing to
> say and get no Release.
>
> The criterion is therefore computed, not a hardcoded list: a tag gets a
> Release if `tag-notes.sh` prints anything.

## The observation

45 tags, zero GitHub Releases. `gh release list` is empty, and the only
way to see what changed between two versions is `git log` or reading tag
messages by hand. There is no CHANGELOG.md and no `.github/` at all.

This is not a gap in discipline — it is a gap in *publication*. The
release notes already exist and are good. They are sitting inside the
annotated tag objects where nothing reads them.

## What already exists — the whole plan turns on this

`git tag -l --format='%(contents:body)'` returns the tag message with the
PGP signature already stripped (verified on v2.19.4). So the notes are
extractable, mechanically, today. No new writing.

Coverage across the 45 tags is three-tiered:

| Tier | Tags | State |
|---|---|---|
| **A — full notes** | v2.4.0–v2.5.2, v2.16.0–v2.19.4 (15) | Real bodies, 441–1463 chars. Publishable verbatim. |
| **B — subject only** | v2.5.5–v2.7.1, v2.13.x, v2.15.0 (18) | Annotated, `body` empty. Title exists, notes don't. |
| **C — bare** | v2.2.0, v2.3.0, v2.8.0–v2.12.0 (12) | Lightweight tags. No message at all. |

Tier A is already better than most projects' release notes: they open on
the user-visible symptom ("The wrist read 316 kcal left while the phone
read 147"), then explain the cause. **That voice is the asset here.** The
plan must not replace it with generated bullet lists.

## The rule

**One source of truth: the annotated tag message.** Everything else —
the GitHub Release, the changelog file, the compare link — is generated
from it. Nothing is ever written twice, so nothing can drift.

This costs nothing to adopt because it describes what already happens.
The release ritual (bump `MARKETING_VERSION` → commit → `git tag -s` with
a written message → push both remotes) stays exactly as it is; it gains
one more step at the end.

## Architecture — `scripts/release.sh`

Local, not CI. It matches `deploy-phone.sh`, and it keeps the smartcard
and gpg on the machine that has them — a GitHub Action could create the
Release on tag push, but it would be the repo's first CI surface and it
cannot sign anything, so it buys one saved keystroke for a new dependency.
Recommend the script.

    scripts/release.sh 2.19.5

1. **Refuse to run on a dirty tree**, or if `MARKETING_VERSION` in
   `project.yml` does not equal the argument. The version bump is a
   separate commit by convention; this checks the two agree rather than
   editing anything.
2. **Refuse if the tag exists**, locally or on either remote.
3. Open `$EDITOR` on a template if no `-F` file is given, so the message
   is still written deliberately. A release with no notes should be
   awkward to produce.
4. `git tag -s`, then `git push origin main` and `git push origin <tag>`
   (one push reaches GitHub and Forgejo — origin carries both URLs).
5. `gh release create <tag> --verify-tag --title "<subject>"
   --notes-file -`, fed from `%(contents:body)` plus a generated
   `**Full changelog**: <compare link>` footer.
6. Regenerate `CHANGELOG.md` (below) and commit it.

`--verify-tag` matters: it aborts rather than silently creating a tag
GitHub invented itself, which would be unsigned.

## CHANGELOG.md — generated, never hand-edited

A hand-maintained changelog would be a second copy of the tag messages,
and the second copy is the one that goes stale. Generate it instead, with
a header saying so, from `git tag --sort=-creatordate` + `contents`.

It earns its place for three reasons the Releases page cannot cover:
the Forgejo mirror gets a changelog (Forgejo has its own releases API and
`git push` does **not** mirror release objects — GitHub Releases will be
GitHub-only); the history is readable offline and in the repo; and it
survives the repo outliving any one forge.

## What a Release is, and is not

**Notes-only. No artifacts, ever.** An iOS/watchOS app cannot be
distributed outside the App Store or TestFlight, so there is no `.ipa` to
attach and attaching one would be misleading. The Release page should say
this in one line, or the empty Assets section reads as a broken build.
If the paid developer account lands (App Store plan, phase 1), a
TestFlight link becomes the natural thing to put there.

**No contribution CTA.** The repo is PolyForm-Noncommercial and declines
external PRs by policy. Releases raise visibility — they appear in
watchers' feeds — so the notes should stay descriptive and not invite
patches. Nothing in the current tag messages does; keep it that way.

## Version scheme, as actually practised

Worth writing down since the script will enforce the shape:

- **major** — reserved; `2.x` since the license change.
- **minor** — a new capability (v2.17.0 log-without-saving, v2.18.0 AI
  fallback, v2.19.0 the weight basis).
- **patch** — a fix or refinement to what shipped (v2.19.1–.4).

## Backfill

Two treatments, and the split is honest about what the record supports:

- **Tier A (15 releases)** — publish the tag body verbatim. Mechanical,
  and the result is genuinely good reading.
- **Tiers B and C (30 releases)** — do **not** fabricate prose from
  commits and present it as notes written at the time. Publish the
  version as the title with a generated body: the commit subjects in the
  range plus the compare link. This repo's commit subjects are unusually
  descriptive, so that is a real changelog, just visibly a generated one.

Alternative worth considering: backfill Tier A only, and let the older
tags stay tags. Fewer, better pages; the compare links still work for
anyone who wants the detail. **Recommend this** — 30 generated pages
dilute the 15 good ones, and nobody is going back to read v2.5.7.

## Verification

- `scripts/release.sh` on a throwaway tag against a scratch repo, then
  `gh release view` to confirm the markdown renders (the tag bodies use
  4-space-indented log excerpts, which become code blocks — check that
  reads correctly).
- Confirm the signature survives: `git tag -v` after the script, and that
  GitHub shows the tag as verified.
- Confirm `CHANGELOG.md` regenerates byte-identically when re-run with no
  new tag, so it never produces a spurious diff.

## Decisions taken

1. **Backfill scope** — only versions that already have notes. 25 of 45,
   computed by `tag-notes.sh` rather than listed.
2. **CHANGELOG.md** — generated into the repo. It is the only changelog
   the Forgejo mirror gets (`git push` mirrors tags, never release
   objects), and it survives the repo outliving any one forge.
3. **Script, not Action** — `scripts/release.sh`, beside
   `deploy-phone.sh`.

## What shipped

Three scripts, each with one job:

- **`tag-notes.sh <tag>`** — prints a tag's notes, cleaned. The single
  extraction point, so the changelog and the Release can never render
  the same tag differently. Strips commit trailers (15 tags carry a
  `Co-Authored-By`, either pasted into the tag message before v2.16.0 or
  inherited from the bump commit by a lightweight tag) and relies on
  `%(contents:body)` already excluding the PGP signature.
- **`generate-changelog.sh`** — regenerates `CHANGELOG.md` from every
  tag, newest first, each with a compare link to its predecessor.
  Deterministic: verified byte-identical on re-run, which `release.sh`
  depends on to avoid spurious commits.
- **`release.sh <version>`** — refuses a dirty tree, a non-`main`
  branch, a `MARKETING_VERSION` that disagrees with the argument, a tag
  that already exists locally or on a remote, and a missing or
  unauthenticated `gh`. Then: `$EDITOR` on a template → `git tag -s
  --cleanup=strip` → push both remotes → `gh release create
  --verify-tag` with the notes plus a compare link and a one-line
  "notes only" footer → regenerate and commit the changelog.

`--verify-tag` is load-bearing: without it `gh` will happily create a tag
of its own, unsigned.
