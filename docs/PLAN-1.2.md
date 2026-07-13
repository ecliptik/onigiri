# Onigiri 1.2.0 — polish four-pack + going public

Plan agreed 2026-07-10 (late). Scope from `docs/POST-1.0.md` leftovers plus
repo publication. Rhythm unchanged: implement → kit tests + affected UI
test on ERASED paired sims → commit → push → deploy phone AND watch →
tell the user what to verify.

Decisions locked with the user:

- License: **MIT**.
- Scrub level: **secrets/devices only** — team ID and device names/UDIDs
  move to gitignored local config. © Micheal Waltz, ecliptik URLs, doc
  prose, and the `com.ecliptik` bundle ID all stay (public identity;
  bundle rename would reset HealthKit grants and device data).
- Git authorship stays `Micheal Waltz <micheal@ecliptik.com>` (the
  public address — verified, all 120 commits).
- History WILL be rewritten (only clones: this laptop + Forgejo):
  reel.mp4/reel.gif purged everywhere (embarrassing), team ID + device
  IDs replaced throughout history. Note: rewriting drops the GPG
  signatures on old commits — new work continues signed.

## M1 — Duplicate-food guard

Scanning/picking a product whose *name* (case-insensitive) matches a
library food offers "edit existing instead" in the prefilled form,
instead of silently creating a twin. Touch points: the two `route(_:)`
paths (QuickLogSheet, FoodsView online section) and FoodFormView —
when a prefill's name matches, an alert offers "Edit “X”" (loads the
existing food into the form, prefill values available to apply) vs
"Create anyway". Kit-testable name matching; UI test with a seeded name
collision.

## M2 — Watch parity niceties

1. Food/water icon personalization syncs to the watch (ride the existing
   `SyncPayload`/`applicationContext` — add icon keys, watch reads
   `SharedStore` like the phone).
2. Water-goal progress on the watch home (current oz / goal under the
   headline; goal already syncs).
CAUTION (memory): watch UI has zero automated coverage and a bare VStack
under .navigationTitle renders blank on-device — keep ScrollView roots.
Verification is user-on-wrist.

## M3 — Progress gauges toggle

Settings → Appearance: "Progress gauges" toggle, default OFF. When on,
Today's metrics wear their progress visually, designed as a set (a lone
bar looked orphaned pre-1.0 and was removed):
- ring around the balance headline (progress toward daily budget),
- fill bars behind the water and sodium hydration-row numbers.
Phone only for 1.2. UI test toggles it on and screenshots.

## M4 — Error-style unification

Remaining inline red footnotes become toasts (transient failures should
all report the same way): TodayView `model.errorMessage`, QuickLogSheet
`errorMessage`, FoodFormView `lookupMessage` (orange), OnlineResults
`search.message` review — persistent states (e.g. "Health unavailable")
may stay inline; judge per case, note choices in the commit.

## M5 — Public release prep

1. `LICENSE` (MIT, © 2026 Micheal Waltz) + README license note.
2. Team ID out of `project.yml` → optional include `local.yml`
   (gitignored) carrying `DEVELOPMENT_TEAM`; README dev-setup documents
   creating it.
3. `scripts/deploy-phone.sh` device name/UDIDs → sourced from gitignored
   `scripts/local-devices.env`; script exits with a friendly message when
   missing. CLAUDE.md loses the literal device names.
4. `.gitignore` additions: `*.xcresult`, `local.yml`,
   `scripts/local-devices.env`.
5. Secret sweep (git grep for keys/tokens — none known; OFF needs no key).
6. History rewrite with `git filter-repo`: purge `docs/showcase/reel.*`
   from all history, replace team ID + device UDIDs/names in historical
   blobs; tags carried over; force-push main + tags to Forgejo; verify
   with a fresh clone + build.
7. Publication is a **GitHub mirror** (github.com/ecliptik/onigiri) fed
   from Forgejo — pushes keep going to Forgejo only. Settings footer and
   README point at the GitHub URL.

## Out of scope

Paid dev account / CloudKit / TestFlight (own design cycle), reminders
time customization, gauges on watch, duplicate-guard fuzzy matching
beyond case-insensitive equality.
