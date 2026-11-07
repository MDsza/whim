import SwiftUI
import WhimIPhone

/// Startup and the interactive welcome share their first frame.
struct OnboardingFrame<Content: View, Actions: View>: View {
    let step: Int
    var totalSteps: Int = QuickCaptureGuide.currentRoute == nil ? 3 : 4
    var showsProgress = true
    var back: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                ScrollView {
                    content.frame(maxWidth: 480, alignment: .leading)
                        .padding(.horizontal, WhimSpacing.page).padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height, alignment: step == 1 ? .top : .center)
                }.scrollDismissesKeyboard(.interactively)
            }
            VStack(spacing: 12) { actions }
                .frame(maxWidth: 480).padding(.horizontal, WhimSpacing.page)
                .padding(.top, 20).padding(.bottom, 16)
                .frame(maxWidth: .infinity).background(.black)
                .fixedSize(horizontal: false, vertical: true)
        }.background(.black)
    }

    private var header: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                if let back {
                    Button(action: back) {
                        Image(systemName: "arrow.left").font(.body.weight(.medium))
                            .frame(width: 44, height: 44).whimGlass(in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Back")
                        .accessibilityIdentifier("onboarding-back")
                } else {
                    Image("whim.small").resizable().scaledToFit()
                        .frame(width: 34, height: 24).accessibilityHidden(true)
                }
                Text("whim").font(.title2.weight(.semibold))
                Spacer()
                if showsProgress {
                    Text(String(format: "%02d / %02d", step + 1, totalSteps))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .accessibilityLabel("Step \(step + 1) of \(totalSteps)")
                }
            }
            if showsProgress {
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Capsule().fill(.white.opacity(index <= step ? 0.85 : 0.15)).frame(height: 2)
                    }
                }.accessibilityHidden(true)
            }
        }.padding(.horizontal, WhimSpacing.page).padding(.top, 12).padding(.bottom, 8)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
