import SwiftUI

/// Step 1 of the setup wizard: collect who the user is and how they
/// think about money. None of this leaves the device.
///
/// `@Bindable` is the @Observable-era replacement for `@ObservedObject` +
/// `$` projection — it lets us write `$viewModel.name` for two-way
/// bindings into the form fields without owning the view model here.
struct PersonalDetailsStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    /// A small, hard-coded set of ISO currency codes for the MVP. We can
    /// swap this for `Locale.commonISOCurrencyCodes` later if we want
    /// the long list, but a short menu is friendlier for first-time setup.
    private let supportedCurrencies: [String] = ["ILS", "USD", "EUR", "GBP"]

    var body: some View {
        Form {
            Section {
                TextField("שם", text: $viewModel.name)
                    .textContentType(.name)
                    .autocapitalization(.words)
                    .submitLabel(.next)
                
                TextField("מקצוע", text: $viewModel.profession)
                    .textContentType(.jobTitle)
                    //.frame(maxWidth: .infinity, alignment: .leading)
                    .submitLabel(.next)

            } header: {
                Text("פרטים אישיים")
            } footer: {
                Text("השם יופיע במסך הבית. אפשר לערוך הכול מאוחר יותר.")
            }

            Section {
                // axis: .vertical turns this into a multi-line text editor
                // that grows with the content — better than a single line
                // for free-form aspirations.
                TextField(
                    "למשל: לחסוך לדירה, להחזיר הלוואה, נסיעה גדולה…",
                    text: $viewModel.goalsText,
                    axis: .vertical
                )
                .lineLimit(3...6)
            } header: {
                Text("המטרות שלי")
            } footer: {
                Text("טקסט חופשי. בהמשך נוכל לפרק את זה ליעדים מדידים.")
            }

            Section {
                Picker("מטבע מועדף", selection: $viewModel.preferredCurrencyCode) {
                    ForEach(supportedCurrencies, id: \.self) { code in
                        Text(currencyLabel(for: code)).tag(code)
                    }
                }
            } footer: {
                Text("זה המטבע שייבחר כברירת מחדל לחשבונות ולעסקאות חדשים.")
            }
        }
        // Let the form blend with the brand background instead of using
        // the default system grouped fill. Inputs still read as inputs
        // thanks to per-section row backgrounds.
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .font(Theme.Typography.body)
    }

    /// Human-friendly label for the currency picker — currency code first
    /// (what the data layer stores), followed by the localised name.
    private func currencyLabel(for code: String) -> String {
        let locale = Locale.current
        let name = locale.localizedString(forCurrencyCode: code) ?? code
        return "\(code) — \(name)"
    }
}

#Preview {
    PersonalDetailsStepView(viewModel: OnboardingViewModel())
}
