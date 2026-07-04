import SwiftUI

/// "Budget vs. actual" — the merged dashboard card that replaces the old
/// separate *planned budget* and *this month* cards.
///
/// For the selected period — this month or this year, toggled with the same
/// segmented חודש/שנה control the Analytics roadmap uses — it lays the plan
/// and reality side by side, one row per bucket (income / needs / wants):
/// the actual amount, the planned amount it's measured against, and a
/// progress bar that fills toward the plan and turns red on an overrun. A
/// banner at the top calls out any budget breach; `HomeView` additionally
/// raises a one-per-session alert (see there).
///
/// All the arithmetic lives in the pure `BudgetVsActual` value type — this
/// view only lays it out — so the same numbers can later feed an Analytics
/// station with no duplication.
struct BudgetVsActualCard: View {
    let report: BudgetVsActual
    /// The period the report covers — a scope (month/year) plus the anchor
    /// date picking *which* month or year. Owned by `HomeView` (which builds
    /// the matching report) so the card and the data can't drift apart. The
    /// segmented control toggles only the scope; the surrounding carousel
    /// steps the anchor.
    @Binding var period: AnalyticsPeriod
    /// Tapped via the header pencil. Parent owns the budget-editor sheet.
    let onEdit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped true on appear so the progress bars grow in from empty.
    @State private var revealed = false

    private var code: String { report.currencyCode }

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
            header

            // The period toggle only earns its place when there are numbers
            // to re-scope; the empty state stays a single quiet line.
            if report.hasAnyBudget || report.hasAnyActivity {
                scopePicker
            }

            if report.hasAnyBudget {
                comparison
            } else if report.hasAnyActivity {
                // Activity but nothing to compare against — show the actuals
                // and nudge the user toward setting a budget.
                actualsOnly
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .cardStyle()
        .onAppear { revealed = true }
    }

    // MARK: - Header

