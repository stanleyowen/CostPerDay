# CostPerDay

**CostPerDay** is an iOS app that turns what you paid for something into what it's
actually costing you *right now* — a daily rate, amortised over how long you've
owned it or expect to keep it. It exists to make the ongoing cost of ownership
visible, as a small deterrent against impulse purchases.

Built with SwiftUI and SwiftData, targeting iOS 18+.

## Why

A $1,200 laptop doesn't feel like $1,200 once it's a year old — but expressed as
"$1.10 a day, and falling" it stays legible for as long as you own it. CostPerDay
applies that framing to everything you record: electronics, furniture, appliances,
clothing, vehicles, or anything else you spent money on.

## Features

- **Cost per day, two ways** — *To date* (price ÷ days owned, falls the longer you
  keep something) and *Planned* (price ÷ expected lifetime, the rate you budgeted
  for up front).
- **A dashboard** — total daily/monthly/yearly burn rate, spend by sector and
  category, spend by year, and a ranked list of your worst-value items.
- **Multi-currency support** — record an item in the currency you actually paid in;
  the exchange rate is locked at purchase time and everything rolls up into a
  single base currency you choose in Settings.
- **Built-in and custom categories** — over 30 built-in categories across five
  sectors (electronics, home, appliances, personal, active), plus your own.
- **Retire, don't delete** — mark an item sold, given away, or dead to stop its
  cost clock while keeping the history; record what you recovered on resale.
- **Local JSON backup and restore** — export your whole library to a file and
  restore it later; restoring only adds what's missing and never overwrites.
- **Fully localized** — English plus Chinese (Traditional/Simplified), Japanese,
  Korean, Indonesian, Spanish, French, German, Portuguese (Brazil), Russian, and
  Vietnamese.
- **Guided first launch** — a short onboarding flow introduces the core idea and
  the two cost bases before you ever see the tab bar.
- **Everything stays on-device** — no account, no server, no analytics. Your data
  lives in SwiftData locally; the only network call is an optional exchange-rate
  lookup when you record an item in a foreign currency.

## Getting started

**Requirements:** Xcode 16+, iOS 18 SDK, a Mac to build on.

```bash
git clone https://github.com/stanleyowen/CostPerDay.git
cd CostPerDay
open CostPerDay.xcodeproj
```

Select the `CostPerDay` scheme and run on a simulator or device running iOS 18+.

To launch with sample data pre-loaded (Debug builds only), add
`-seedSampleData` as a launch argument in the scheme's Run options.

## How it works

1. **Add an item** — name, category, price, currency, purchase date, and how
   long you expect it to last.
2. CostPerDay immediately shows what that works out to per day, both as budgeted
   (*Planned*) and, once some time has passed, as it's played out so far (*To
   date*).
3. **The Dashboard** rolls every item up into a single daily burn rate, plus
   breakdowns by sector, category, and year.
4. **Retire an item** when you stop using it — its cost clock stops, and any
   resale value is netted off the total.
5. **Back up** your library to JSON from Settings any time, and restore it on
   a new device or after a reinstall.

## Project structure

```
CostPerDay/
├── CostPerDay/
│   ├── CostPerDayApp.swift     # App entry point, SwiftData container, onboarding gate
│   ├── Models/                 # SwiftData models (Item, CustomCategory, ItemCategory, Sector...)
│   ├── Views/                  # Items list, Dashboard, Item editor, Settings, Onboarding
│   ├── Support/                # Formatting, currency, backup, exchange rates, validation
│   └── Resources/              # Localizable.xcstrings (generated, see Localization/)
├── CostPerDayTests/             # Unit tests
└── Localization/                 # Translation pipeline (see below)
```

## Localization

Translations aren't hand-edited in the Xcode string catalog. The source of truth
is [`Localization/keys.json`](Localization/keys.json) (every English string, with
context comments) and one JSON file per language under
[`Localization/translations/`](Localization/translations/).
[`Localization/build_catalog.py`](Localization/build_catalog.py) validates every
translation — key coverage, format-specifier consistency, plural forms — and
merges them into `CostPerDay/Resources/Localizable.xcstrings`:

```bash
python3 Localization/build_catalog.py
```

Adding a new user-facing string means adding it to `keys.json`, adding its
translation to each file in `translations/`, then re-running the script. See
[`Localization/TRANSLATION_GUIDE.md`](Localization/TRANSLATION_GUIDE.md) for the
full conventions (register, glossary, format-specifier rules).

## Testing

```bash
xcodebuild test -project CostPerDay.xcodeproj -scheme CostPerDay \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Covers cost/amortisation math, category resolution, draft validation, exchange
rate handling, and localization consistency.

## Privacy

CostPerDay stores your library locally on-device via SwiftData. Nothing is sent
to a server, and there is no account, tracking, or analytics. The only network
request the app makes is an optional currency-conversion lookup when you record
or rebase an item priced in a foreign currency.
