# PLAN — Fall back to Apple Intelligence when the provider can't be reached (2026-08-07)

> **SHIPPED** as v2.18.0 (2026-08-08), and VERIFIED ON DEVICE in the
> condition that prompted it: airplane mode with a remote provider
> selected, estimate answered by Apple Intelligence (the user).
>
> Verification that ran: 398 kit tests; the eval suite 10/10 with ZERO
> skips (245 s); `AIFallbackTests` 3/3, which proves the whole path with
> no network by pointing the Local provider at `127.0.0.1:1` — refused
> instantly, estimate still arrives stamped `.onDevice` after 16.5 s of
> real on-device inference, and with the switch OFF the same fixture
> produces nothing.
>
> Deltas from the plan as written:
>
> 1. `AIChat` became `public` (its two deadlines only — the helpers stay
>    internal) so the app can pass `fallbackTimeout`.
> 2. The engine rides to the UI on `ScannedProduct.aiEngine` as planned,
>    and is stamped at the ENTRY POINT rather than at each construction
>    site — the entry point is the one place that knows whether the
>    remote replied or the fallback ran.
> 3. `identifyFoodOnDevice(from:)` had to be split out: the photo
>    branch's fallback cannot re-enter `identifyFood(from:)`, which
>    would re-read the selected provider and try the remote text relay
>    a second time against the same dead network.
> 4. `PreferenceSnapshotTests`' exact-count tripwire fired on the new
>    sweep key (48 → 49), as designed; updated with a named assertion
>    for the key and the reason.
> 5. The first `AIFallbackTests` run reported TEST SUCCEEDED while
>    executing ZERO tests — a new file needs `xcodegen generate` before
>    it is in the target. Checking for skips is what caught it.

## The complaint

Identifying and logging food with a BYO-AI provider failed in an area
with no cell coverage. The phone had a perfectly good on-device model
sitting idle, and nothing routed to it: picking Anthropic/OpenAI/Local
in Settings means every AI call goes there, and a call that can't leave
the device fails all the way down to the deterministic path.

## The rule

**A provider that can't answer right now is not the same as a provider
that answered no.** When the selected engine is unreachable or
temporarily failing, Apple Intelligence answers instead — if the user
left the new Fallback switch on and the device actually has it.

Decided with the user 2026-08-07:

| | |
| --- | --- |
| **Trigger** | Unreachable **and** transient service failures |
| **Default** | On |
| **Disclosure** | The provenance caption names the engine that really answered |
| **Wait** | ~10 s deadline while fallback is armed (30 s otherwise) |

### What falls back, precisely

Falls back — *couldn't get an answer*:

- `URLError`: `.notConnectedToInternet`, `.networkConnectionLost`,
  `.cannotConnectToHost`, `.cannotFindHost`, `.dnsLookupFailed`,
  `.timedOut`, `.dataNotAllowed`, `.internationalRoamingOff`,
  `.secureConnectionFailed`
- HTTP `408`, `429`, and `500…599`

Does **not** fall back — *the provider answered, and the answer is a
problem the user should see*:

- HTTP `401` / `403` (bad or revoked key), `400` (malformed request),
  any other 4xx
- A refusal, or JSON the decoder can't use
- `.serverCertificateUntrusted` and friends: a certificate problem on a
  local server is a misconfiguration, and silently papering over it
  would hide it forever

`.secureConnectionFailed` is deliberately in the first list: captive
portals (hotel, café) fail exactly this way and are "no internet" in
every sense the user cares about. Nothing is sent on a fallback, so
erring toward it costs no privacy.

## Architecture

### 1. The classifier — kit, pure, tested

`AIChatClients.swift` already owns `AIChatError`. Add beside it:

```swift
/// Could the selected provider not answer RIGHT NOW (so another engine
/// should try), or did it answer with something the user needs to see?
public enum AIReachability {
    public static func isTransient(_ error: Error) -> Bool
}
```

Pure, no I/O, and the only place the two lists above exist. Tests in
`AIReachabilityTests.swift`: every `URLError` code in the list, a
representative one outside it, 408/429/500/503 true, 400/401/403/404
false, and a non-network error false.

