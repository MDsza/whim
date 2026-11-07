import SwiftUI
import WhimCore
import WhimIPhone

struct OnboardingView: View {
    var model: IPhoneModel
    let settings: SettingsProjection?
    @AppStorage("onboarding.v1.step", store: UserDefaults(suiteName: WhimProductionComposition.appGroupIdentifier)) private var savedStep = 0
    @Binding private var setupAcknowledged: Bool
    @AppStorage("onboarding.quickCapture.v1.step", store: UserDefaults(suiteName: WhimProductionComposition.appGroupIdentifier)) private var upgradeStep = 3
    let setupOnly: Bool
    private var step: Int { QuickCaptureGuide.onboardingStep(saved: setupOnly ? upgradeStep : savedStep, setupOnly: setupOnly) }
    @State private var setupPage = 0
    @State private var webhook: WebhookEditor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize

    init(model: IPhoneModel, settings: SettingsProjection?, setupOnly: Bool = false, setupAcknowledged: Binding<Bool> = .constant(false)) {
        self._setupAcknowledged = setupAcknowledged
        self.setupOnly = setupOnly
        self.model = model; self.settings = settings
        _webhook = State(initialValue: WebhookEditor(client: model.client))
    }

    var body: some View {
        OnboardingFrame(step: step, back: step == 0 || (setupOnly && step == 3) || (step == 2 && model.startupState?.microphone == .notDetermined) ? nil : { move(to: step - 1) }) {
            Group {
                switch step {
                case 0: OnboardingWelcome()
                case 1: OnboardingWorkflow(model: model, settings: settings, webhook: webhook)
                case 2: OnboardingMicrophone(microphoneDenied: microphoneDenied)
                default: QuickCaptureSetupView(onPageChange: { setupPage = $0 })
                }
            }.id(step).transition(.opacity)
        } actions: {
            switch step {
            case 0:
                Button("Get started", systemImage: "arrow.right") { move(to: 1) }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                if !textSize.isAccessibilitySize { OnboardingPrivacyText() }
            case 1:
                Button("Continue to microphone", systemImage: "arrow.right") { move(to: 2) }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
            case 2:
                if model.startupState?.microphone == .notDetermined {
                    Button("Continue", systemImage: "arrow.right") { complete(request: true) }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                } else {
                    if microphoneDenied {
                        Button("Open system settings", systemImage: "arrow.up.right") {
                            Task { await model.perform { try await model.client.openSystemSettings() } }
                        }.buttonStyle(OnboardingPrimaryButtonStyle())
                    }
                    if model.startupState?.microphone == .granted {
                        Button(QuickCaptureGuide.currentRoute == nil ? "Continue" : "Continue to setup") { complete(request: false) }
                            .buttonStyle(OnboardingPrimaryButtonStyle())
                    } else {
                        Button("Continue") { complete(request: false) }
                            .buttonStyle(OnboardingSecondaryButtonStyle())
                    }
                }
            default:
                if QuickCaptureGuide.currentRoute == .actionButton && setupPage == 1 {
                    Button("Continue") { finish() }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                } else {
                    Button("Skip for now") { finish() }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                }
            }
        }
        .disabled(model.isPending || model.startupState == nil || webhook.isPending)
        .sensoryFeedback(.selection, trigger: step)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding")
    }

    private var microphoneDenied: Bool {
        model.startupState?.microphone == .denied || model.startupState?.microphone == .restricted
    }
    private func move(to destination: Int) {
        Task {
            if step == 1 { await webhook.saveIfNeeded(); await model.refresh() }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                if setupOnly { upgradeStep = destination } else { savedStep = destination }
            }
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
    private func complete(request: Bool) {
        Task {
            await model.perform {
                if request { _ = try await model.client.requestPermission(.microphone) }
            }
            if QuickCaptureGuide.currentRoute == nil { finish() }
            else { move(to: 3) }
        }
    }
    private func finish() {
        // Acknowledge while this view is mounted, before completion can replace it.
        setupAcknowledged = true
        guard !setupOnly else { return }
        Task { await model.perform { try await model.client.completeOnboarding() } }
    }

}
