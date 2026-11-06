import SwiftUI
import WhimCore
import WhimIPhone
struct PendingIPhoneLink { let id = UUID(); let url: URL }
@main struct WhimIPhoneApp: App {
    init() { BGTaskSchedulerAdapter.register() }
    @State private var model: IPhoneModel?
    @State private var failure: ActionableFailure?
    @State private var showsStorageInstructions = false
    private let onboarding = UserDefaultsOnboardingStore()
    @State private var starting = false
    @State private var startingRecording = false
    @State private var pendingLink: PendingIPhoneLink?
    var body: some Scene {
        WindowGroup {
            Group {
                if let model { IPhoneRootView(model: model, pendingLink: pendingLink) }
                else {
                    IPhoneStartupShell(onboardingCompleted: onboarding.isComplete(), recordingPending: startingRecording,
                        canRecord: failure?.blocksCapture != true) {
                        Task { await recordFromStartup() }
                    }
                        .safeAreaInset(edge: .top) {
                            if let failure {
                                WhimErrorContainer(message: failure.message, actionLabel: failure.actionLabel, busy: starting) {
                                    if failure.action == .storageInstructions { showsStorageInstructions = true }
                                    else { Task { await launch() } }
                                }.padding()
                            }
                        }.task { await launch() }
                        .alert("Free up storage", isPresented: $showsStorageInstructions) {
                            Button("Check again") { Task { await launch() } }
                            Button("Close", role: .cancel) {}
                        } message: { Text("Open iPhone Settings > General > iPhone Storage and remove items you no longer need. Then return to Whim and check again.") }
                }
            }.preferredColorScheme(.dark).tint(.white).buttonStyle(WhimButtonStyle())
                .toggleStyle(SwitchToggleStyle(tint: Color(uiColor: .systemGreen)))
                .onOpenURL { pendingLink = PendingIPhoneLink(url: $0) }
        }
    }
    @MainActor private func launch() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #endif
        guard !starting, model == nil else { return }; starting = true
        defer { starting = false }
        do {
            #if DEBUG
            // Hold only the automatic launch task to exercise the first rendered shell.
            let arguments = ProcessInfo.processInfo.arguments
            // Installed upgrade journeys begin with the persisted state of a prior release.
            if arguments.contains("-WhimFixtureAudio"), arguments.contains("-WhimFixtureWatchUpdate") {
                onboarding.complete()
            }
            if arguments.contains("-WhimFixtureAudio"),
               let index = arguments.firstIndex(of: "-WhimStartupDelayMilliseconds"),
               arguments.indices.contains(index + 1), let delay = Int(arguments[index + 1]), delay > 0 {
                try await Task.sleep(for: .milliseconds(delay))
            }
            #endif
            _ = try await mountModel()
            failure = nil
        } catch is CancellationError {} catch { failure = ActionableFailure(error, operation: .preparation) }
    }
    @MainActor private func mountModel() async throws -> IPhoneModel {
        let client = try await WhimRuntime.shared.service()
        // Automatic startup and the first Record tap may await the same composition.
        if let model { return model }
        let value = IPhoneModel(client: client, onboardingCompletedHint: onboarding.isComplete())
        model = value
        return value
    }
    @MainActor private func recordFromStartup() async {
        guard !startingRecording else { return }
        startingRecording = true
        defer { startingRecording = false }
        do {
            let model = try await mountModel()
            failure = nil
            await model.startRecording()
        } catch { failure = ActionableFailure(error, operation: .preparation) }
    }
}
