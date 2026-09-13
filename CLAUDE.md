# עכבר עו״ש (OshRat)

> If you named the Xcode project something other than `OshRat`, update the name in this file to match it.

## What this app is

A personal finance app, in Hebrew, that helps one person track their money and feel in control of their financial state. There is intentionally **no connection to banks or investment providers** — the user enters and updates all balances and transactions manually. This is both a privacy choice and a simplicity choice.

This is also a **learning project**: the developer is new to iOS development. Prefer clear, idiomatic, well-commented Swift, and briefly explain non-obvious decisions as you go rather than only producing code.

## Names

- Project / module name (code, ASCII): `OshRat`
- Display name (what users see, Hebrew): עכבר עו״ש
- Theme (for a later design phase): rat / mouse themed. No design work yet.

## Platform & stack

- iOS only. Deployment target: **iOS 26** (project setting is 26.5). Uses SwiftData plus iOS 26 Liquid Glass APIs (e.g. `glassEffect` in `HomeBottomBar`).
- UI: SwiftUI.
- Persistence: SwiftData, local and on-device. No backend, no server, no network calls in the MVP — with **one explicit exception**: see *FX rates* below.
- Architecture: MVVM — SwiftUI views → view models → services → SwiftData models.
- Charts: Swift Charts (Apple's native framework).
- Language & layout: Hebrew, right-to-left. The app is **pinned to Hebrew on every device** (`CFBundleLocalizations = [he]` in `OshRat/Info.plist`, `developmentRegion = he`), so it always renders RTL regardless of the simulator/device system language. User-facing Hebrew is currently written inline as `Text("…")` literals; Swift treats these as `LocalizedStringKey`s and Xcode auto-extracts them into `OshRat/Localizable.xcstrings` (whose `sourceLanguage` is `he`, so the key *is* the final text — nothing to "translate"). Let SwiftUI mirror RTL automatically; for a `+`/`-` sign on an amount, wrap it in U+2066…U+2069 so the bidi-neutral sign stays on the visual left (see the summary cards).
- **Goal — finish the String Catalog migration:** make `Localizable.xcstrings` the source of truth for user-facing text, chiefly to get correct Hebrew **plurals** (1 / 2 / many differ, e.g. `%lld תנועות`) and to disambiguate / positionally reorder interpolated args. Migrating is safe and does **not** change the app's language: keys stay Hebrew and `CFBundleLocalizations = [he]` keeps it Hebrew + RTL. Do **not** add a second language (e.g. `en`) to the catalog or bundle localizations unless the app is genuinely going multilingual — that would let a non-Hebrew device flip the layout to LTR.
- Multi-currency: every account, holding, transaction, budget item, and goal carries its own ISO currency code (e.g. `ILS`, `USD`). The dashboard rolls everything into the user's **preferred currency** via cached FX rates (see below), falling back to per-currency / "FX unavailable" when rates are missing. Conversion goes through `CurrencyConverter`.

## FX rates (network exception)

The app pulls daily reference exchange rates from **Frankfurter.dev** (`https://api.frankfurter.dev/v1/latest`) so the dashboard can roll multi-currency totals into the user's preferred currency. This is the *only* network call the MVP makes.

Rules of the exception:
- **Public reference data only.** Frankfurter publishes ECB rates. No auth, no API key, no user identifiers in the request.
- **Cached aggressively.** Rates are stored in a `FXRateSnapshot` SwiftData row and refreshed at most once per 24h.
- **Graceful fallback.** If the fetch fails (or the cache is empty), the dashboard falls back to per-currency totals with a small "FX unavailable" note. Nothing in the rest of the app depends on a successful fetch.
- **Don't expand this exception** without updating this section. Anything that sends user data over the network — bank, brokerage, market-data, analytics, telemetry — needs a separate, deliberate decision.

## Money & data rules

- All monetary amounts use `Decimal`, never `Double` or `Float` (avoids rounding errors).
- Account balances are entered and updated **manually by the user** and are the source of truth for net worth. Transactions are a separate income/expense log that feeds the dashboard and budget — we do **not** auto-recompute balances from transactions in the MVP.
- Keep the data models **CloudKit-compatible** even though sync is off for now: every stored property must be optional or have a default value, and do not use unique constraints. This keeps the door open to enable iCloud sync later with almost no rework.

## Data models (SwiftData `@Model` classes)

Define these in a `Models/` group.

Shared enums (String-backed, `Codable`), all in `Models/SharedEnums.swift`:
- `TransactionKind`: `income`, `expense`
- `AccountType`: `current`, `digitalWallet`, `savings`, `investment`. Also carries the per-type `symbolName` (SF Symbol), `sortRank` (dashboard / analytics ordering) and `isLiquid` (the dashboard's נזיל / נכסים split) — use those rather than re-writing the switch in a view. Decodes unknown raw values to `.current`, so a removed case can't brick the whole store (as `.other` once did). **`.investment` is currently blocked in the UI** (see *Investments* below) but still a valid stored value.
- `CategoryNature`: `need`, `want`, `neutral` (powers needs-vs-wants)
- `RecurrenceUnit`: `day`, `week`, `month`, `year` — the current cadence model ("every N units"). Sub-monthly units average into *every* month; monthly/yearly land their full amount on the months they occur in.
- `BudgetFrequencyKind` / `BudgetScheduleKind` — **legacy**, superseded by `RecurrenceUnit` + a count. Still persisted so pre-existing `BudgetItem` rows migrate cleanly, and `BudgetScheduleKind` still distinguishes `oneTime` from recurring.

Models:
- **UserProfile** — name, profession, free-text goals, preferred currency code, createdAt. Holds the personal data from onboarding.
- **Account** — name, type (`AccountType`), balance (`Decimal`), currency code, lastUpdated, isFavorite; relationships to its transactions (nullify) and holdings (cascade). The manually managed balances. A `.savings` account is a **deposit (פיקדון)**: it also carries `interestRatePercent`, `depositStartDate`, `maturityDate`, `autoPayoutOnMaturity`, `payoutAccount` (a self-referencing nullify relationship, inverse `incomingDepositPayouts`) and `payoutCompletedAt`. All optional/defaulted, all ignored unless the type is `.savings`, and all-empty is a valid open-ended savings pot. `depositTerms` bridges them to `DepositTerms`; `isAwaitingPayout(asOf:)` is what the dashboard prompt keys on.
- **Holding** — symbol, name, quantity, marketValue (`Decimal`), currency code, lastUpdated; belongs to an investment `Account`. A single manually-valued position (stock/ETF).
- **Category** — name (Hebrew label), kind (`TransactionKind`), nature (`CategoryNature`), colorHex, SF Symbol name; relationship to its transactions.
- **Transaction** — amount (`Decimal`), kind, date, title, note, currency code, optional balanceAfter; optional links to a Category and an Account, plus a cascade `attachments` relationship. The income/expense log. (A "manual balance edit" marker title flags bookkeeping rows so totals can exclude them.)
- **TransactionAttachment** — filename, `@Attribute(.externalStorage)` data blob, typeIdentifier (UTI string), createdAt; belongs to a `Transaction` (cascade). A receipt/invoice the user attached — image or PDF — added from Camera/Photos/Files in the transaction sheet and viewed (via QuickLook) from the expandable transaction card. Camera needs `NSCameraUsageDescription` in `OshRat/Info.plist`.
- **BudgetItem** — optional Category, plannedAmount (`Decimal`), kind, currency code, frequency (`BudgetFrequencyKind`), and an optional **schedule** (`BudgetScheduleKind` + day/month/year, plus an optional month/year **end bound** for recurring lines — "until January 2028"). `plannedAmount(inMonth:year:)` attributes each line to the right month; `occurrenceDate(...)` resolves the calendar day and, for **income**, shifts it off Shabbat *and Israeli holidays* to the next business day by default via `businessDay(onOrAfter:)` + `IsraeliHolidays`. Feeds planned-vs-actual and the budget calendar (which tints Shabbat and holidays).
- **Goal** — title, targetAmount, savedAmount (`Decimal`), optional targetDate, note, currency code, isCompleted. Covers goals and future plans.
- **FXRateSnapshot** — base currency, rates map, fetchedAt. Cached daily exchange rates (see *FX rates* above).

Not a `@Model`, but part of the same layer:
- **DepositTerms** (`Models/DepositTerms.swift`) — the pure, unit-tested term maths behind a deposit: `isMatured`, `daysRemaining`, `progress`, `value(asOf:)`, `projectedValue`. **Simple annual interest** (`principal × (1 + rate × years)`, 365-day years), not compounding: the user can reproduce it on a calculator, and the payout prompt lets them overwrite it with the bank's real figure anyway. Accrual stops at maturity. Compiled into the test targets as well as the app — see the pbxproj gotcha below.

Register all models in the app's `.modelContainer(for: [...])` at launch (`OshRatApp`).

## Features (build order)

MVP, roughly in this order (1–3 implemented; 4 not yet):
1. **Onboarding / setup wizard** — collect personal data → financial accounts (current, investment) → budget (planned income & expenses). Seed a default set of Hebrew income/expense categories on first launch.
2. **Dashboard** — a clean, minimal, friendly summary: net worth, this month's income vs expenses, budget progress (month-aware), goal progress. The assets card splits its rows into **נזיל** (עו״ש + ארנק דיגיטלי) and **נכסים** (פיקדונות + השקעות) by `AccountType.isLiquid`, each with its own subtotal under the combined total. Rows are **capped at the first three** (a "הצג עוד" toggle at the card's bottom-left opens the rest) so the card can't push the budget card off-screen; collapsing hides *rows only* — each group header still subtotals every account in it, so the parts keep adding up to the hero total.
3. **Transactions** — add / edit / delete income and expenses (and transfers) anytime, each with a category and account.
4. **Goals & future plans** — create and track savings goals. *(model exists; UI not built yet.)*

**Investments — deliberately off.** `.investment` stays in the account-type picker (it's coming) but selecting it bounces back, with a "בפיתוח" note explaining why; a segmented `Picker` can't disable one segment, so the revert *is* the affordance. Accounts that are *already* investments still open and edit normally — `AccountEditorSheet.originalType` is what permits that. In the meantime securities are logged as ordinary transactions through two seeded categories, **קניית ני״ע** (expense) and **מכירת ני״ע** (income). Both are `.neutral`, which today means a purchase counts under **צרכים** in needs-vs-wants and the budget card — a known distortion, accepted until investment accounts are real.

Also built since:
- **Deposits** (`Models/DepositTerms.swift`, `Services/DepositPayoutService.swift`, `Views/Home/DepositMaturitySheet.swift`) — a savings account with a rate, a start date, a maturity date, a payout account and an auto/ask toggle. **Payout targets are `.current` accounts only** (`HomeView.payoutCandidates`) — a deposit matures into an עו״ש, not into another deposit or a wallet; the one exception is an account a deposit already points at, kept in the list so older data doesn't silently lose its target. On the maturity day `HomeView` settles it: deposits set to automatic (and with a live payout account it can reach) transfer on their own and raise a one-button confirmation; the rest raise `DepositMaturitySheet`, which pre-fills the projected value, lets the user correct it and pick a different target, and offers "לא עכשיו" (session-scoped — it asks again next launch). **The payout writes two rows**: the interest as income on the deposit (without it, transferring principal+interest would drag the deposit negative) and the move itself as a normal transfer, so it reverses and restores like any other row. `payoutCompletedAt` latches it closed; the account stays at zero with its terms intact.
- **Analytics** (`Views/Analytics/`) — a vertical, gamified "roadmap" of stats (monthly/yearly, month-over-month comparison, spending by category, needs-vs-wants, records, assets). All number-crunching is in the testable `AnalyticsReport`; stations reveal on scroll.
- **Budget scheduling & calendar** (`Views/Budget/`) — scheduled budget lines (every month / every year / one-time) that flow into the correct month automatically, plus a month `BudgetCalendarView` to plan them. The shared `BudgetScheduleSection` is reused by the income and expense editors.
- **Soft delete & recovery** (`Services/TrashService.swift`, `Views/RecentlyDeleted/`) — deleting an account or a transaction hides it rather than destroying it; `RecentlyDeletedView` restores or permanently deletes, and `HomeView` purges rows older than 30 days on appear.
- **Quick-add widget** (`OshRatWidget/`) — a static home-screen widget that deep-links `oshrat://new-transaction` straight into the new-transaction sheet.

Later (not now): networked gamification — streaks, competing with friends. This will need a backend and is out of scope for the MVP. (The Analytics page's gamification is purely local.)

## Navigation

- `ContentView` routes by data: no `UserProfile` in SwiftData → `OnboardingFlowView`; otherwise `HomeView`. There's no "did the user onboard?" flag — the data is the source of truth.
- `HomeView` is the app shell. It owns the shared chrome — background, the floating glass `HomeBottomBar`, the FAB (new transaction), and the global sheets (new transaction, budget editor, account editor) — and switches between tab branches on a `@State selectedTab: HomeBottomBar.Tab`.
- `HomeBottomBar.Tab`: `home` (raised center button sitting in the notch), `transactions`, `analytics`, `calendar`. Side icons are `HomeBarButton` (brand accent when selected, secondary otherwise); the center is the raised `HomeCenterButton`. The bar is built on the iOS 26 `glassEffect` with a custom `NotchedBarShape`.
- The dashboard branch is a plain `ScrollView`; each other tab is wrapped in its **own** `NavigationStack` inside `HomeView`, so it gets its own large title + toolbar. Reserve bottom padding for the bar + popped home button on every scrolling screen.
- The dashboard's budget card is a **horizontally paged `ScrollView`** (`BudgetCardCarousel`) — one card per period, swiped to move month-to-month or year-to-year. A nested scroll view on the perpendicular axis is the deliberate choice: it separates the axes *natively* (UIKit locks a pan to whichever direction it starts in), which a custom `DragGesture` cannot — an earlier drag-driven version fought the dashboard's vertical scroll. It bleeds full-width and restores the gutter as `contentMargins`, so pages match the width of the cards above. See the paged-`ScrollView` gotcha in Conventions before widening its window.
- **Widget entry point:** `HomeView` handles the `oshrat://new-transaction` URL from the quick-add widget by opening the new-transaction sheet.
- Feature-local sheets (income/expense editors, the schedule section, calendar add) are presented from within their own screens, not from `HomeView`.
- **To add a tab:** add a case to `HomeBottomBar.Tab`, a `HomeBarButton` in the bar's `HStack`, and a branch in `HomeView`'s `switch` — then register any new screen files in the pbxproj (see Conventions).

## Settings

There is **no Settings screen yet** — preferences are currently hardcoded to sensible defaults. Planned, in priority order:

- **Business-day shift for income (toggle, default on).** Recurring *income* is auto-placed on the next business day, skipping **Shabbat** (Israel works Sun–Fri) **and Israeli rest-day holidays** — a salary on the 1st shows on the next open day when the 1st is a Saturday, Yom Kippur, etc. Holidays come from `IsraeliHolidays` (computed offline from the Hebrew calendar). It returns an `IsraeliHoliday` with an `isRestDay` flag: only **rest-day** holidays (yom tov + Independence Day, which has a Fri/Sat/Mon observance shift) move a salary; working-day holidays (Hanukkah, Purim, Tu BiShvat, Lag BaOmer) are display-only. Implemented now in `BudgetItem.occurrenceDate(..., shiftIncomeToBusinessDay:)` + `BudgetItem.businessDay(onOrAfter:)`, currently forced on. **Task:** add a `shiftIncomeToBusinessDay` preference (store on `UserProfile`, default `true`), build the Settings toggle, and thread it through to `occurrenceDate` from the calendar/dashboard so the user can disable it.
- Later: preferred-currency change, manual FX refresh, and a (currently DEBUG-only) data reset.

## Conventions

- Group code as: `Models/`, `ViewModels/`, `Views/` (with a subfolder per feature), `Services/`, `DesignSystem/`. Visual constants (colours, spacing, typography, `.cardStyle()`) live in `DesignSystem/Theme.swift` — use them, don't hard-code.
- One type per file *ideally*, but tightly-coupled private helper views/types are co-located with their feature file (matches the existing code).
- Keep views small; push logic into view models / testable value types (e.g. `AnalyticsReport`, `BudgetSchedule`) and services.
- Comment the *why*, not the obvious *what*. When you add a dependency or make a structural choice, say so and explain why.
- **Adding files (gotcha):** only the `OshRat/` folder is a synchronized Xcode group. New files under `Models/`, `Views/`, `ViewModels/`, `Services/`, `DesignSystem/` are **not** auto-detected — register each in `OshRat.xcodeproj/project.pbxproj` by hand (a `PBXBuildFile`, a `PBXFileReference`, an entry in the parent group's `children`, and an entry in the target's `PBXSourcesBuildPhase`). Validate with `plutil -lint OshRat.xcodeproj/project.pbxproj`.
- **Build check:** `xcodebuild build -scheme OshRat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- **Paged `ScrollView` gotcha:** every mounted page's body runs on each render, so per-page work multiplies by the page count — `HomeView.report(for:)` rebuilds a `BudgetVsActual` from the entire ledger, and `.defaultScrollAnchor(.center)` measures the whole row, which defeats `LazyHStack` — so the row is a plain `HStack` (a lazy one sized itself from the pages built so far and clipped the tallest card's bottom off). A ±240-period window meant ~481 ledger scans per render and a pinned main thread on a real device. Keep the window small and re-base it around the visible page instead of mounting a wide range.
- **Verifying UI on the simulator is limited:** `simctl` boot/install/launch/screenshot work, but AppleScript automation is blocked, so gestures can't be driven, and an empty store routes to onboarding rather than the dashboard. A clean build is not evidence that a gesture or scroll change behaves — say so, and test interaction on a device.

## Current status

Onboarding, the dashboard (assets + budget-vs-actual cards), transactions (list, add, edit, transfers), the Analytics roadmap, and the budget calendar with scheduled items are all implemented. The dashboard's budget card **swipes between periods** — month or year, past or future — via `BudgetCardCarousel`. Transaction rows in the list **expand inline** on tap into an insights card (recurrence/cadence, amount-vs-average, last-seen, day pattern, similar past rows — all computed in the pure `TransactionInsights` value type) that also surfaces the note and any **file attachments** (receipts/invoices added from Camera/Photos/Files, viewed via QuickLook; in the sheet the add button stays pinned beside the strip and newest files show first). Deleting an account or transaction is a **soft delete** recoverable from `RecentlyDeletedView`, and a home-screen **quick-add widget** deep-links into the new-transaction sheet. Navigation is a custom glass bottom bar (`HomeBottomBar`) with Home / Transactions / Analytics / Calendar; `HomeView` switches between them and owns the shared chrome (bottom bar, FAB, sheets). Savings accounts are **deposits**: rate, dates, payout account and an auto/ask toggle, with a maturity prompt that pays out as a real transfer. The assets card is split into נזיל and נכסים, and shows three account rows before "הצג עוד". Investment accounts are **blocked** pending a proper build — קניית ני״ע / מכירת ני״ע categories stand in. Not yet built: the Goals UI, the Settings screen, the investments feature, and the rat/mouse visual theme.

## Planned / later (not in the current build)

1. CloudKit sync (multi-Apple-device). For when multi-device is wanted — needs the paid Apple Developer Program:

- Switch the container to ModelConfiguration(schema:, cloudKitDatabase: .automatic).
- Xcode capabilities: iCloud → CloudKit (container iCloud.com.rotem.OshRat) and Background Modes → Remote notifications.
- Use the CloudSyncStatus helper to show a quiet "local-only" banner when iCloud is unavailable — never block the app; it must keep working offline / signed out.
- Fix first-launch category seeding to run once per iCloud account using NSUbiquitousKeyValueStore, to avoid duplicate default categories across devices.
- If the container fails to build with a CloudKit relationship error, make the to-many transactions relationships on Account and Category optional ([Transaction]?).
- Before any App Store release, deploy the CloudKit schema from Development to Production in the CloudKit Console.

2. Gamification / XP. Local-only engine: a UserProgress model (XP, level, streaks) + an Achievement catalog + a ProgressService called from the existing data-write points; wire the mascot poses to reward moments. No backend for the solo version. Full plan in GAMIFICATION.md (XP rules, levels, achievements, and the layered mascot-customization system).
3. App Store launch. Enroll in the paid program; prepare App Privacy details + a privacy-policy URL; Hebrew/RTL screenshots; TestFlight; then submit. Keep manual-entry only (no bank APIs) for v1. Optional later: a small "Pro" tier via StoreKit (sync, advanced insights, export) — worth gating premium features behind a simple isPro check early so adding purchases later is easy.
