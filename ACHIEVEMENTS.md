# OshRat — XP rebalance + achievements (phase 2)

The detailed build plan for **phase 2** of `GAMIFICATION.md`. Drafted
2026-09-23.

**Status (2026-09-23): §0–§6 and §9 are implemented; the shelf (§7's
`AchievementsShelf`, §10) is not** — patches unlock and pay XP but nothing
draws them yet. Open decisions were resolved as recommended: retroactive
patches *and* XP with a queued level-up toast (§5a), the 600 early XP kept
as-is (§3), and the goal patches shipped as locked slots
(`Achievement.isReachable == false`) until the Goals UI exists. Goal XP
sources (§2) exist as `XPReason` cases and constants but have no entry point
yet. Two deliberate deviations, both tightening an anti-farm guard:
- **Budget "untouched"** checks the latest edit to *any* line (plus
  deletions), not only lines that apply to the month: re-scheduling a line
  away from a month changes that month's plan while no longer "applying".
- **`ladder-10`** counts months of each rung's `DepositTranche.createdAt`
  (entry time), not `startDate`, which comes from the transfer's user-chosen
  date — §4's doctrine says a `date`-based guard is worthless.

`Goal` also gained optional `createdAt` / `completedAt`, which `goal-done`
needs and which the Goals UI must set.

Read `GAMIFICATION.md` (the plan of record for the whole system) and
CLAUDE.md's *Gamification* section first — this document assumes phase 1,
the XP core, is built and unchanged, and it revises some of its numbers.

---

## 0. Blockers — two model fields must exist first

Neither exists today, and most of the anti-farming rules below are
unenforceable without them. **Do these first.**

### 0.1 `Transaction.createdAt`

```swift
/// When the row was actually written, as distinct from `date`, which is
/// when the money moved and which the user picks freely.
///
/// Every anti-farming guard keys on this. A guard built on `date` is
/// worthless: a user can enter 100 rows in one sitting and date them
/// across a year, satisfying any "spread over N days" rule instantly.
/// `createdAt` is not settable from the UI, so spreading entry over real
/// days requires actually using the app over real days.
var createdAt: Date?
```

Optional, not defaulted — `nil` marks rows that predate the field.
CloudKit-safe (optional, no unique constraint). Set it in every insert
path: `NewTransactionSheet`, the transfer path, `AccountDraft.apply`'s
manual-balance-edit marker, `DepositPayoutService`, `DemoDataService`.

Legacy rows (`nil`): count toward *totals* but contribute no distinct day
to a spread guard. Rationale: we cannot prove when they were entered, and
the honest user loses little because spread thresholds are low relative to
a real history.

### 0.2 `BudgetItem.lastEditedAt`

```swift
/// When this line was last created or changed. The budget achievements
/// require the month's budget to have been settled *before* the month
/// began — otherwise "stay under budget" is won by raising the budget on
/// the 28th.
var lastEditedAt: Date?
```

Stamp it on create and on every mutation (the income/expense editors and
`BudgetEditorSheet`). Deleting a line also counts as an edit for the month
it is deleted in — track via `UserProgress.budgetLastTouchedAt` (below),
since a deleted row cannot carry a timestamp.

### 0.3 `UserProgress` additions

```swift
var unlockedAchievements: [String] = []   // achievement ids, the patch ledger
var achievementsEpoch: Date?              // first launch after this ships
var budgetLastTouchedAt: Date?            // covers budget *deletions*
```

`achievementsEpoch` is set once, on first evaluation. **Budget achievements
never evaluate a month that starts before it** — we genuinely cannot verify
the no-edit rule for history, and inventing credit would be dishonest.
Everything else evaluates retroactively (see §5).

---

## 1. Curve rebalance (`Models/XPRules.swift`)

Current curve reaches level 99 at 247,450 XP — roughly 23 years at the
30/day cap. Almost every user lives in levels 2-6. Fix is a **plateau**,
not a steeper slope.

```swift
static let baseLevelCost    = 80     // was 100
static let levelCostStep    = 30     // was 50
static let levelCostCeiling = 500    // new
static let maxLevel         = 99     // unchanged

static func xpToAdvance(from level: Int) -> Int {
    guard level >= 1, level < maxLevel else { return 0 }
    return min(baseLevelCost + levelCostStep * (level - 1), levelCostCeiling)
}
```

The ceiling is reached at level 15 (`80 + 30×14 = 500`), so levels 1-14
ramp and 15+ are flat.

`totalXP(toReach:)` becomes piecewise — still closed-form, no loop:

