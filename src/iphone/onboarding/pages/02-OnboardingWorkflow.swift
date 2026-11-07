import SwiftUI
import WhimCore
import WhimIPhone

struct OnboardingWorkflow: View {
    let model: IPhoneModel
    let settings: SettingsProjection?
    let webhook: WebhookEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            OnboardingWorkflowHeading()
            if let settings {
                WebhookConfigurationView(model: model, editor: webhook, configuration: settings.webhook, compact: true)
                    .padding(20)
                    .background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12), lineWidth: 1))
            } else { ProgressView("Loading webhook settings…") }
            Link(destination: URL(string: "https://github.com/kumibrr/whim/blob/main/docs/webhook-contract-v1.md#reference-receiver")!) {
                Label("Set up a server", systemImage: "arrow.up.right")
            }.whimGlassButton().accessibilityIdentifier("onboarding-server-setup")
            Label("Set this up later. Your Notes stay on your device until a destination is ready.", systemImage: "tray")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingWorkflowHeading: View {
    var body: some View {
        OnboardingHeading(title: "Your workflow,\ndirectly.",
            detail: "Send each Note to a destination you control. Your audio goes straight from your device to your webhook.")
    }
}
