import SwiftUI

struct OnboardingHeading: View {
    let title: String
    let detail: String
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 38
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: titleSize, weight: .semibold))
                .tracking(-1.2).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(.body).foregroundStyle(.secondary)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingPrivacyText: View {
    var body: some View {
        Text("No account. No cloud storage. No analytics.")
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.labelStyle(.titleOnly).font(.body.weight(.semibold)).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 56).padding(.horizontal, WhimSpacing.page).padding(.vertical, 4)
            .foregroundStyle(.white).whimGlass(in: Capsule())
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}

struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44).whimGlass(in: Capsule())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
