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

- iOS only. Deployment target: iOS 17.0 or later (so we can use SwiftData).
- UI: SwiftUI.
- Persistence: SwiftData, local and on-device. No backend, no server, no network calls in the MVP — with **one explicit exception**: see *FX rates* below.
- Architecture: MVVM — SwiftUI views → view models → services → SwiftData models.
- Charts: Swift Charts (Apple's native framework).
- Language & layout: Hebrew, right-to-left. Use a String Catalog / localization for all user-facing text; never hard-code Hebrew strings inside views. Let SwiftUI mirror layouts for RTL automatically.
- Multi-currency: every account, transaction, and goal carries its own ISO currency code (e.g. `ILS`, `USD`). For now the dashboard groups and totals **per currency**; combined cross-currency conversion is a later enhancement.

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

Models:
- **UserProfile** — name, profession, free-text goals, preferred currency code, createdAt. Holds the personal data from onboarding.
- **Account** — name, type (`AccountType`), balance (`Decimal`), currency code, lastUpdated; relationship to its transactions (delete rule: nullify). The manually managed balances.
- **Category** — name (Hebrew label), kind (`TransactionKind`), colorHex, SF Symbol name; relationship to its transactions.
- **Transaction** — amount (`Decimal`), kind, date, note, currency code; optional links to a Category and an Account. The income/expense log.
- **BudgetItem** — optional Category, plannedAmount (`Decimal`), kind. The planned monthly income/expenses, used for planned-vs-actual.
- **Goal** — title, targetAmount, savedAmount (`Decimal`), optional targetDate, note, currency code, isCompleted. Covers goals and future plans.

Register all models in the app's `.modelContainer(for: [...])` at launch.

## Features (build order)

MVP, roughly in this order:
1. **Onboarding / setup wizard** — collect personal data → financial accounts (current, investment) → budget (planned income & expenses). Seed a default set of Hebrew income/expense categories on first launch.
2. **Dashboard** — a clean, minimal, friendly summary: net worth (per currency), this month's income vs expenses, budget progress, goal progress. Use Swift Charts.
3. **Transactions** — add / edit / delete income and expenses anytime, each with a category and account.
4. **Goals & future plans** — create and track savings goals.

Later (not now): gamification — goals, streaks, competing with friends. This will need a backend and is out of scope for the MVP.

## Conventions

- Group code as: `Models/`, `ViewModels/`, `Views/` (with a subfolder per feature), `Services/`, `Resources/`.
- One type per file; the file name matches the type.
- Keep views small; push logic into view models and services.
- Comment the *why*, not the obvious *what*.
- When you add a dependency or make a structural choice, say so and explain why.

## Current status

Project just created in Xcode: empty SwiftUI app, Storage = None (SwiftData will be added manually so the developer sees how it is wired). Next step: add the SwiftData models and set up the `ModelContainer`.
