# Translation task — CostPerDay (iOS app)

## What the app is
A personal finance app that records physical possessions (electronics, furniture,
appliances, clothing, bicycles, etc.) and shows the **cost per day** of owning each
one — purchase price amortised over how long it has been owned or is expected to
last. Its purpose is to discourage impulse purchases by making the daily cost of
ownership visible. It supports multiple currencies, custom categories, and JSON
backups.

## Register — IMPORTANT
Use a **formal, professional register** in every language. This is a serious
finance tool, not a playful consumer app.
- Address the user formally where the language distinguishes (de: *Sie*, not *du*;
  fr: *vous*, not *tu*; es: *usted*; ru: *вы*; vi: use neutral/formal forms;
  id: formal Bahasa, avoid slang; ja: です・ます調 (polite form), avoid casual;
  ko: 합쇼체/해요체 polite endings).
- Prefer complete, grammatical sentences. Avoid contractions, slang and exclamation marks.
- Use standard financial/accounting terminology where one exists in the language
  (e.g. "amortised", "resale value", "exchange rate", "base currency").

## Input
`keys.json` in this directory: a JSON object mapping each **English source string**
(the key) to a **comment** giving its UI context. Read it in full.

## Output
Write ONE file per language: `<lang>.json` in this directory, e.g. `ja.json`.
It must be a JSON object with **exactly the same 241 keys** as `keys.json`.
Each value is either:
  - a plain string — the translation, OR
  - an object of CLDR plural forms (see below) for the plural-sensitive keys.

Nothing else in the file. No markdown fences, no commentary.

## Format specifiers — CRITICAL
Keys contain printf specifiers that MUST be preserved exactly:
  `%@`   — a string (a price, a duration, a currency code, a date)
  `%lld` — an integer
  `%%`   — a literal percent sign
Rules:
- Every specifier in the key must appear in the translation, the same number of times.
- Never translate, reorder-in-place, or alter a specifier's spelling.
- If the target language needs a DIFFERENT word order than English, you MUST use
  positional specifiers so the arguments still map correctly:
  `%1$@`, `%2$@`, `%1$lld`, etc. (numbering follows the English order.)
  Example: English `"%@ · %@ owned"` → if your language must put the duration first,
  write `"%2$@ 保有 · %1$@"` — NOT `"%@ 保有 · %@"`.
- Do not add or remove specifiers.

## Plural-sensitive keys
For these keys ONLY, output an object keyed by the CLDR plural categories your
language actually uses (`one`, `two`, `few`, `many`, `other` — `other` is always
required). For languages with no plural inflection (zh-Hant, zh-Hans, ja, ko, id, vi)
supply only `{"other": "..."}`.

  "%lld days"
  "%lld months"
  "%lld years"
  "%lld items"
  "%lld retired"
  "Added %lld items."
  "Restored %lld custom categories."
  "Skipped %lld entries already present."
  "%lld items purchased in another currency use the exchange rate recorded at the time of purchase."
  "Your %lld items are currently priced against %@. This rate re-expresses them in %@. The prices originally entered remain unchanged; only the conversion is adjusted."

Example (French):
  "%lld items": {"one": "%lld article", "other": "%lld articles"}
Example (Japanese):
  "%lld items": {"other": "%lld 件"}

Every OTHER key must be a plain string, even if it contains %lld
(e.g. "%lld mo" and "%lld yr" are fixed abbreviations — plain strings).

## Domain glossary — translate these consistently
- **Item** — a physical possession being tracked.
- **Cost per day** — purchase price ÷ days; the app's core metric.
- **To date** / **Planned** — the two cost bases: actual-so-far vs. as-budgeted.
- **Fully amortised** — the item has outlived its expected lifetime; every further
  day of use is effectively free. Use the accounting term where one exists.
- **Retire / Return to service** — mark an item as no longer in use (this stops its
  cost clock) and the reverse. NOT "delete".
- **Sector** — the broad grouping above category (Electronics, Home & Furniture, …).
- **Base currency** — the single currency all totals are converted into.
- **Resale / Recovered value** — money recouped by selling the item on.
- **Expected lifetime** — how long the owner expects the item to remain in service.

## Short strings — keep them short
Many keys are table-row labels, chart axis titles or buttons and appear in tight
layouts. Keep translations approximately as short as the English. In particular:
"%lld mo", "%lld yr", "%lld yr %lld mo", "per day", "per week", "per month",
"per item", "Price", "Name", "Sort", "Rate", "Edit", "Save", "Cancel", "Delete",
"OK", "Undo", "Dismiss", "0", "%lld".

## Leave untouched
- `"0"` and `"%lld"` — bare placeholders; output them unchanged.
- Do not translate the app name "CostPerDay" or "GitHub" or "JSON".
- "View on GitHub" — translate only the "View on" part.

## Before you finish
Verify programmatically (write a throwaway python check) that:
  1. your file is valid JSON,
  2. its key set is byte-identical to `keys.json`'s key set,
  3. for every key, the multiset of format specifiers in your value(s) matches the key
     (treating `%1$@` as equivalent to `%@`, `%1$lld` as `%lld`).
Fix anything that fails, then report only: languages written + confirmation all
three checks passed.
