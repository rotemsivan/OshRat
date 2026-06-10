import SwiftUI

/// The welcome screen's hero: the rat mascot pops in, then hovers
/// gently above a soft ground shadow.
///
/// Two independent animations:
///   1. **Entrance** — a one-shot spring pop (scale + fade) when the
///      view first appears.
///   2. **Idle float** — once the pop settles, a slow ease-in-out bob
///      that repeats forever. The shadow shrinks and fades in
///      counterpoint, which is what sells the "hovering" read; without
///      it the rat just looks like it's sliding up and down.
///
/// With Reduce Motion on, the entrance becomes a plain fade and the
/// idle float never starts.
struct WelcomeMascotView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One-shot entrance flag; flipped in `onAppear` and never reset.
    @State private var hasEntered = false
    /// Drives the repeat-forever bob. Started from the entrance
    /// animation's `completion` so the pop fully lands first.
    @State private var isFloating = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image("rat-mascot-coin")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 280, maxHeight: 320)
                .offset(y: isFloating ? -10 : 0)

            Ellipse()
                .fill(Theme.Colors.graphite.opacity(0.18))
                .frame(width: 150, height: 14)
                .scaleEffect(isFloating ? 0.82 : 1)
                .opacity(isFloating ? 0.55 : 1)
        }
        // Reduce Motion swaps the scale-pop for an opacity-only fade.
        .scaleEffect(hasEntered || reduceMotion ? 1 : 0.6)
        .opacity(hasEntered ? 1 : 0)
        .accessibilityLabel(Text("עכבר עו״ש מחזיק מטבע זהב"))
        .onAppear(perform: enter)
    }

    private func enter() {
        withAnimation(
            reduceMotion
                ? .easeOut(duration: 0.4)
                : .spring(response: 0.55, dampingFraction: 0.68)
        ) {
            hasEntered = true
        } completion: {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        WelcomeMascotView()
    }
}
