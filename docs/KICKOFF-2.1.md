# 2.1 kickoff prompt

Paste (or point a fresh session at) the block below to begin the 2.1
work. Everything it references is committed: `docs/PLAN-2.1.md`, the
updated `docs/ROADMAP.md`, and the session memory carries the lore.

---

Start Onigiri 2.1 (docs/PLAN-2.1.md — "Glance"): the Today-mirror
widget + logging polish. Work the milestones in order; the plan
settles the product decisions (widget in large+medium, day paging
snaps back at day roll, no Meal-or-Food chooser on the watch, the
Details › grammar reverses the old chevron removal deliberately).

M1 — TodayCardWidget (OnigiriWidgets), systemLarge, static render:
mirror the top of Today exactly — the kcal-left ring
(BalanceAccessoryView), Burned/Eaten flanks, the sodium/water metric
pills driven by the tracked slots, the rice-paper canvas. Day totals
through the kit's PlanCache day queries; locked-phone behavior must
match the existing widgets (DaySnapshot last-good fallback — verify
that parity, don't assume it). Screenshot-verify the render on the
simulator home screen before moving on.

M2 — Interactivity: ‹ › AppIntent day paging (browsed day in App
Group defaults, bounded by the 92-day totals window, snap back to
today at day roll), a water button that logs the default serving IN
PLACE by reusing the Control Center Log Water intent, and a + button
that widgetURL-deep-links into the Log sheet for the SHOWN day
(backfill included, like the existing quick actions). Then the
systemMedium variant (ring + pills; flanks only if they fit). Gallery
and QA screenshots.

M3 — Watch: rename home's "Log a meal" → "Log"; its sheet becomes the
phone's default Log view in miniature — Favorites first (meals +
foods mixed), then Recent, one unified list (MealPickerView reshape;
the sync payload already carries everything). Deploy to the watch and
verify on-wrist.

M4 — Housekeeping sweep: the "Details ›" grammar at all three sites
(month card unchanged; day card's "View & edit on Today" and Today's
headline join it — keep the day card's edit/cross-tab cue as an
accessibility hint); the shared barcode-routing helper replacing the
FoodsView/QuickLogSheet lookUpBarcode copies; QA-walkthrough tour
taps fixed for the Favorites-first defaults; and the OFF
search-a-licious nutrition-facts-completed filter ONLY after probing
the live service with the exact syntax — its failure mode is a clean
200-with-zero-hits that never trips the legacy fallback, so if OFF is
unstable that day, slip the item back to the backlog and say so.

M5 — Docs, README screenshots if surfaces changed, release as 2.1
(tag + push after my on-device verdict).

Constraints: iOS 18 floor is hard; no new Apple Intelligence
surfaces; no widget configuration UI. Follow the house verify rhythm:
kit tests per milestone, full build (watch included), the flow test
ALONE on freshly-erased paired sims (never batched with another
seeded test), screenshot-verify every UI claim via xcresult
attachments (ADD_WIDGET=1 exists for installing widgets on the sim
home screen). Commit per milestone — ask me to prime gpg when signing
fails. Deploy to the phone with the build-gated generic-destination +
retry-loop pattern; catch the watch with the generic watchOS build +
install patience loop. Stop and ask before any product-shape decision
the plan doesn't already settle.
