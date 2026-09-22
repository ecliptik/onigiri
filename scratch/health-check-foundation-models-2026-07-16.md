# Foundation Models Audit — Onigiri/Models/FoodIntelligence.swift (2026-07-16)

## Summary
- CRITICAL: 0, HIGH: 0, MEDIUM: 2, LOW: 3
- Readiness: PRODUCTION-READY (two MEDIUM completeness gaps)

## Boundary Check
Verified: Packages/OnigiriKit has zero matches for FoundationModels|LanguageModelSession|@Generable|@Guide — kit does not import Foundation Models. FoodIntelligence.swift confirmed sole bridge, guarded with `#if canImport(FoundationModels)`. No violation.

## Foundation Models Map
- 3 LanguageModelSession instances, all created fresh per-call (describeFood26, suggestMealName26, refine26) — stateless, single-turn, no shared session.
- 3 @Generable structs (FoodEstimate, MealName, LabelReading), all flat, 100% @Guide coverage on numeric properties.
- Availability discipline: double-gated — `isAvailable` for UI + independent re-check inside each worker function before creating a session.
- Error handling: uniform generic catch-and-fallback in all three functions, by explicit project design (CLAUDE.md: "every model failure falls back silently to the deterministic path").

## Issues by Severity

### MEDIUM — No evaluation suite for three shipping AI affordances
**File**: `Onigiri/Models/FoodIntelligence.swift` (whole file)
**Issue**: describeFood, suggestMealName, refine have no Evaluation/ModelSample/Evaluator suite. On-device model changes underneath the app on every OS update with no code change — quality can silently drift with nothing to catch a regression.
**Fix**: Encode a small (10-15 sample) golden set of ModelSamples with range-sanity Evaluators (kcal/sodium within plausible bounds, name non-empty).

### MEDIUM — User-supplied text and OCR transcript interpolated directly into prompt body
**File**: `Onigiri/Models/FoodIntelligence.swift:103, 137, 194`
**Issue**: All three call sites interpolate untrusted text (user description, food names, OCR label transcript) directly into the prompt turn content. No sanitization.
**Impact**: Low in practice — @Generable/@Guide constrains output shape/range, results always shown for user review before saving (never auto-committed). Worst case is a wrong value the user notices and corrects.
**Fix**: Not urgent given containment + human-review design. Optionally note in-prompt that content is untrusted data, not instructions.

### LOW — No explicit cancellation surface for in-flight generations
**File**: `Onigiri/Views/FoodFormView.swift:584-600`, `Onigiri/Views/MealFormView.swift:284-290`, `Onigiri/Views/ScanSheet.swift:201-229`
**Issue**: No stored Task handle to cancel, no Cancel control in UI. Low impact — prompts are short/bounded.

### LOW — Fresh LanguageModelSession per call, no reuse/pooling
**File**: `Onigiri/Models/FoodIntelligence.swift:96, 131, 185`
**Issue**: Minor cold-start cost per tap; actually the recommended pattern here since calls are independent/stateless (pooling would risk cross-contamination). No change recommended.

### LOW — Generic-only error handling (intentional, documented design — informational only)
**File**: `Onigiri/Models/FoodIntelligence.swift:113-116, 141-144, 211-214`
**Issue**: Not a defect — matches CLAUDE.md's documented silent-fallback contract. No fix needed.

## Recommendations
1. No CRITICAL/HIGH issues.
2. Short-term: add a small Evaluations-based regression suite (10-15 samples) for the three affordances.
3. Long-term: revisit session reuse/cancellation only if usage grows into multi-turn/longer conversations.