```swift
static func totalXP(toReach level: Int) -> Int {
    guard level > 1 else { return 0 }
    let steps     = min(level, maxLevel) - 1
    let rampSteps = min(steps, rampLength)            // rampLength == 14
    let flatSteps = max(0, steps - rampLength)
    return rampSteps * baseLevelCost
         + levelCostStep * rampSteps * (rampSteps - 1) / 2
         + flatSteps * levelCostCeiling
}
```

Derive `rampLength` rather than hard-coding 14, so retuning any constant
stays a one-line change:

```swift
static var rampLength: Int {
    max(0, (levelCostCeiling - baseLevelCost + levelCostStep - 1) / levelCostStep)
}
```

Resulting pacing (at a realistic ~20 XP/day from logging alone):

| Reach | Old | New   | Time    |
|-------|-----|-------|---------|
| 2     | 100 | 80    | day 1   |
| 5     | 700 | 500   | ~1 mo   |
| 10    | 2700| 1,800 | ~3 mo   |
| 20    |10450| 6,350 | ~11 mo  |
| 50    |71050|21,350 | ~3 yr   |
| 99    |247450|45,850| ~6 yr   |

Onboarding's 90 XP now clears level 2 outright, so the wizard ends with a
level-up toast on first dashboard appearance. Verify that reads well.

---

## 2. New XP sources

Append to `XPReason` — **never rename existing cases**, their raw values
are persisted.

| Case                   | XP  | Guard                                  |
|------------------------|-----|----------------------------------------|
| `.goalContribution`    | 5   | shared daily cap                       |
| `.goalCompleted`       | 100 | keyed `goal-<persistentID>`            |
| `.budgetMonthMet`      | 60  | keyed `budget-YYYY-MM`                 |
| `.achievementUnlocked` | var | membership in `unlockedAchievements`   |

`dailyUsageCap` stays **30**. It rarely binds (3 transactions + a balance
fix is 18); raising it would only help farmers.

Goal cases need the Goals UI, which does not exist — see §6.

---

## 3. Achievement tiers

Tier drives the patch's look **and** its XP.

| Tier | Hebrew | XP  |
|------|--------|-----|
| bronze | ארד  | 100 |
| silver | כסף  | 200 |
| gold   | זהב  | 300 |

**Streak achievements pay 0.** `XPRules.streakMilestones` already pays
50/150/500 for exactly those events; the patch is the reward. Paying twice
for one act would be a bug.

Catalogue total: **3,400 XP** (11 bronze + 7 silver + 3 gold, streaks at 0).

⚠ **Balance note.** Six achievements are reachable in the first month or
two (`first-deposit`, `first-attachment`, `first-transfer`,
`multi-currency`, `balance-check-10`, `categorised-50`) = 600 XP, which
lands a new user near level 6 quickly. Intentional under "front-load early
wins", but check it does not trivialise the early curve; if it does, demote
some to a `starter` tier at 50.

---

## 4. Anti-farming doctrine

Everything in this app is hand-entered, so farming cannot be *prevented* —
only made **more effort than the honest path**. Four mechanisms, applied
per entry in §6:

1. **Distinctness** — count distinct transactions / accounts / days, never
   raw rows. (25 attachments on one transaction must not count.)
2. **Entry-time spread** — require N distinct `createdAt` days. This is
   what §0.1 exists for.
3. **Substance floors** — a qualifying month needs a minimum number of
   real transactions, so an empty month cannot trivially "stay under
   budget" or "run a surplus".
4. **Pre-commitment** — the budget must be settled before the month it is
   judged on (§0.2); a goal must exist a while before completing counts.

Reward **qualitative** behaviour: not "net worth is large" (a number the
user types) but "the ledger shows income exceeding expenses, month after
month" (which takes a year of real logging to fake convincingly).

---

## 5. Retroactive unlocking

Evaluate from **facts, not from the XP ledger** — check
`longestStreak >= 7`, not whether key `streak-7` is in `awardedKeys`. This
decouples patches from XP and gives existing users credit for what they
have already done.

Consequence: on first launch after this ships, a long-running user unlocks
several patches at once. The demo `saver` scenario (23-day streak, hundreds
of rows) is the test case.

**Decision needed** — pick one:
- (a) Grant patches *and* XP retroactively. Needs the level-up toast to
      queue rather than show only the latest, or several level-ups collapse
      into one.
- (b) Grant patches retroactively, suppress their XP. Simpler, no toast
      work, but the user "loses" earned XP.

Recommendation: **(a)**, with a queued toast — it is a genuinely good first
moment. Budget achievements are exempt either way (§0.3).

---

## 6. The catalogue