### 2. The remote choke point reports WHY it failed

Every remote call in the app funnels through one function,
`FoodIntelligenceRemote.completeRemote(system:user:imageJPEG:)`, which
today returns `Data?` and swallows the reason. That single return type
is why nothing downstream can tell "offline" from "refused".

```swift
enum RemoteOutcome {
    case answered(Data)
    /// The provider replied, and the reply is unusable. No fallback.
    case rejected
    /// Couldn't get an answer now (AIReachability.isTransient). Fallback
    /// may run.
    case unavailable
}
```

Each `xxxRemote(…)` helper returns `RemoteAnswer<T>` — `.answered(T?)`
or `.unavailable` — so the outcome is compile-checked all the way to the
entry point. **No shared "last error" state**: these calls can overlap
(the Log sheet can have an estimate in flight while a scan runs), and a
global would attribute one call's failure to another.

### 3. The entry points gain one rung

The seven paired-engine entry points in `FoodIntelligence.swift`
(`refine`, `describeFood`, `describeMeal`, `readNutritionScreenshot`,
`readFoodSign`, `suggestMealName`, `identifyFood(from:)`) all share a
shape today:

```swift
if AIProviderSettings.selected != .onDevice { return await xxxRemote(…) }
…on-device…
```

which becomes:

```swift
if AIProviderSettings.selected != .onDevice {
    switch await xxxRemote(…) {
    case .answered(let value): return value
    case .unavailable:
        guard AIProviderSettings.fallbackToOnDevice, onDeviceAvailable else { return … }
        // fall through to the on-device path below
    }
}
…on-device…
```

`identifyFood(photo:)` needs no special case: a vision-capable remote
gets the JPEG, and the fallback lands on `identifyFood(from: guesses)`
— the classifier-label text relay, which *is* the on-device path. The
Vision classifier has already run by then and is local anyway.

### 4. The shorter deadline

`AIChat.timeout` is 30 s with no retries. Hard-offline already fails
instantly (the OS knows there is no route), so 30 s only bites on the
weak-signal case — which is the reported one.

`AIChat.session(timeout:)` and both clients' `completeJSON` gain a
`timeout:` parameter defaulted to the current 30 s, so every existing
call site is unchanged. `completeRemote` passes `AIChat.fallbackTimeout`
(10 s) when `fallbackToOnDevice && onDeviceAvailable && selected != .onDevice`,
and the full 30 s otherwise. A timeout at either length classifies as
`.unavailable`.

### 5. Provenance — the part that is easy to get wrong

Eight call sites read `AIProviderSettings.selected.estimateCaption`.
Every one of them would **lie** after a fallback: an on-device answer
captioned "AI estimate from Anthropic" is exactly the claim the caption
exists to prevent, and CLAUDE.md's rule is that the provider name says
where the text went.

The rule to apply:

- **Prospective** copy names the SELECTED provider — "✨ Estimate with
  Anthropic" is a description of what tapping will do
  (`AIEstimateSection.swift:38`).
- **Retrospective** provenance names the engine that ANSWERED —
  `AIEstimateSection.swift:104`, `FoodFormView.swift:246` and `:459`,
  `QuickLogSheet.swift:276`, `FoodsView.swift:234`,
  `MealFormView.swift:438-439`.

Mechanically: `DescribedFood`, `DescribedMeal` and `IdentifiedFood` gain
`engine: AIProvider`, and `ScannedProduct` (kit) gains
`aiEngine: AIProvider?` — nil for anything not AI-derived — so the
engine rides with the values through `ProductPrefill` into the form,
the way `aiGenerated` already does. Retrospective sites read
`product.aiEngine?.estimateCaption`.

`refine`, `readNutritionScreenshot` and `readFoodSign` surface no
provider-named caption, so they need no engine field — only the
fallback rung.

### 6. The setting

`AIProviderSettings` gains:

```swift
public static let fallbackOnDeviceKey = "aiFallbackOnDevice"
/// Default ON, so ABSENT must read true — `defaults.bool(forKey:)`
/// alone would make a fresh install read false and quietly ship the
/// behavior we're fixing.
public static var fallbackToOnDevice: Bool {
    guard SharedStore.defaults.object(forKey: fallbackOnDeviceKey) != nil else { return true }
    return SharedStore.defaults.bool(forKey: fallbackOnDeviceKey)
}
```

Add the key to `PreferenceSnapshot.settingsSweepKeys` beside the other
`AIProviderSettings` keys, or a settings reset will strand it.

**Settings → AI**, under the provider picker:

- Hidden entirely when the selected provider IS `.onDevice` — there is
  nothing to fall back from.
- Shown but disabled when `onDeviceAvailable` is false (no Apple
  Intelligence, or iOS < 26), with a footer saying why rather than a
  dead switch.
- Toggle: **"Fall back to Apple Intelligence"**
- Footer (formal register, per the copy rule): "When <Provider> can't be
  reached — no signal, or a temporary outage — estimate on this iPhone
  instead. Nothing is sent anywhere in that case."

`FoodIntelligence.isAvailable` does **not** change. An unconfigured
provider is a setup problem the user should fix, not a network blip;
lighting the affordances up on the back of the fallback would hide it.

## Verification

- Kit: `AIReachabilityTests` (above) — the whole classification table.
- **A deterministic end-to-end test, no network required**: set provider
  `.local` with base URL `http://127.0.0.1:1/v1` and a model name. Port 1
  refuses instantly → `.cannotConnectToHost` → `.unavailable` → fallback.
  Opt-in UI test `AI_FALLBACK=1` on an iOS 26 sim with AI enabled:
  assert an estimate still arrives and its caption reads **Apple
  Intelligence**, not Local AI. The same fixture with Fallback OFF must
  produce NO estimate — that half is what proves the switch works.
- Re-run the `OnigiriTests` eval suite: prompts are untouched, so this is
  a no-regression check, but the entry-point signatures move under it.
- On device, the real check: airplane mode with a remote provider
  selected, then Identify Food.

## Fallout / open

- **`describeFood` and `suggestMealName` have no `guard isAvailable`**
  (`FoodIntelligence.swift:108` and `:379`), unlike the other five.
  REVIEWED 2026-08-07 — **not a live bug**; all three production call
  sites gate:
  - `DescribeFoodIntent.swift:25` — explicit guard, immediately before.
  - `EstimateRow.swift:80` — `if FoodIntelligence.isAvailable` opens the
    branch and `:128` closes it, so the tap, the retry button AND the
    `onAppear` resume are all inside; `estimate()` is unreachable from
    outside it.
  - `MealFormView.swift:189` — gates the suggest button.

  `refine()` was different because the LABEL-SCAN cascade calls it with
  no view in the way. Same-shaped omission, different reachability.

  Added anyway as step 0, as hygiene rather than a fix: this feature puts
  a second engine behind `isAvailable` and touches all seven entry
  points, five-guarded-two-not invites the wrong assumption, and every
  current gate is a RENDER-TIME read of a static (not `@AppStorage`)
  value. The eval suite sets the master switch itself
  (`FoodIntelligenceEvals.swift:81`) and skips unless available (`:92`),
  so the guards are a no-op there.
- The watch runs no AI, so nothing here touches WatchSync.
- Privacy policy: the site and wiki describe AI as going to the selected
  provider. A fallback only ever sends LESS, but "if that provider can't
  be reached, the estimate runs on your iPhone instead" is worth a line
  in both.

## Order of work

1. Kit: `AIReachability` + tests.
2. `RemoteOutcome`/`RemoteAnswer` through `completeRemote` and the seven
   `xxxRemote` helpers; entry-point rungs. No behavior change yet —
   fallback reads its default but nothing else moves.
3. The timeout parameter.
4. Provenance: engine fields + the eight caption sites.
5. The Settings toggle, footer, and sweep-key registration.
6. Tests (kit + the port-1 UI test), sim pass, device pass in airplane
   mode.
7. Version bump, release.
