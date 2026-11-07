import SwiftUI
import WhimIPhone

/// Uses the onboarding frame with release-selected native content and optional settings.
struct AppUpdateView: View {
    @Bindable var model: AppUpdateModel
    let update: AppUpdate

    var body: some View {
        OnboardingFrame(step: 0, showsProgress: false) {
            VStack(alignment: .leading, spacing: 32) {
                OnboardingHeading(title: update.title, detail: update.detail)
                ForEach(Array(update.sections.enumerated()), id: \.offset) { _, section in
                    content(section)
                }
                if let error = model.error {
                    WhimErrorText(message: error.message)
                    if model.editor == nil {
                        Button("Try again") { Task { await model.load() } }
                            .buttonStyle(OnboardingSecondaryButtonStyle())
                    }
                }
            }
        } actions: {
            Button("Continue") { Task { await model.complete() } }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(update.hasPreferenceControls && model.editor == nil)
                .accessibilityIdentifier("app-update-continue")
            if !update.sections.contains(.watchRecording) {
                Button("Skip for now") { model.skip() }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .accessibilityIdentifier("app-update-skip")
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(uiColor: .systemGreen)))
        .disabled(model.isPending)
        .task { await model.load() }
        .interactiveDismissDisabled()
        .presentationDetents([.large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-update-sheet")
    }

    @ViewBuilder private func content(_ section: AppUpdate.Section) -> some View {
        switch section {
        case .quickCaptureGuide:
            QuickCaptureSetupView()
        case .watchRecording:
            if let editor = model.editor {
                AppUpdateWatchRecording(editor: editor)
            } else if model.error == nil { ProgressView("Loading Watch settings…") }
        }
    }
}
