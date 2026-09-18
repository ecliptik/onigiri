# Refreshing the site and README media for iOS 27 (2026-09-18)

> Status: **DONE 2026-09-18.** All 23 files replaced and through the
> gates; the four traps the run turned up are folded into
> `PLAN-site-and-media.md` (VFR duration inflation, the query-clear
> flash, the erase resetting Full Screen Apps, and a repeat seed
> tripping the aggressive-pace warning). Shipped: 7 phone stills, 2
> iPad, 2 widget, 6 clips + 6 posters. The watch shot is untouched, as
> scoped.
>
> Status when written: SCOPED 2026-09-18, decisions taken. The mechanics live in
> `plans/PLAN-site-and-media.md` — this file is the campaign: what is
> stale, why, in what order, and what could stop it.
>
> **In scope:** the 6 clips + posters, the 7 phone stills, the 2 iPad
> stills, the 2 widget stills. **Out:** the watch shot — it is correct
> as-is, its content was already ruled on (balance mode, 2026-08-02),
> and re-shooting it would mean re-pairing a watchOS 27 sim first.
>
> The fallback agreed for a model that cannot answer — **keep the
> 2026-08-03 take** rather than re-shoot through a BYO provider or cut
> the clip — turned out not to be needed: the 27.0 runtime answers (see
> blocker 1). It stands as the rule if the host's model ever stops.

## Why now

Two things moved under the assets at once.

1. **iOS 27 redraws the tab bar.** The "+" is a search-role tab drawn
   IN the row; iOS 26 hangs it off the side as a detached circle
   (CLAUDE.md, accepted 2026-09-15). Every phone still and every clip
   we ship was taken on 26.5, so all of them show a bar the app no
   longer draws on a current phone.
2. **The Log sheet was rebuilt** between 2026-09-15 and 09-18 — one
   field, a pinned composer with an action row, the chooser behind
   "+". Two of the three clips are shot inside that sheet.

## Inventory

Sizes and dates are from the committed files; "stale" says what a
viewer would notice.

| Asset | Taken | State |
|---|---|---|
| `showcase/{light,dark}/today,goal,calendar` + `light/foods` | 2026-09-17 | **Content current.** Only the iOS 26 tab bar dates them. |
| `showcase/{light,dark}/ipad-landscape` | 2026-08-03 | Stale: pre-`inlineLarge` Today header, iOS 26 chrome. |
| `showcase/widget/home-screen{,-dark}` | 2026-08-02 | Stale: iOS 26 Home Screen and tab bar behind the widget. |
| `showcase/watch/home` | 2026-07-19 | Probably fine — watchOS chrome barely moved, and the balance reading is deliberate (see below). |
| `media/add-food{,-dark}.mp4` + posters | 2026-08-03 | **Badly stale.** Shows the old Log sheet: an in-list "Scan Barcode, Label, or Food" row and a bottom search pill reading "Foods, Meals, and More". Neither exists. |
| `media/ai-estimate{,-dark}.mp4` + posters | 2026-08-03 | **Badly stale**, same sheet, plus the old AI row wording. |
| `media/day-swipe{,-dark}.mp4` + posters | 2026-08-03 | **Badly stale.** Today's header is the old in-content large title, the day reads "Yesterday" (a string the app stopped using because it truncated), and the meter says "Intake" where it now says "Eaten". |
| `media/social-card.png` | — | No app UI. Leave it. |

That is **7 phone stills, 2 iPad, 2 widget, 6 clips + 6 posters** ≈ 23
files. `dark/foods.png` does not exist and is not needed — the site
never asks for it and the README embeds only the light set.

## What is already in place

More than the older notes suggest, and it changes the shape of the job:
this is mostly a RUN, not an authoring exercise.

- **`testHeaderShots`** (`TEST_RUNNER_HEADER_SHOTS=1`) still produces the
  four tab stills, and asserts the four titles share a top-left corner.
- **`testSiteClip`** (`TEST_RUNNER_SITE_CLIP=day-swipe|add-food|ai-estimate`)
  already drives all three clips from XCUITest and prints `CLIPMARK`
  beats, and its choreography is CURRENT: the AI leg types into
  `entryDoorsDescribeField` and taps `label BEGINSWITH 'Estimate with'`.
  Worth noting that query only works again because the composer's label
  went back to "Estimate with AI" on 2026-09-18 — under the short-lived
  "AI Estimate" it would have failed.
- **`grantHealthAccess` handles iOS 27's two-page grant** as of
  2026-09-18. Without that fix none of these captures can run on 27 at
  all: the scope page ("How much data would you like to share…") stands
  over the app and every tap fails. This campaign is only possible
  today.
- **`testAddWidgetToHomeScreen`** (`TEST_RUNNER_ADD_WIDGET=1`) places the
  widget for the Home Screen shot.

## Devices to use