    /// Title + month label, with a pencil affordance opposite the label
    /// (always available, even in the empty state, so the user can add lines).
    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("התקציב מול הביצוע")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
            Text(periodLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .contentTransition(.numericText())
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(Theme.Spacing.xs)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("עריכת התקציב"))
        }
        .frame(maxWidth: .infinity)
    }

    /// The חודש/שנה toggle — the same control (and Hebrew labels) as the
    /// Analytics period selector, so the two screens speak one language.
    /// Switching scope keeps the anchor: viewing August and tapping שנה
    /// shows August's year.
    private var scopePicker: some View {
        Picker("תקופה", selection: $period.scope.animation(reduceMotion ? nil : .easeInOut(duration: 0.25))) {
            ForEach(AnalyticsPeriod.Scope.allCases) { scope in
                Text(scope.hebrewLabel).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 200)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - States

    private var emptyState: some View {
        Text("עדיין לא הוגדר תקציב.")
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Full plan-vs-reality layout.
    private var comparison: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
            if let summary = report.overrunSummary {
                OverrunBanner(summary: summary, code: code)
            }

            BudgetProgressRow(line: report.income, baseColor: Theme.Colors.income,
                              code: code, revealed: revealed, reduceMotion: reduceMotion)

            Divider().overlay(Theme.Colors.separator)

            BudgetProgressRow(line: report.needs, baseColor: Theme.Colors.expense,
                              code: code, revealed: revealed, reduceMotion: reduceMotion)
            BudgetProgressRow(line: report.wants, baseColor: Theme.Colors.wants,
                              code: code, revealed: revealed, reduceMotion: reduceMotion)

            Divider().overlay(Theme.Colors.separator)

            netRow

            scheduledExtrasNote
                .frame(maxWidth: .infinity, alignment: .leading)
            fxFootnote
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Fallback when there's spending but no budget: just the actual totals.
    private var actualsOnly: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
            amountRow(title: "הכנסות", amount: report.income.actual, color: Theme.Colors.income)
            amountRow(title: "הוצאות", amount: report.totalActualExpense, color: Theme.Colors.expense)
            netRow

            Label("הגדירו תקציב כדי לראות השוואה לתכנון", systemImage: "slider.horizontal.3")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            fxFootnote
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Rows

    private func amountRow(title: LocalizedStringKey, amount: Decimal, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(amount.formattedCurrency(code))
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }

    /// Actual net is the bottom line; the planned net rides underneath as a
    /// quiet reference so the user sees how the month tracked against plan.
    private var netRow: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
            HStack {
                Text("נטו בפועל")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(report.actualNet.formattedSignedCurrency(code))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(report.actualNet >= 0 ? Theme.Colors.income : Theme.Colors.expense)
                    .monospacedDigit()
            }
            if report.hasAnyBudget {
                HStack {
                    Text("מתוכנן")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(report.plannedNet.formattedSignedCurrency(code))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footnotes

    @ViewBuilder
    private var scheduledExtrasNote: some View {
        if report.hasScheduledExtras {
            Label(
                period.scope == .month ? "כולל הוצאות מתוכננות לחודש זה" : "כולל הוצאות מתוכננות לשנה זו",
                systemImage: "calendar.badge.clock"
            )
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private var fxFootnote: some View {
        if report.hasCrossCurrency, report.fxUnavailable {
            Text("שערי חליפין לא זמינים — מוצגים רק פריטים ב-\(code).")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// "יולי 2026" in month scope, "2026" in year scope — the carousel steps
    /// across periods, so the label must say *which* one, not just its kind.
    /// (Formatting lives in `AnalyticsPeriod.label`, shared with Analytics.)
    private var periodLabel: String {
        period.label()
    }
}

// MARK: - Month/year carousel

/// Wraps `BudgetVsActualCard` in an endless period pager: the selected
/// period's card sits centred, the *previous* period (June when viewing July)
/// peeks in from one screen edge and the *next* (August) from the other.
/// Two rounded stepper buttons under the card slide a neighbour into place
/// and step the bound `period` one unit back or forward — months in month
/// scope, years in year scope, with no bound in either direction (a budget
/// is a plan, so the future is exactly as browsable as the past). The
/// חודש/שנה toggle inside the card keeps choosing the unit, untouched by
/// the pager. (An earlier iteration drove this with a drag gesture; the
/// buttons replaced it because a fully scripted slide is reliably smooth.)
///
/// Layout contract with the caller: the carousel wants the **full screen
/// width** (bleed it past the dashboard's horizontal padding); the centre
/// card gives up `peekWidth + spacing` on each side so the neighbours are
/// clearly visible — a deliberately narrower card than its dashboard
/// siblings, which is what signals "this one slides". No clipping is needed
/// — the row simply extends offscreen — which also keeps the cards' soft
/// shadows intact.
struct BudgetCardCarousel: View {
    @Binding var period: AnalyticsPeriod
    /// Builds the report for a given period — the caller owns the data.
    let makeReport: (AnalyticsPeriod) -> BudgetVsActual
    let onEdit: () -> Void
    /// How much of each neighbouring card stays visible beside the centre
    /// one. Big enough that the carousel affordance is unmissable.
    var peekWidth: CGFloat = 32

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var containerWidth: CGFloat = 0
    /// The row's slide displacement in leading-relative points — animated
    /// to ±one step by the stepper buttons, zero whenever the pager is at
    /// rest.
    @State private var slideOffset: CGFloat = 0
    /// True while a slide animation runs, so a second tap can't interleave
    /// with the period swap at its end.
    @State private var isSettling = false

    /// Gap between the centre card and each peeking neighbour.
    private let spacing: CGFloat = Theme.Spacing.sm

    /// Centre-card width: the container minus a visible `peekWidth` slice
    /// and the gap on each side.
    private var cardWidth: CGFloat { max(0, containerWidth - 2 * (peekWidth + spacing)) }
    /// How far one full page turn travels.
    private var step: CGFloat { cardWidth + spacing }

    var body: some View {
        // Five pages (two back … two forward) so that at any point of a
        // one-step slide both peeks are filled — with only three pages the
        // slot behind the incoming card would go empty mid-animation and
        // the endless-pager illusion would break.
        let calendar = Calendar.current
        let previous = period.previous(calendar)
        let next = period.next(calendar)
        // HStack order is earlier → later; under the app's RTL layout that
        // puts the past on the visual right and the future on the visual
        // left, so dragging right rolls forward in time (July → August).
        let pages = [previous.previous(calendar), previous, period, next, next.next(calendar)]
        VStack(spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(pages.indices, id: \.self) { slot in
                    pageCard(pages[slot], slot: slot)
                }
            }
            .offset(x: slideOffset)
            // Centre the over-wide row inside the measured container: the
            // frame is narrower than the HStack, so the default centre
            // alignment holds the middle card in the middle of the screen.
            .frame(width: containerWidth > 0 ? containerWidth : nil)
            .frame(maxWidth: .infinity)

            stepControls
                // Align the steppers with the centre card's edges.
                .frame(width: cardWidth > 0 ? cardWidth : nil)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            containerWidth = width
        }
    }

    /// The two rounded stepper buttons under the card. HStack order is
    /// earlier → later, matching the pages row above: under RTL the
    /// previous-period button lands on the visual right (where the past
    /// peeks) and the next-period button on the visual left. The chevrons
    /// auto-mirror, so each one points at the card it will bring in.
    private var stepControls: some View {
        HStack(spacing: Theme.Spacing.sm) {
            stepButton(systemImage: "chevron.backward", label: "התקופה הקודמת") {
                settle(toward: 1)
            }
            stepButton(systemImage: "chevron.forward", label: "התקופה הבאה") {
                settle(toward: -1)
            }
        }
    }

    private func stepButton(
        systemImage: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(Theme.Colors.accent.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .stroke(Theme.Colors.accent.opacity(0.25), lineWidth: 1)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isSettling)
        .accessibilityLabel(Text(label))
    }

    /// One page of the roulette. Scale and opacity are *continuous functions
    /// of the card's live position* — full size/opacity at the centre,
    /// easing down to 0.94 / 0.65 a full slot away — rather than fixed
    /// per-slot styles. That way they interpolate in step with the slide,
    /// and by the time a neighbour reaches the centre it already looks
    /// exactly like the centre card, so the post-slide state swap changes
    /// no pixels.
    private func pageCard(_ pagePeriod: AnalyticsPeriod, slot: Int) -> some View {
        // Leading-relative position of this slot's centre, in card-steps
        // away from the container centre (0 = centred, ±1 = peek slots).
        let travel = step > 0 ? (CGFloat(slot - 2) * step + slideOffset) / step : 0
        let distance = min(abs(travel), 1)
        let isCenter = slot == 2
        return BudgetVsActualCard(
            report: makeReport(pagePeriod),
            period: isCenter ? $period : .constant(pagePeriod),
            onEdit: onEdit
        )
            .frame(width: cardWidth)
            .scaleEffect(1 - 0.06 * distance, anchor: .top)
            .opacity(1 - 0.35 * distance)
            // Only the resting centre card is interactive / visible to
            // VoiceOver; the stepper buttons below are the (fully
            // accessible) way to move between periods.
            .allowsHitTesting(isCenter)
            .accessibilityHidden(!isCenter)
    }

    /// Slide one page in from the given side (±1 in leading-relative space:
    /// −1 brings in the *later* neighbour, +1 the earlier one), then step
    /// the period. The incoming card already shows its period — and, via
    /// `pageCard`'s position-driven styling, already looks like the centre
    /// card — so stepping `period` and zeroing the offset in the same
    /// non-animated frame leaves the pixels exactly where they landed.
    private func settle(toward direction: CGFloat) {
        guard !isSettling else { return }
        let landing = direction < 0 ? period.next() : period.previous()
        if reduceMotion {
            period = landing
            return
        }
        isSettling = true
        withAnimation(.smooth(duration: 0.45), completionCriteria: .removed) {
            slideOffset = direction * step
        } completion: {
            period = landing
            slideOffset = 0
            isSettling = false
        }
    }
}

// MARK: - Progress row

/// One bucket's plan-vs-reality line: a coloured dot + label, the actual
/// amount measured against the planned one, and a progress bar that fills
/// toward the plan (and goes red on an overrun or un-budgeted spend).
private struct BudgetProgressRow: View {
    let line: BudgetLine
    /// The bucket's identity colour when on budget; an overrun overrides it.
    let baseColor: Color
    let code: String
    let revealed: Bool
    let reduceMotion: Bool

    /// Overruns (and spending with no budget) read red, consistent with the
    /// banner — a single, unambiguous "over" signal across the card.
    private var barColor: Color {
        (line.isOverBudget || line.isUnbudgetedSpend) ? Theme.Colors.expense : baseColor
    }

    private var amountColor: Color {
        (line.isOverBudget || line.isUnbudgetedSpend) ? Theme.Colors.expense : Theme.Colors.textPrimary
    }

    /// Bar fill, clamped to the track: full when over (it can't show >100%),
    /// and full for un-budgeted spend so the red bar reads as "off-plan".
    private var fillFraction: Double {
        if let progress = line.progress { return min(max(progress, 0), 1) }
        return line.actual > 0 ? 1 : 0
    }

    private var percentText: String? {
        guard let progress = line.progress else { return nil }
        return progress.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            HStack {
                Circle().fill(baseColor).frame(width: 8, height: 8)
                Text(LocalizedStringKey(line.bucket.hebrewLabel))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Theme.Spacing.sm)
                amounts
            }

            HStack(spacing: Theme.Spacing.sm) {
                BudgetProgressBar(fillFraction: fillFraction, color: barColor,
                                  revealed: revealed, reduceMotion: reduceMotion)
                if let percentText {
                    Text(percentText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(line.isOverBudget ? Theme.Colors.expense : Theme.Colors.textSecondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .leading)
                }
            }

            if line.isOverBudget {
                Text("חריגה של \(line.overAmount.formattedCurrency(code))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.expense)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    /// Actual amount, then the planned figure it's measured against — or a
    /// "not budgeted" note when there was no plan for this bucket.
    @ViewBuilder
    private var amounts: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(line.actual.formattedCurrency(code))
                .font(Theme.Typography.amount)
                .foregroundStyle(amountColor)
                .monospacedDigit()
            if line.planned > 0 {
                Text("מתוך \(line.planned.formattedCurrency(code))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
            } else if line.isUnbudgetedSpend {
                Text("לא תוקצב")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.expense)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var accessibilityLabel: String {
        let label = line.bucket.hebrewLabel
        let actual = line.actual.formattedCurrency(code)
        if line.planned > 0 {
            let planned = line.planned.formattedCurrency(code)
            let base = "\(label): בפועל \(actual), מתוך \(planned) מתוכננים"
            return line.isOverBudget ? "\(base), חריגה של \(line.overAmount.formattedCurrency(code))" : base
        }
        if line.isUnbudgetedSpend {
            return "\(label): בפועל \(actual), ללא תקציב"
        }
        return "\(label): \(actual)"
    }
}

/// A single-value progress bar that fills from the leading (RTL: right) edge
/// to `fillFraction`, growing in once the card appears (unless Reduce Motion
/// is on, where it's drawn at its final width immediately).
private struct BudgetProgressBar: View {
    let fillFraction: Double
    let color: Color
    let revealed: Bool
    let reduceMotion: Bool
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(revealed || reduceMotion ? fillFraction : 0))
            }
            .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85), value: revealed)
            // Also ease when the value itself changes — e.g. the card's
            // month/year scope toggle swapping in a different report.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: fillFraction)
        }
        .frame(height: height)
    }
}

// MARK: - Overrun banner

/// The persistent in-card warning shown whenever the month is over budget.
/// Honest about *what* is over: the total expense plan, or a specific
/// category when the total still has room.
private struct OverrunBanner: View {
    let summary: OverrunSummary
    let code: String

    private var message: String {
        if summary.isTotalOver {
            return "חריגה מהתקציב החודשי — \(summary.totalOverAmount.formattedCurrency(code))"
        }
        // No total breach, so name the category/categories that are over.
        let names = summary.lines.map(\.bucket.hebrewLabel).joined(separator: " ו")
        return "חריגה ב\(names)"
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(Theme.Typography.body)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.Colors.expense)
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(Theme.Colors.expense.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("On budget") {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        BudgetVsActualCard(
            report: BudgetVsActual(
                currencyCode: "ILS",
                income: BudgetLine(bucket: .income, planned: 9000, actual: 8200),
                needs: BudgetLine(bucket: .needs, planned: 4000, actual: 3100),
                wants: BudgetLine(bucket: .wants, planned: 2000, actual: 1100),
                hasAnyBudget: true,
                hasAnyActivity: true,
                fxUnavailable: false,
                hasCrossCurrency: false,
                hasScheduledExtras: false
            ),
            period: .constant(.current()),
            onEdit: {}
        )
        .padding(Theme.Spacing.lg)
    }
}

#Preview("Over budget") {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        BudgetVsActualCard(
            report: BudgetVsActual(
                currencyCode: "ILS",
                income: BudgetLine(bucket: .income, planned: 9000, actual: 9300),
                needs: BudgetLine(bucket: .needs, planned: 4000, actual: 4300),
                wants: BudgetLine(bucket: .wants, planned: 2000, actual: 1100),
                hasAnyBudget: true,
                hasAnyActivity: true,
                fxUnavailable: false,
                hasCrossCurrency: false,
                hasScheduledExtras: true
            ),
            period: .constant(.current()),
            onEdit: {}
        )
        .padding(Theme.Spacing.lg)
    }
}
