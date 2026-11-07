import Foundation
import Observation
import WhimCore

/// Deliberate announcements are independent of app versions and first-install onboarding.
public struct AppUpdate: Identifiable, Equatable, Sendable {
    public enum Section: Equatable, Sendable {
        case quickCaptureGuide, watchRecording
    }
    public let id: String
    public let title: String
    public let detail: String
    public let sections: [Section]

    public init(id: String, title: String, detail: String, sections: [Section]) {
        self.id = id; self.title = title; self.detail = detail; self.sections = sections
    }

    /// Select release content here. Keep the ID stable until a new announcement is intended.
    public static let current = AppUpdate(id: "watch-silence-v1", title: "Hands-free Notes on Apple Watch",
        detail: "After you speak, Whim can stop, save, and send your Note when it detects silence.",
        sections: [.watchRecording])

    public var hasPreferenceControls: Bool {
        sections.contains(.watchRecording)
    }
}

/// Owns the update presentation's durable eligibility and optional Watch settings draft.
@MainActor @Observable public final class AppUpdateModel {
    public private(set) var pendingUpdate: AppUpdate?
    public private(set) var editor: SettingsEditor?
    public private(set) var isPending = false
    public var error: IPhoneError? { loadError ?? editor?.error }
    private var loadError: IPhoneError?
    private let client: any WhimClient
    private let defaults: UserDefaults
    private let update: AppUpdate
    private var prepared = false
    private var generation = 0
    private static let coveredKey = "onboarding.updates.v1.covered"

    public init(client: any WhimClient, defaults: UserDefaults, update: AppUpdate = .current) {
        self.client = client; self.defaults = defaults; self.update = update
    }

    /// Called with durable onboarding state before the user can finish onboarding.
    public func prepare(onboardingCompleted: Bool) {
        if !onboardingCompleted {
            // Covers both first install and Reset Whim, including an interrupted onboarding.
            generation += 1
            acknowledge()
            prepared = true
        } else if !prepared {
            prepared = true
            if !covered.contains(update.id) { pendingUpdate = update }
        }
    }

    public func load() async {
        guard pendingUpdate != nil, update.hasPreferenceControls, editor == nil, !isPending else { return }
        let revision = generation
        isPending = true; loadError = nil
        defer { if generation == revision { isPending = false } }
        do {
            let settings = try await client.settings()
            guard generation == revision, !Task.isCancelled else { return }
            editor = SettingsEditor(client: client, preferences: settings.preferences)
            if update.sections.contains(.watchRecording) {
                editor?.watchAutoStopEnabled = WatchRecordingPreferences.default.autoStopEnabled
                editor?.watchSilenceDurationSeconds = WatchRecordingPreferences.default.silenceDurationSeconds
            }
        } catch is CancellationError {} catch {
            if generation == revision { loadError = IPhoneError(error) }
        }
    }

    public func complete() async {
        guard pendingUpdate != nil, !isPending else { return }
        if update.hasPreferenceControls, editor == nil { await load() }
        guard !update.hasPreferenceControls || editor != nil, pendingUpdate != nil else { return }
        let revision = generation
        isPending = true; loadError = nil
        defer { if generation == revision { isPending = false } }
        if let editor {
            do {
                // A retained draft may outlive a deep link into Settings. Apply only
                // the controls actually edited here to the latest saved preferences.
                let latest = try await client.settings().preferences
                guard generation == revision, !Task.isCancelled else { return }
                let input = PreferenceInput(
                    retentionPolicy: latest.retentionPolicy,
                    transcriptionEnabled: latest.transcriptionEnabled,
                    transcriptionLocaleIdentifier: latest.transcriptionLocaleIdentifier,
                    watchRecording: .init(autoStopEnabled: editor.watchAutoStopEnabled, silenceDurationSeconds: editor.watchSilenceDurationSeconds),
                    watchRecordingRevision: latest.watchRecordingRevision)
                if input != latest { try await client.updatePreferences(input) }
            } catch is CancellationError { return } catch {
                if generation == revision { loadError = IPhoneError(error) }
                return
            }
        }
        guard generation == revision, !Task.isCancelled else { return }
        acknowledge()
    }

    public func skip() {
        guard pendingUpdate != nil, !isPending else { return }
        acknowledge()
    }

    private var covered: [String] { defaults.stringArray(forKey: Self.coveredKey) ?? [] }
    private func acknowledge() {
        var ids = covered
        if !ids.contains(update.id) { ids.append(update.id); defaults.set(ids, forKey: Self.coveredKey) }
        pendingUpdate = nil; editor = nil; loadError = nil; isPending = false
    }
}
