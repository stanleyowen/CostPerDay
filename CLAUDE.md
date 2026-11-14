# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Wallet (formerly Tally and Dayrate, originally CostPerDay; the GitHub repo is `stanleyowen/Wallet`) is an iOS 18+ SwiftUI + SwiftData personal-finance app: a wallet / expense tracker (accounts, transactions, transfers, budgets, labels, detailed reports, BudgetBakers Wallet CSV import, App Intents for Shortcuts/Siri) integrated with an ownership tracker that shows the daily cost of the things you buy (price amortised over days owned or expected lifetime). Fully on-device; the only network call is an optional exchange-rate lookup (`open.er-api.com`). No third-party dependencies.

## Git

Never add a `Co-Authored-By` trailer or any other AI attribution to commit messages or PR descriptions.

## Commands

```bash
# Build
xcodebuild build -project Wallet.xcodeproj -scheme Wallet \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# All tests (Swift Testing, not XCTest)
xcodebuild test -project Wallet.xcodeproj -scheme Wallet \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# Single suite or test: -only-testing:<Target>/<SuiteStruct>[/<testFunc()>]
xcodebuild test -project Wallet.xcodeproj -scheme Wallet \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WalletTests/DraftTests

# Regenerate the string catalog after changing any translation
python3 Localization/build_catalog.py
```

