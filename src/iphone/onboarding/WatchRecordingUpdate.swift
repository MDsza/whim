import Observation
import WhimCore

/// Suggested Watch settings for the one-time update; opening it never changes saved preferences.
@MainActor @Observable public final class WatchRecordingUpdate {
    public nonisolated static let acknowledgementKey = "onboarding.watchSilence.v1.acknowledged"
    public var autoStopEnabled = WatchRecordingPreferences.default.autoStopEnabled
    public var silenceDurationSeconds = WatchRecordingPreferences.default.silenceDurationSeconds
    public private(set) var isPending = false
    public private(set) var error: IPhoneError?
    private let client: any WhimClient

    public init(client: any WhimClient) { self.client = client }

    public static func needsPresentation(onboardingCompleted: Bool, acknowledged: Bool, isRecording: Bool) -> Bool {
        onboardingCompleted && !acknowledged && !isRecording
    }

    public func save() async -> Bool {
        guard !isPending else { return false }
        isPending = true; error = nil
        defer { isPending = false }
        do {
            let current = try await client.settings().preferences
            try await client.updatePreferences(.init(retentionPolicy: current.retentionPolicy,
                transcriptionEnabled: current.transcriptionEnabled,
                transcriptionLocaleIdentifier: current.transcriptionLocaleIdentifier,
                watchRecording: .init(autoStopEnabled: autoStopEnabled, silenceDurationSeconds: silenceDurationSeconds),
                watchRecordingRevision: current.watchRecordingRevision))
            return true
        } catch is CancellationError { return false }
        catch { self.error = IPhoneError(error); return false }
    }
}