24 entries. `id` is persisted — **never rename**. Hebrew strings are final
text; add them to `Localizable.xcstrings` with plurals where a count
appears (see CLAUDE.md — an empty catalog entry renders `1 ימים`).

### התמדה — consistency

| id | Hebrew | Criterion | Tier | XP |
|----|--------|-----------|------|-----|
| `streak-7`   | שבוע רצוף | `longestStreak >= 7` | ארד | 0 |
| `streak-30`  | חודש רצוף | `longestStreak >= 30` | כסף | 0 |
| `streak-100` | מאה ימים | `longestStreak >= 100` | זהב | 0 |
| `log-100`  | מאה תנועות | 100 live non-transfer rows, entered on ≥ 30 distinct `createdAt` days | ארד | 100 |
| `log-500`  | חמש מאות תנועות | 500 rows, ≥ 90 distinct days | כסף | 200 |
| `log-1000` | אלף תנועות | 1,000 rows, ≥ 180 distinct days | זהב | 300 |

The day floors are the anti-bulk-entry guard: 1,000 rows over 180 days is
a real history; 1,000 rows in an afternoon is not.

### בקרה — budget discipline

All four require the month to be **closed** (we are past its last day) and
the budget **untouched during it**:

```
monthQualifies(M) =
     M.start >= achievementsEpoch
  && every BudgetItem applying to M has lastEditedAt < M.start
  && (budgetLastTouchedAt ?? .distantPast) < M.start
  && M has >= 15 live non-transfer transactions
```

| id | Hebrew | Criterion | Tier | XP |
|----|--------|-----------|------|-----|
| `under-budget-1`  | חודש בתוך התקציב | 1 qualifying month under budget | ארד | 100 |
| `under-budget-3`  | שלושה חודשים ברצף | 3 **consecutive** | כסף | 200 |
| `under-budget-12` | שנה של משמעת | 12 **consecutive** | זהב | 300 |
| `wants-under-30`  | רצונות מתחת ל-30% | a qualifying month where `.want` spend < 30% of total | ארד | 100 |

Reuse `BudgetVsActual` for the under/over verdict — do not reimplement it.

### צמיחה — growth  (replaces the old net-worth tiers)

Net worth is a number the user types, so rewarding its size rewards typing.
Reward the *ledger* instead: income genuinely exceeding expenses, repeatedly.

A month counts as a surplus month when, excluding transfers and
manual-balance-edit markers, income > expenses **and** the month has ≥ 10
live transactions entered on ≥ 8 distinct `createdAt` days.

| id | Hebrew | Criterion | Tier | XP |
|----|--------|-----------|------|-----|
| `surplus-3`  | שלושה חודשים בעודף | 3 consecutive surplus months | ארד | 100 |
| `surplus-6`  | חצי שנה בעודף | 6 consecutive | כסף | 200 |
| `surplus-12` | שנה בעודף | 12 consecutive | זהב | 300 |

### חיסכון — saving

| id | Hebrew | Criterion | Tier | XP |
|----|--------|-----------|------|-----|
| `first-deposit`   | הפיקדון הראשון | a `.savings` account with a rate **and** a maturity date **and** balance > 0 — a real deposit, not an empty shell | ארד | 100 |
| `deposit-matured` | פיקדון עד הסוף | a deposit with `payoutCompletedAt != nil`; inherently time-gated | כסף | 200 |
| `ladder-10`       | סולם של עשר | one replenishable deposit with ≥ 10 live tranches whose `startDate`s span ≥ 5 distinct months | כסף | 200 |
| `first-goal`      | היעד הראשון | a goal exists with `targetAmount > 0` | ארד | 100 |
| `goal-done`       | יעד הושג | a goal completed **≥ 30 days after it was created** — blocks create-and-complete farming | כסף | 200 |

`first-goal` / `goal-done` need the Goals UI (§8).

### סדר — hygiene

| id | Hebrew | Criterion | Tier | XP |
|----|--------|-----------|------|-----|
| `categorised-50`    | הכול מסודר | 50 live rows with a category, on ≥ 20 distinct `createdAt` days | ארד | 100 |
| `first-attachment`  | קבלה ראשונה | any attachment | ארד | 100 |
| `attachments-25`    | תיק מסמכים | attachments on **25 distinct transactions**, across ≥ 10 distinct `createdAt` days | כסף | 200 |
| `balance-check-10`  | יתרות מעודכנות | 10 manual balance edits on distinct **(account, calendar day)** pairs — at most one per account per day | ארד | 100 |
| `first-transfer`    | העברה ראשונה | any live transfer | ארד | 100 |
| `multi-currency`    | שני מטבעות | ≥ 2 currencies among live accounts, **each with ≥ 1 live transaction** — not a decoy account | ארד | 100 |

