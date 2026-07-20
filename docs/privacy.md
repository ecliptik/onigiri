---
title: Onigiri Privacy Policy
permalink: /privacy/
---

# Onigiri Privacy Policy

_Last updated: July 20, 2026_

Onigiri is a calorie, nutrition, and water tracker for iPhone, iPad,
and Apple Watch. It is built so that your data stays yours.

## The short version

- Your logs live in **Apple Health** on your device. We never see them.
- Onigiri has **no accounts, no analytics, no ads, and no servers**.
- **Nothing leaves your device by default.** Online food lookups (the
  search text or barcode sent to public food databases) and the AI
  features are both **off until you turn them on** — offered once
  during onboarding, changeable anytime in Settings.

## Health data

With your permission, Onigiri reads and writes Apple Health (HealthKit)
data: dietary energy, nutrients, sodium, water, body weight, and energy
burned. This data is stored by Apple Health on your device and synced
between your devices by Apple, under Apple's protections. Onigiri never
transmits Health data anywhere, never shares it with third parties, and
never uses it for advertising or research. Deleting the app leaves your
Health data intact in Apple Health; you can also revoke Onigiri's
access at any time in the Health app (Profile → Apps → Onigiri).

## Food database lookups

Online lookups are **off by default** — with them off, food search
uses only your saved library and the scanner reads nutrition labels
on-device. When you turn them on (onboarding or Settings → Online
Database), searching or scanning a barcode sends only the search text
or barcode to one of two public services, per your Settings:

- **[Open Food Facts](https://world.openfoodfacts.org)** — barcode
  scans and text search. Data licensed under the Open Database License
  (ODbL).
- **[USDA FoodData Central](https://fdc.nal.usda.gov)** — optional text
  search, used only if you supply your own free api.data.gov key. Your
  key is stored in the device Keychain and sent only to USDA.

These requests include no Health data, no identity, and no identifiers
beyond your device's network address, which every internet request
carries. Each service's own privacy policy governs what it does with
queries it receives.

## AI features (optional)

Onigiri's AI features — food estimates, meal-name suggestions,
nutrition-label reading, and Identify Food — are **off by default**.
Nothing AI-related runs until you turn the switch on in Settings → AI.
When you do, they run **on-device** through Apple Intelligence on
devices that support it — on that setting, nothing about them leaves
your iPhone.

Two of these features are hybrids with an on-device first stage that
runs no matter which provider you pick: nutrition labels are read by
Apple's on-device text recognition first, and the AI only fills in
values the local reader missed; food photos are screened by Apple's
on-device image classifier before anything is identified. Barcode
scans never use AI at all. With the default Apple Intelligence engine,
every stage stays on the phone.

In Settings you can instead bring your own AI provider. When you do,
those features send only the text you typed, the label transcript
being read, or the photo being identified to the provider **you**
configured, under your own API key:

- **[Anthropic](https://www.anthropic.com/legal/privacy)** — your
  Anthropic API key, sent only to Anthropic.
- **[OpenAI](https://openai.com/policies/row-privacy-policy/)** — your
  OpenAI API key, sent only to OpenAI.
- **A local server you run** (Ollama, LM Studio, or any
  OpenAI-compatible endpoint) — requests go only to the address you
  configure, typically on your own network, and to nowhere else.

API keys are stored in the device Keychain, are never included in
backups or library exports, and are sent only to their own provider.
These requests carry no Health data and no identity. Each provider's
own privacy policy governs what it does with the content it receives.
AI providers are off unless you configure one — deleting the provider's
key or switching back to On-Device stops all AI traffic immediately.

## What Onigiri stores on your device

Your food and meal library, goals, and preferences are stored locally
(and shared with the app's own widgets and watch app). Library backups
are saved to the app's Documents folder under your control, visible in
the Files app. Nothing is uploaded.

## Data collection

Onigiri collects no data. There are no analytics or crash-reporting
SDKs, no advertising identifiers, and no tracking.

## Not medical advice

Calorie budgets, deficit targets, and weight projections are
informational estimates computed from your own numbers. They are not
medical advice. Consult a qualified professional before making
significant changes to your diet or exercise.

## Contact

Questions or concerns: [open an issue](https://github.com/ecliptik/onigiri/issues)
on the project repository.

## Changes

Material changes to this policy will be noted in the app's release
notes and on this page.
