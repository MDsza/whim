import SwiftUI

struct OnboardingWelcome: View {
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            OnboardingHeading(title: "A place for\nyour thoughts.",
                detail: "Whim stores voice Notes locally on your iPhone and Apple Watch and delivers them directly to your webhook.")
            VStack(alignment: .leading, spacing: 24) {
                OnboardingBenefit(symbol: "lock", title: "Keep it yours",
                    detail: "Local storage. Your destination. You’re in control.")
                OnboardingBenefit(symbol: "hand.tap", title: "Convenient",
                    detail: "Record in Whim, or assign it to your iPhone’s Action button when supported.")
                OnboardingBenefit(symbol: "applewatch", title: "Apple Watch",
                    detail: "Use complications, or add Whim to the Smart Stack for hands-free operation.")
            }
            if textSize.isAccessibilitySize { OnboardingPrivacyText() }
        }
    }
}

private struct OnboardingBenefit: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.body).frame(width: 44, height: 44)
                .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }
}
