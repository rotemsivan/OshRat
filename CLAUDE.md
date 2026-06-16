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

Shared enums (String-backed, `Codable`):
- `TransactionKind`: `income`, `expense`
- `AccountType`: `current`, `savings`, `investment`, `other`
- `CategoryNature`: `need`, `want`, `neutral` (powers needs-vs-wants)
- `BudgetFrequencyKind`: `monthly`, `everyXWeeks` (amount roll-up cadence)
- `BudgetScheduleKind`: `recurringMonthly`, `recurringYearly`, `oneTime` (which months a budget line lands in)

Models:
- **UserProfile** — name, profession, free-text goals, preferred currency code, createdAt. Holds the personal data from onboarding.
- **Account** — name, type (`AccountType`), balance (`Decimal`), currency code, lastUpdated, isFavorite; relationships to its transactions (nullify) and holdings (cascade). The manually managed balances.
- **Holding** — symbol, name, quantity, marketValue (`Decimal`), currency code, lastUpdated; belongs to an investment `Account`. A single manually-valued position (stock/ETF).
- **Category** — name (Hebrew label), kind (`TransactionKind`), nature (`CategoryNature`), colorHex, SF Symbol name; relationship to its transactions.
- **Transaction** — amount (`Decimal`), kind, date, title, note, currency code, optional balanceAfter; optional links to a Category and an Account. The income/expense log. (A "manual balance edit" marker title flags bookkeeping rows so totals can exclude them.)
- **BudgetItem** — optional Category, plannedAmount (`Decimal`), kind, currency code, frequency (`BudgetFrequencyKind`), and an optional **schedule** (`BudgetScheduleKind` + day/month/year, plus an optional month/year **end bound** for recurring lines — "until January 2028"). `plannedAmount(inMonth:year:)` attributes each line to the right month; `occurrenceDate(...)` resolves the calendar day and, for **income**, shifts it off Shabbat *and Israeli holidays* to the next business day by default via `businessDay(onOrAfter:)` + `IsraeliHolidays`. Feeds planned-vs-actual and the budget calendar (which tints Shabbat and holidays).
- **Goal** — title, targetAmount, savedAmount (`Decimal`), optional targetDate, note, currency code, isCompleted. Covers goals and future plans.
- **FXRateSnapshot** — base currency, rates map, fetchedAt. Cached daily exchange rates (see *FX rates* above).

Register all models in the app's `.modelContainer(for: [...])` at launch (`OshRatApp`).

## Features (build order)

MVP, roughly in this order (1–3 implemented; 4 not yet):
1. **Onboarding / setup wizard** — collect personal data → financial accounts (current, investment) → budget (planned income & expenses). Seed a default set of Hebrew income/expense categories on first launch.
2. **Dashboard** — a clean, minimal, friendly summary: net worth, this month's income vs expenses, budget progress (month-aware), goal progress.
3. **Transactions** — add / edit / delete income and expenses (and transfers) anytime, each with a category and account.
4. **Goals & future plans** — create and track savings goals. *(model exists; UI not built yet.)*

Also built since:
- **Analytics** (`Views/Analytics/`) — a vertical, gamified "roadmap" of stats (monthly/yearly, month-over-month comparison, spending by category, needs-vs-wants, records, assets). All number-crunching is in the testable `AnalyticsReport`; stations reveal on scroll.
- **Budget scheduling & calendar** (`Views/Budget/`) — scheduled budget lines (every month / every year / one-time) that flow into the correct month automatically, plus a month `BudgetCalendarView` to plan them. The shared `BudgetScheduleSection` is reused by the income and expense editors.

Later (not now): networked gamification — streaks, competing with friends. This will need a backend and is out of scope for the MVP. (The Analytics page's gamification is purely local.)

## Navigation

- `ContentView` routes by data: no `UserProfile` in SwiftData → `OnboardingFlowView`; otherwise `HomeView`. There's no "did the user onboard?" flag — the data is the source of truth.
- `HomeView` is the app shell. It owns the shared chrome — background, the floating glass `HomeBottomBar`, the FAB (new transaction), and the global sheets (new transaction, budget editor, account editor) — and switches between tab branches on a `@State selectedTab: HomeBottomBar.Tab`.
- `HomeBottomBar.Tab`: `home` (raised center button sitting in the notch), `transactions`, `analytics`, `calendar`. Side icons are `HomeBarButton` (brand accent when selected, secondary otherwise); the center is the raised `HomeCenterButton`. The bar is built on the iOS 26 `glassEffect` with a custom `NotchedBarShape`.
- The dashboard branch is a plain `ScrollView`; each other tab is wrapped in its **own** `NavigationStack` inside `HomeView`, so it gets its own large title + toolbar. Reserve bottom padding for the bar + popped home button on every scrolling screen.
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

## Current status

Onboarding, the dashboard (assets / budget / monthly cards), transactions (list, add, transfers), the Analytics roadmap, and the budget calendar with scheduled items are all implemented. Navigation is a custom glass bottom bar (`HomeBottomBar`) with Home / Transactions / Analytics / Calendar; `HomeView` switches between them and owns the shared chrome (bottom bar, FAB, sheets). Not yet built: the Goals UI, and the rat/mouse visual theme.
