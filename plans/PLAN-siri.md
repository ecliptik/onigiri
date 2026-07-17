# Siri — hands-free logging and ask-back (2.5)

Decided 2026-07-16: all four capabilities — ask-back queries, water
quantity, AI describe-to-log (always confirm), watch Siri. Builds on
the shipped foundation (c678c3a): LogWater/LogMeal/LogFood intents with
parameterized phrases, EntityStringQuery resolution, vocabulary refresh
on every mirror rewrite.

## Shipped foundation (works today)

- "Log water in Onigiri", "Log a glass of water in Onigiri"
- "Log <saved meal> in Onigiri" — meal names from the library mirror
- "Log <favorite/recent food> in Onigiri" — disjoint from meal names
- Generic fallbacks ("Log a meal in Onigiri" → Siri asks which)
- Same intents power Spotlight, Action button, Shortcuts app, Control
  Center (water). Vocabulary refreshes via PhoneSyncService.

## 1. Ask-back queries — the highest-value add

One intent, one metric parameter (AppEnum: caloriesLeft / water /
sodium), so Siri disambiguates naturally and Shortcuts shows one tile:

- "How many calories do I have left in Onigiri?"
- "How much water have I had in Onigiri?"
- "How much sodium today in Onigiri?"

Parameterized phrases over the AppEnum give each metric its own spoken
form; each returns `.result(dialog:)` + a small snippet view (the
accessory-widget rendering already knows how to draw these numbers).
Data comes LIVE from HealthKitService + DailyPlanLoader — the same path
Today uses, not the possibly-stale widget mirror. Intent runs in the
app process (background mode), so HealthKit access is already there.

## 2. Water quantity

Optional `ounces: Double?` on LogWaterIntent — nil keeps today's
one-phrase default-serving behavior, Shortcuts exposes the field for
automation ("bedtime → log 20 oz"). HONEST LIMIT: numeric parameters
can't ride in App Shortcut phrases (only AppEntity/AppEnum can), so
"log 20 ounces of water in Onigiri" is not a guaranteed one-shot
phrase; the reliable forms are the default phrase, a Shortcuts
automation, or Siri asking. If one-shot spoken sizes matter, add a
small ServingSize AppEnum (glass / bottle / big bottle) mapped to oz —
enum cases CAN be phrase parameters.

## 3. Describe-to-log (AI, always confirm)

App-target intent (FoodIntelligence never enters the kit):
"Log half a cup of rice and a fried egg in Onigiri" →
`describeFood(text)` → Siri reads back "About 230 kcal, 200 mg sodium
for Rice and Egg — log it?" (`requestConfirmation`) → HealthKit write
with time-of-day slot inference → spoken result.

- Gated on `FoodIntelligence.isAvailable`; unavailable → clean spoken
  error, and the AppShortcut hides behind the same gate.
- Greedy decoding (already the shipped path) keeps repeat phrases
  giving repeat numbers.
- ALWAYS confirm before writing — an estimate landing in Health
  unreviewed is the flow's only real risk (user decision 2026-07-16).
- The freeform text parameter can't be in the phrase either; the phrase
  is "Describe a food in \(applicationName)" (Siri then asks "what did
  you eat?") — one extra exchange, still fully hands-free.

## 4. Watch Siri

Raise-to-speak "log water in Onigiri" phone-free. The intents live in
the kit and watchOS has HealthKit+WidgetKit, so this is registration
work: a watch-target AppIntentsPackage (including OnigiriKitIntents) +
an AppShortcutsProvider with the water/meal/food shortcuts (no
describe-to-log — no Foundation Models on watchOS). The watch's mirror
is populated by WatchSync already; add the same
updateAppShortcutParameters() call where the watch stores a payload.

## Order of work

1. [ ] Ask-back query intent + snippet + phrases (biggest daily value).
2. [ ] Watch registration (small, high leverage on the tappiest device).
3. [ ] Water ounces parameter (+ ServingSize enum only if one-shot
   spoken sizes prove wanted).
4. [ ] Describe-to-log with confirmation; extend the eval suite's
   describeFood golden set to cover phrases users would SAY (spoken
   grammar differs from typed).
5. [ ] negativePhrases pass ("delete my log", "undo my water") so
   near-miss phrases don't false-trigger logging.

## Risks / notes

- Free personal team: App Shortcuts need no extra entitlements — no
  provisioning risk.
- Siri phrase matching quality varies with vocabulary size; meal/food
  names with emoji or very long names may not resolve — the containment
  EntityStringQuery mitigates.
- Interactive snippets (iOS 26) are deliberately deferred — polish
  after the four pillars prove out in daily use.