Debug builds accept launch arguments (all inert in Release, see `Support/DebugFlags.swift` and `SampleData`):
- `-seedSampleData` — items plus two accounts and ~3 months of transactions in an empty store. With the base currency set to TWD it seeds a Taipei profile instead (`SampleDataTaiwan.swift`: NT$ prices, five accounts, ~5 months simulated day by day so no account is overdrawn); set it before the first seeded launch with `xcrun simctl spawn <id> defaults write com.stanley.wallet baseCurrency TWD`.
- `-importWalletCSV <path>` — import a Wallet CSV at launch (idempotent).
- `-skipOnboarding`, `-initialTab home|transactions|reports|items|settings`, `-openComposer`, `-openRecord` (the latest transaction in the editor), `-scrollAnchor center|bottom`, `-reportFocus <category key or group:raw>`, `-reportDay <day of month>`, `-selectAccounts <n>` (pre-select the first n Home account cards), `-openAccount` (the first account's page), `-openFilters` (the Transactions filter sheet) — for scripted simulator screenshots (`xcrun simctl launch … ` then `xcrun simctl io booted screenshot`).

Free-provisioning builds on a real iPhone expire after 7 days. `Scripts/install-reinstall-agent.sh` installs a LaunchAgent that, every 2 h, runs `Scripts/reinstall-on-device.sh`: once 5 days have passed since the last success it builds the last commit with a fresh profile and installs it over the app on the iPhone (same Wi-Fi or cable), notifying on success or failure. The agent can't read `~/Documents`, so it builds from a bare mirror in `~/Library/Application Support/WalletReinstall` that git hooks in `.git/hooks` keep on the checked-out commit. Log: `~/Library/Logs/WalletReinstall.log`.

The Xcode project uses file-system-synchronized groups, so new Swift files under `Wallet/` or `WalletTests/` are picked up without editing `project.pbxproj`.

## Architecture

**Persistence & data-safety invariants** — these exist to protect users' on-disk data; don't "clean them up":
- The bundle ID is `com.stanley.wallet` (test bundle `com.stanley.WalletTests`); it was deliberately moved off the old `com.stanley.Dayrate`, so this installs as a separate app from old Dayrate/Tally builds (move data across with a backup). Don't change it again: a new bundle ID means a new, empty store.
- In user-facing text, "Wallet" is this app; the BudgetBakers app is always called "BudgetBakers" (or "BudgetBakers Wallet") so the two never read as the same thing.
- Transactions are the `@Model` class `Record` (not `Transaction`, which collides with SwiftUI). `RecordCategory`, `RecordKind`, `AccountKind`, `BudgetPeriod` raw values are persisted: add cases, never rename them.
- Records point at accounts by `accountID`/`toAccountID` UUIDs, not relationships (cheap date/account predicates, no surprise cascades). The only relationship is `Record.item` ↔ `Gadget.records` (nullify both ways — deleting either side never deletes money history). Deleting an account deletes its income/expense records and turns its transfers into "outside Wallet" transfers (`LedgerActions.delete`, shared by the account editor and the Accounts list swipe).
- Amounts are positive magnitudes; `kind` carries direction. A transfer with `accountID == nil` came from outside the tracked accounts; `toAccountID == nil` went outside. `toAmount` (0 = same as `amount`) is the destination-currency amount of a cross-currency transfer.
- `Item` is a `typealias` for the `@Model` class `Gadget`. SwiftData derives the entity name from the class name, so renaming `Gadget` would orphan existing stores.
- `ItemCategory` raw values are persisted on every item: add cases, never rename them.
- An item's `categoryRaw` is either an `ItemCategory` raw value or a custom category key (`"custom:" + uuid`). Always resolve it for display through `CategoryCatalog.display(for:)`, which also handles deleted/unknown categories (`isMissing`) rather than reassigning them.
- `DataStore` (`Support/DataStore.swift`) owns the single container shared by the app and the App Intents, and falls back to an in-memory container if the real store can't open, and the UI shows a banner. Model changes must remain lightweight-migratable (all stored properties have defaults).

**Multi-currency model** — each item stores `price` in its own `currencyCode` plus `rateToBase`, a rate locked at purchase time (and an optional `resaleRateToBase`). Records do the same (`amount`, `currencyCode` = the source account's currency, locked `rateToBase`). All aggregate math is done in the user's base currency (`@AppStorage("baseCurrency")`). Changing the base currency calls `Gadget.rebase`, `Record.rebase` and `Budget.rebase` to rescale stored rates/limits; original amounts are never modified. Foreign account balances convert at the most recently locked rate for that currency (`Ledger.latestRates`), so net worth works offline.

**Ledger math lives in one place too** — `Support/Ledger.swift` (balances, net worth, net-worth series) and `Support/ReportEngine.swift` (`ReportPeriod`, `Report.build`, `BudgetStatus`) are pure functions over `Flow`, a Sendable value snapshot of a `Record`. Transfers never count as income or spending; accounts with `excludeFromStats` count toward balances but not reports. A running period is compared like-for-like with the same elapsed stretch of the previous one. Screens build a `LedgerSnapshot` once per render.

**Charts are filters** — Reports keeps a `ReportFocus` (category/group, label, weekday, day) that `Report.build` applies to every figure; `day` only highlights and lists, it doesn't narrow totals. Tapping a slice/row/bar/day/label/account sets it; bars wider than a day zoom the period instead (`zoomTrail` steps back out). Bar-chart taps go through `View.onChartTap`, a tap (not drag) overlay so scrolling over charts still works. The filter bar converts the focus into a `TransactionFilter` for "Show N transactions".

**Wallet import** — `Support/CSV.swift` (RFC 4180 parser, lenient numbers, formula-injection-safe writer) and `Support/WalletImport.swift` turn a BudgetBakers export into a `Plan` before anything is written; `LedgerWriter` (`@ModelActor`) inserts it off the main actor. Transfer legs sharing a timestamp are re-paired; unpaired legs become outside transfers. Categories map by `envelope_id`, then English name. Each record gets a hashed `importKey`, so re-importing a newer export only adds what's new — keep keys stable.

**Shortcuts** — `Intents/WalletIntents.swift`: Add Transaction (category inferred from history via `SuggestionIndex` when omitted), Get Balance, Get Spending, New Transaction (opens the composer through `AppRouter`). Shared write paths live in `LedgerActions`.

**Cost math lives in one place** — the `ItemFields` protocol (`Models/ItemFields.swift`) holds all conversion and cost-per-day logic (`netCost`, `daysOwned`, `plannedDays`, `costPerDay(mode:)`, etc.) as extensions. Both the persisted `Gadget` and the unmanaged `ItemDraft` conform, so edit forms preview costs from the draft. Functions take a `now:` parameter so tests can pin time. `CostMode` (`.actual` = "To date", `.planned` = "Planned") selects which reading the UI shows.

**Draft editing pattern** — edit forms bind to `ItemDraft` / `CustomCategoryDraft` / `RecordDraft` / `AccountDraft` / `BudgetDraft` (plain structs), never to the live `@Model`, and write back only via `apply(to:)` on Save. This prevents SwiftData autosave from persisting edits the user cancels. Follow this for any new edit form. `DraftTests` pins this behavior.

**Validation** — `ItemValidation.issues(for:baseCurrency:)` is the single source of truth for what a valid item is, shared by the edit form, backup import, and tests.

**Backup** — `Backup.swift` defines a versioned JSON format (`BackupFile`, `formatVersion`, now 3) that is deliberately independent of the SwiftData schema. v3 adds accounts, records (with item links by item identity) and budgets, restored by `Backup.restoreLedger` after items. Restore is additive only (skips entries already present, never overwrites). New fields must be optional so older backups (including Dayrate's) still decode.

**Security** — optional app lock (`Support/AppLock.swift`, `.deviceOwnerAuthentication` so the passcode is always a fallback; toggling it requires authentication), a privacy cover in the app switcher when locked, and exports written with complete file protection.

**Exchange rates** — `ExchangeRateService` is an actor with an injectable `URLSession` and `UserDefaults`; it caches per-base snapshots for 12h and serves stale cache as an offline fallback. Tests stub the network via a custom `URLProtocol`.

## Design system

`Support/Theme.swift` holds the visual identity and shared components; reuse them rather than restyling per screen.
- **Brand:** the mark is a classic wallet — a brown leather bifold with saddle stitching and a snap strap, three cards (coral, gold, white) fanned out of the top, on warm cream (`BrandMark`). Interface colours come from the icon, and the brand accent is kept apart from money meanings so a button never reads as "spent": `Brand.accent` (teal from the card stripe, also the `AccentColor` asset — keep them in sync) for anything tappable or selected, with `Brand.gradient` (teal → `Brand.highlight`) for the + button and single-series charts; `Brand.expense` (coral) only for money out, `Color.income` (green) for money in; `Brand.night` (deep teal ink) for hero surfaces; `Brand.amber` (gold) for "per day" highlights; `Brand.leather` for the glow under the mark. Don't use `Color.accentColor` — it ignores `Brand.accent` in code.
- **The curve:** `BrandCurve` is the normalised `k/(t+k)` "price ÷ days" hyperbola behind the item hero card (`HeroBackground`) and the onboarding demo.
- **Ledger components:** `RecordRow`, `AccountCard`, `KindPicker`, `FloatingAddButton`, `LabelChips`, `ChangeBadge`, `FigureColumn`, `TrendChart` (explicit Y domain — don't let `AreaMark` drag the axis to zero). `PeriodStepper` is the one period control (‹ title ›) on Reports, the Transactions tab and account pages; transaction lists keep every filter, the period included (`TransactionPeriodControl` over `TransactionPeriod`), in `TransactionFilterSheet` behind `FilterToolbarButton`, show the period under the title (`periodSubtitle`), and step it with a sideways swipe on the summary (`PeriodSwipe`). Don't pin controls under a large title — the list jumps as the title collapses — and keep the bottom of the screen for the tab bar and +. Amounts are typed on the system decimal keyboard; `AmountInput` keeps the text well-formed in the user's locale and the currency's decimals.
- **Components:** `ItemGlyph` (category icon in a lifetime-progress ring), `CategoryTile`, `Chip`, `CostModePicker` (the shared To date/Planned switch with its explainer popover), `CostPeriod` (day/week/month/year), `InfoRow`, `CardHeader`, and the `.card()` modifier.
- **App icon:** generated by `python3 Design/make_icon.py Wallet/Assets.xcassets/AppIcon.appiconset`, which writes the default, dark and tinted variants under the asset catalog's file names. Its geometry and colours match `BrandMark.Geometry`/`Palette`, so change both together.
- **README images:** `python3 Design/make_readme_images.py <shots_dir> Design/screenshots` builds the hero banner and screenshots. Take screenshots only from a simulator seeded with `-seedSampleData` — the repo is public, never use real data.
- **Row actions — the same everywhere** (`Views/Components/RowActions.swift`): every list row for something the user owns (transaction, item, account, budget, custom category) gets swipe left → Delete (red) + Edit (`editActionTint`); swipe right → its one specific action (Duplicate a transaction, Retire/Return an item, Archive/Unarchive an account; orange to put away, green to bring back); long press → a menu with the same actions (Edit, specific ones, Divider, Delete). Transaction rows anywhere use `.recordActions(record)`; rows in cards (Home, Reports) get the menu only, since they can't swipe.
- **Deleting:** always red and always confirmed with the same centred alert (Cancel + red Delete), wherever it starts — swipe, menu, detail screen or editor. Build the alert from a `DeleteRequest` factory (`.record`, `.item`, `.account`, `.budget`, `.category`) so each kind has one wording; list rows set `router.pendingDelete` (shown by the root view), sheets and detail screens use `.deleteConfirmation($request)`. Swipe Delete uses `SwipeDeleteButton` (red tint, no `role`, so the row doesn't animate away before the answer); other Delete buttons use `role: .destructive` plus `.tint(.red)`. Never a `confirmationDialog` action sheet, never an instant delete.
- **Cancel:** every sheet's Cancel is red (`CancelButton`). Editors use `.cancelAction(hasChanges:perform:)`: with unsaved changes it asks with a centred "Discard unsaved changes?" alert and blocks swipe-to-dismiss; with none it just closes. `hasChanges` compares the draft (all drafts are `Equatable`) with a baseline taken once the editor has filled in its own defaults — never re-fetch or rebuild anything to decide it.
- **Actions vs settings:** something that happens (archive, retire, delete) is a button that does it, labelled with the verb ("Archive account" / "Unarchive account"); a toggle is only for an ongoing setting ("Exclude from statistics").
- **Derived data:** screens compute their derived data once per render (`ItemListView`'s `Snapshot` and `ItemRowModel`, `DashboardView`'s `Stats`, `TransactionsView`'s `Snapshot`, `LedgerSnapshot`, `Report`). Don't turn these back into computed properties that are read repeatedly.

## Localization

Do not hand-edit `Wallet/Resources/Localizable.xcstrings` — it is generated. To add or change a user-facing string:
1. Use the English text as the key in code (`String(localized: "...", comment: "...")` or a SwiftUI `Text` literal).
2. Add it to `Localization/keys.json` (key → context comment).
3. Add a translation to every file in `Localization/translations/` (11 languages). Plural-sensitive keys are objects of CLDR forms and must also be listed in `Localization/en_plurals.json` for the English forms.
4. Run `python3 Localization/build_catalog.py`; it refuses to write if any language is missing a key, has mismatched format specifiers, or lacks required plural forms.

Strings added to Swift code but missing from `keys.json` silently stay English, and the build doesn't flag them. To find them, build the app, then compare the keys in the compiler's `*.stringsdata` files (under DerivedData's `Objects-normal/arm64/`) against `keys.json`.

`Localization/TRANSLATION_GUIDE.md` has the conventions: formal register in every language (de *Sie*, fr *vous*, ja です・ます, etc.), preserve `%@`/`%lld`/`%%` exactly, use positional specifiers (`%1$@`) when word order changes, and the domain glossary ("To date", "Planned", "Fully amortised"). The supported-language list is duplicated in `build_catalog.py` (`LANGS`), `LocalizationTests.expectedLanguages`, and `knownRegions` in the project file; keep them in sync.
