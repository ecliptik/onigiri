# 1.8 — Lowering the OS support floor

## Why

Onigiri targets iOS/iPadOS/watchOS 26.0 today — the OS that shipped
with it. That excludes real, working hardware in this household:
an iPhone XS on iOS 18.7 shows up in Xcode as *ineligible: "iOS 18.7.9
doesn't match Onigiri.app's iOS 26.0 deployment target."* The app's
actual API needs are far below 26; the floor is an accident of when
the project started, not a requirement.

## Device math (verified 2026-07-13)

| Floor | iPhones gained | iPads gained | Watches gained |
|---|---|---|---|
| 26.0 (today) | — (11/A13 and later) | — (8th gen+) | — (S6/SE2+) |
| **18.0 / watchOS 10** | **XS, XS Max, XR** (A12) | **7th gen** (A10) | **S4, S5, SE 1st gen** |
| 17.0 | none beyond 18's list | none | n/a |

- iOS 18 and iOS 17 support the *same* iPhones — going below 18 gains
  zero devices while costing real APIs (ControlWidget, Tab(value:role:),
  onScrollGeometryChange). Not worth it.
- **iOS 17 is the hard technical floor regardless**: SwiftData and
  @Observable carry the library and every model object.
- watchOS 26 requires the paired iPhone on iOS 26 — so a watchOS-26-only
  watch app *also* silently demands the newest phone OS. Lowering the
  watch floor matters even for watches that could run 26.

## What actually requires iOS 26 (grep-verified)

Three things. Everything else in the app is iOS 17/18-era.

1. `.glassEffect(.regular, in: .capsule)` — the toast capsule
   (Feedback.swift). Fallback: `.background(.ultraThinMaterial, in:
   .capsule)` behind an `if #available(iOS 26, *)` shim.
2. `.tabBarMinimizeBehavior(...)` — ContentView. Guard it; on 18 the
   tab bar simply never minimizes (arguably simpler).
3. The **rendering** of `Tab(role: .search)` as the detached corner
   circle — the API itself is iOS 18. On 18 the Add tab draws inside
   the bar at the trailing edge; the selection-bounce routing is
   version-independent. Two follow-ons to re-verify on an 18 device:
   - `AddPillLongPress`: the corner-region fallback still covers the
     trailing tab slot, and the label-walk likely *works* on 18's
     UIKit tab bar (it fails on 26's element-based chrome).
   - Screenshots/docs keep describing "the corner +"; on 18 it's the
     trailing tab. Cosmetic.

Already-18-compatible pieces that are sometimes mistaken for 26-isms:
`onScrollGeometryChange` (18), ControlWidget/Control Center button
(18), interactive widget intents (17), `listSectionSpacing` (17),
`containerBackground` (17/watchOS 10), accessory widget families incl.
`.accessoryCorner` (watchOS 10), `.searchable(isPresented:)` (17).
The watch app and its complications contain no 26-only API at all.

## Recommendation

**iOS 18.0, iPadOS 18.0, watchOS 10.0.**

- Gains every A12 iPhone, the A10 iPad, and three watch generations,
  for the cost of two availability shims and a QA pass.
- Sub-18 buys nothing (see table) and starts breaking features.
- New code accepts an ongoing tax: every 26-era API from here on needs
  an `#available` guard or a fallback. Keep the floor honest by
  building/QA-ing against an 18 simulator runtime in release passes.

## Implementation steps

1. `project.yml`: `iOS: "18.0"`, `watchOS: "10.0"`; xcodegen.
2. The two shims (toast glass, tab-bar minimize).
3. Download an iOS 18.x and a watchOS 10.x simulator runtime; build
   and run the QA walkthrough on both; specifically exercise the Add
   tab (bounce + hold-to-log-water) on iOS 18.
4. On-device proof: install on the iPhone XS (the whole point).
5. README note: Liquid Glass chrome appears on iOS 26+; older OSes get
   the standard look.

## Non-goals

- iOS 17/16, watchOS 9 — no device gain (17) or real API loss (16: no
  SwiftData).
- Visual parity across OS generations: 18 renders standard chrome, 26
  renders Liquid Glass. Both are "the system look" on their OS; we
  don't fake glass on 18.