---

## 7. Code structure

New files (all need pbxproj registration by hand — see CLAUDE.md's
"Adding files" gotcha; a file the **test targets** also need gets one
`PBXBuildFile` per target, and object IDs must be unique file-wide):

| File | Role | In test target? |
|------|------|-----------------|
| `Models/Achievement.swift` | catalogue as code constants, `AchievementTier` | yes |
| `Models/AchievementEvaluator.swift` | pure: snapshot in → satisfied ids out | yes |
| `Views/Gamification/AchievementsShelf.swift` | replaces the placeholder | no |
| `OshRatTests/AchievementEvaluatorTests.swift` | — | — |

Catalogue lives in **code, not the database** — GAMIFICATION.md is explicit.
Persist only `unlockedAchievements`.

`AchievementEvaluator` takes a plain-value snapshot and touches no
SwiftData, exactly like `AnalyticsReport`:

```swift
struct AchievementSnapshot {
    let longestStreak: Int
    let transactionEntryDays: Set<DateComponents>   // distinct createdAt days
    let liveTransactionCount: Int
    let categorisedCount: Int
    let categorisedEntryDays: Int
    let attachedTransactionCount: Int
    let attachmentEntryDays: Int
    let balanceEditAccountDays: Int
    let hasTransfer: Bool
    let activeCurrencies: Int
    let qualifyingBudgetMonths: [YearMonth]     // already filtered by §6
    let consecutiveUnderBudget: Int
    let consecutiveSurplus: Int
    let wantsUnder30Month: Bool
    let deposits: DepositFacts
    let goals: GoalFacts
}

enum AchievementEvaluator {
    static func satisfied(_ s: AchievementSnapshot) -> Set<String>
}
```

`ProgressService.evaluateAchievements(in:now:)` builds the snapshot, diffs
against `unlockedAchievements`, appends new ids and awards their XP.
Array membership **is** the idempotency guard — no separate key ledger.

Call it from the existing write points (transaction logged, balance
updated, onboarding committed) plus once on dashboard appear, which is what
catches month-boundary achievements. It is a pure read plus a rare write,
so cost is fine; if the ledger scan gets heavy, gate the month-based
branches behind "the month changed since last evaluation".

---

## 8. Sequencing

1. §0 model fields + stamping every insert/mutation path. Ship alone;
   verify the store migrates (optional fields, no unique constraints).
2. §1 curve + its `XPRulesTests` updates. Pure, no UI.
3. §3/§6 catalogue + `AchievementEvaluator` + tests. Still no UI.
4. `ProgressService.evaluateAchievements` + `unlockedAchievements`.
5. `AchievementsShelf` replacing the placeholder (§10).
6. §2 goal XP sources — **only after the Goals UI exists**. Until then
   `first-goal` / `goal-done` stay in the catalogue as permanently-locked
   slots, which is honest: they are visible, unearned, and clearly not yet
   reachable.

---

## 9. Tests

`AchievementEvaluator` is pure, so test it directly against fixed
snapshots. Cover specifically:

- each anti-farm guard **fails** when only the naive condition is met:
  25 attachments on **one** transaction → `attachments-25` NOT satisfied;
  1,000 rows on 1 entry day → `log-1000` NOT satisfied;
  a month whose budget was edited on the 15th → no budget achievement.
- `legacy rows` (`createdAt == nil`) count to totals but add no spread day.
- consecutive-month runs break correctly on a gap month.
- `goal-done` rejects a goal completed 29 days after creation.
- `XPRules`: ramp/plateau boundary at level 14→15, and
  `totalXP(toReach:)` agreeing with a naive loop over `xpToAdvance(from:)`
  for every level 1...99 (cheap, catches the piecewise algebra).

---

## 10. Fix carried over

`AchievementsGalleryPlaceholder` in `Views/Profile/ProfileView.swift` has a
live bug found by cloud review: its `ViewThatFits` offers two candidates of
**identical width** (the fallback wraps the same single-child `HStack` in a
`VStack`), so it never wraps and the slots overflow the card at large
Dynamic Type. The real shelf replaces this view — build it with a
`LazyVGrid` using `GridItem(.adaptive(minimum:))`, or chunk the ids into
rows explicitly. Do not carry the `ViewThatFits` pattern over.

---

## 11. Open decisions

1. **§5** — retroactive XP (a) with a queued toast, or (b) patches only.
   Recommend (a).
2. **§3 balance note** — whether 600 XP of early-reachable achievements
   trivialises levels 2-6.
3. Whether `first-goal` / `goal-done` ship as locked slots or are held back
   entirely until Goals exists.