The committed stills are **1206×2622 = iPhone 17 Pro**, and a different
phone silently resizes every asset (`PLAN-site-and-media.md`, 2026-07-24).
Matching sims on 27.0:

- Phone: **iPhone 17 Pro `89A22F2C-8CE8-4B4A-8A45-B140ECC452F6`**.
  Address it by **udid, never by name** — the roster holds a second
  `iPhone 17 Pro` on 26.5 and `-destination name=…` silently picks one.
- iPad: **iPad Pro 13-inch (M5) `8F9484D9-B1EF-4412-81EC-6F3BAF214C63`**
  (committed iPad asset is 2752×2064).

## Blockers and unknowns

1. ~~**The AI clip may not be capturable on this Mac at all.**~~
   **SETTLED 2026-09-18, and the answer is good: the model ANSWERS on
   the 27.0 sim** — 7.2 s from `CLIPMARK estimating` to
   `CLIPMARK answered`, warm. The `ModelManagerError 1001` /
   `promptTemplateNotFound` that killed the previous attempt was the
   **26.5** runtime against this host; 27.0 does not reproduce it. So
   all three clips re-shoot normally and the "keep the old take"
   fallback is not needed. Re-probe if the host's Apple Intelligence
   state changes — this is a property of the runtime, not of the repo.
   - The probe also caught a STALE LINE in the driver, which is the
     kind of thing only a real run finds: `testSiteClip` ended on
     `app.navigationBars["New Food"]`, and a new food's nav title is
     the EMPTY STRING — it crowded the confirm pair and was dropped,
     leaving "New Food" as an invisible header `Text` for VoiceOver.
     `testFormLogPair` asserts that nav bar is ABSENT, so the clip drove
     the whole way correctly and then failed on its last assertion,
     cutting the tail beat. Fixed to `app.staticTexts["New Food"]`.
2. **No watchOS 27 watch is paired to that phone sim.** The 46 mm
   Series 12 is paired to an iPhone 18 Pro Max. The watch shot needs the
   phone's shared HealthKit grant, so re-shooting it means re-pairing
   first. Cheapest answer is to leave the watch shot alone — it is
   correct as-is and the user already ruled on its content (leave it in
   BALANCE mode, 2026-08-02).
3. **The calendar must be captured mid-month** or the grid shows almost
   no badges (2026-08-02). Today is the 18th and the seeder writes ~3
   days of history, so the 15th–17th land mid-grid — **fine today**,
   and a reason not to let this sit until early October.
4. **Order is load-bearing.** The widget test REINSTALLS the app and
   resets the shared HealthKit grant, so it must run LAST. Each clip
   take LOGS or types something and the seed resets Health per launch,
   so it is one take per launch, and a retry costs the whole cycle.

## Order of work

0. **Probe the model** on the 27.0 sim (blocker 1). Decide the AI clip's
   fate before spending anything else.
1. Erase the phone sim (shut down first — `simctl erase` fails on a
   booted device and a swallowed failure leaves stale state).
2. `appearance light`, `status_bar override` to 9:41 / charged / full
   bars.
3. Install first so the app-group container exists, write the AI/online
   defaults into the container plist via `simctl spawn`, then run
   `testHeaderShots`; export the four attachments.
4. `appearance dark`, repeat for the three dark stills.
5. Clips: for each of the three × two appearances, fresh seed →
   background `simctl io recordVideo` → `testSiteClip` → cut from
   FRAMES against the `CLIPMARK` epochs, never from the script's clock.
   Encode `scale=606:1318,fps=30`, libx264, yuv420p, `+faststart`,
   `-an`; poster = frame 1 at 606×1318.
6. iPad, both appearances (three iPadOS gotchas in
   `PLAN-site-and-media.md`: portrait buffer needs `sips -r 270`,
   full-screen-apps mode, terminate to clear the Settings breadcrumb).
7. Widget shot **last**, both appearances.
8. Watch: skip unless decided otherwise.

## Verification gates

Non-negotiable, because both faults render wrong ONLY in a browser
while sips/Finder/QuickTime show them fine:

- Every mp4: `ffprobe -show_entries format=start_time` must read 0, and
  `ffprobe -v trace | grep "media time: -1"` must be empty. The cure is
  a concat-demuxer remux, not a different `-ss` position.
- Every rotated PNG: `Image.open(p).getexif().get(274)` must be None
  (`sips -r` writes an orientation tag that browsers honour).
- Every still: size equals the committed file's size before it is
  copied in.
- After pushing: load the live Pages URL and look, since `docs/`
  publishes on push.

## Out of scope

- The **wiki** user guide — separate repo, and the user asked about the
  README and the site. Worth a look afterwards for embedded images.
- **Feature copy.** README and `docs/index.html` describe features, not
  the Log sheet's controls; nothing in either went stale with this
  redesign. Checked 2026-09-18.
- The **social card** — no app UI on it.
