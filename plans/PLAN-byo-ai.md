# PLAN — Bring-your-own-AI (2026-07-19)

Let the user point Onigiri's AI features at a provider of their choice:
**On-Device (Apple Intelligence)** — today's behavior and the default —
**Anthropic API**, **OpenAI API**, or a **Local server** (an
OpenAI-compatible endpoint: Ollama, LM Studio, llama.cpp server — which is
how Gemma/Qwen/etc. arrive, per the user's pick; an on-device runtime
embedded in the app was explicitly deferred). Decided with the user
2026-07-19: local = server endpoint; all four AI features route through
the picked provider, vision-gated; selection is an explicit Settings
picker, and every failure keeps today's invariant — **silent fallback to
the deterministic path**.

## What routes (the whole FoodIntelligence surface)

| Capability | Entry point | Needs vision |
|---|---|---|
| Describe-it | `describeFood(_:)` | no |
| Meal-name suggestion | `suggestMealName(for:)` | no |
| Label-scan refinement | `refine(_:transcript:)` | no |
| Identify Food (photo) | `identifyFood(from:)` | YES |

Identify Food routes to a BYO provider only when that provider is
vision-capable (Anthropic and OpenAI are; local depends on the served
model — a per-provider vision flag/model field, below). When it isn't,
the photo path falls back exactly as if the provider errored: Apple FM if
the picker says On-Device, else the deterministic `FoodPhotoClassifier`
guesses. The remote prompt gets BOTH the photo and the Vision classifier
guesses — same signals the FM path uses today.

## Architecture (follows the codebase's own conventions)

- **Kit hosts the HTTP clients** — like `OpenFoodFactsClient` and
  `FoodDataCentralClient`: plain URLSession, no SDK dependencies, pure
  request-build + response-parse logic, fixture-tested offline.
  - `AnthropicClient` — Messages API (`x-api-key` + `anthropic-version`
    headers), structured JSON responses (tool-use forced output).
  - `OpenAICompatibleClient` — chat completions with JSON output; a
    `baseURL` parameter makes ONE client serve api.openai.com AND every
    local runner (Ollama/LM Studio speak this API). Optional bearer token
    (empty for stock Ollama; set for reverse-proxied setups).
- **`FoodIntelligence.swift` stays the app-side router and the ONLY file
  importing FoundationModels** (CLAUDE.md rule). Each of the four entry
  points switches on the selected provider: `.onDevice` → the existing
  `*26` FM paths untouched; `.anthropic`/`.openAI`/`.local` → kit client
  with a shared per-task prompt builder, mapping the JSON back into the
  same result structs (`DescribedFood`, `IdentifiedFood`, `ParsedLabel`,
  meal-name string). Prompt text lives beside the FM prompts so the two
  backends can't drift apart silently.
- **`isAvailable` reworked to mean "the SELECTED provider is usable"**:
  On-Device → the current FM availability check; Anthropic/OpenAI → key
  present in Keychain; Local → base URL present. Every AI affordance in
  the UI already hides behind this one flag, so surfaces light up
  consistently when a provider is configured — no per-view changes.
- **Watch/widgets untouched** — nothing outside the app target calls
  FoodIntelligence.

## Configuration & secrets

- **Keychain** (the FDC pattern in `LibraryModels.swift` — service +
  account + read/write/clear helpers; device-local, never synced, never
  exported in backups): service `com.ecliptik.Onigiri.ai`, accounts
  `anthropicAPIKey`, `openAIAPIKey`, `localAIToken` (the optional local
  bearer). Secrets ONLY here.
- **SharedStore defaults** (non-secret, device-local): `aiProvider`
  (picker selection), `anthropicModel`, `openAIModel`, `localModel`
  (free-text ids — providers rename models, never hardcode-gate),
  `localBaseURL`, `localVisionCapable` (Bool for the photo gate).
  Defaults: cheap/fast tiers (e.g. `claude-haiku-4-5`, `gpt-4o-mini`) —
  editable strings.
  - OPEN QUESTION for the user at build time: is the local base URL
    (home-lab hostname) sensitive enough to warrant Keychain too?
    Default plan says defaults; moving it is one accessor.

## Settings UI

A new "AI Provider" section modeled on the Online Database one: the
picker (On-Device / Anthropic / OpenAI / Local server), then per-provider
fields — SecureField for keys (writes straight to Keychain, shows only
presence like the FDC key), model id text field, base URL + optional
token + vision toggle for Local. A "Test connection" row per remote
provider (cheapest possible request; result as a toast).

## Privacy & network (ship-blockers, not afterthoughts)

- The site and README promise "No accounts, no servers." BYO cloud calls
  send food descriptions/label text/photos to the USER'S chosen provider
  under their own key — opt-in and self-configured, but
  **docs/privacy.md (site canonical) + the wiki copy need an "Optional
  AI providers" section** before the feature ships, mirroring how the
  FDC key is disclosed.
- **Local server over plain http on the LAN**: needs an ATS local-
  networking exception plus `NSLocalNetworkUsageDescription` (iOS local-
  network permission prompt) — set in **project.yml**, never the
  generated plist.
- Cloud endpoints are HTTPS; no new ATS holes.

## Phases

1. **Kit: config + clients.** `AIProviderSettings` (defaults + Keychain
   accessors), `AnthropicClient`, `OpenAICompatibleClient`, DTOs per
   task. Unit tests: request-shape + response-parse fixtures, malformed-
   response fallbacks (nil, never throw into the UI).
2. **App: routing.** The four entry-point switches + shared prompt
   builders + result mapping; vision gating; `isAvailable` rework.
   Deterministic fallbacks unchanged and re-verified.
3. **Settings UI** + Keychain wiring + connection tests.
4. **project.yml/ATS + privacy copy** (privacy.md, site, README note).
5. **Verify.** Kit tests; on-device manual pass per provider (Anthropic
   key, OpenAI key, Ollama on the Mac serving Gemma/Qwen — one vision
   model to prove the photo path); the FM eval suite gains an opt-in env
   knob to point the SAME golden sets + Gate thresholds at a BYO
   provider (spot-run, not CI — it spends the user's tokens); deploy.

## Landmines

- Kit stays FoundationModels-free; clients stay SDK-free (URLSession).
- Match the FM paths' failure manners: bounded timeout (~30 s), no
  retries, return nil, deterministic path takes over silently.
- The label-refine call sits inside the scan flow — cloud RTT adds
  latency where FM inference already takes seconds; acceptable, but keep
  the request single-shot and small (transcript text only, no image).
- Anthropic needs `anthropic-version`; Ollama needs NO auth header when
  the token field is empty (sending an empty Bearer breaks some proxies).
- Re-run the FM eval suite after Phase 2 (prompt files are touched when
  extracting shared builders — the suite is the drift alarm).
- Backups/export must NEVER carry the keys (the FDC key already sets the
  precedent — verify the new accounts are excluded the same way).
