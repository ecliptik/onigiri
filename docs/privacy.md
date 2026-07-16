---
title: Onigiri Privacy Policy
permalink: /privacy/
---

# Onigiri Privacy Policy

_Last updated: July 16, 2026_

Onigiri is a calorie, nutrition, and water tracker for iPhone, iPad,
and Apple Watch. It is built so that your data stays yours.

## The short version

- Your logs live in **Apple Health** on your device. We never see them.
- Onigiri has **no accounts, no analytics, no ads, and no servers**.
- The only data that ever leaves your device is the **search text or
  barcode** you look up against public food databases.

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

When you search for a food or scan a barcode, Onigiri sends only the
search text or barcode to one of two public services, per your Settings:

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
