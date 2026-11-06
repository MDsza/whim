import Foundation
import XCTest
@testable import WhimCore

final class WatchRecordingPreferencesIntegrationTests: XCTestCase {
    // Break: saving/reopening the preference store drops the Watch choice or its revision.
    func testWatchPreferencesSurviveStoreRecreationAndResetToDefaults() throws {
        let suite = "watch-preferences-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = try UserDefaultsPreferenceStore(suiteName: suite)
        let data = Data(#"{"retentionPolicy":"never","transcriptionEnabled":false,"transcriptionLocaleIdentifier":"es-ES","watchRecording":{"autoStopEnabled":false,"silenceDurationSeconds":10},"watchRecordingRevision":7}"#.utf8)
        try store.save(JSONDecoder().decode(PreferenceInput.self, from: data))
        let reopened = try UserDefaultsPreferenceStore(suiteName: suite)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reopened.load())) as? [String: Any])
        let watch = try XCTUnwrap(encoded["watchRecording"] as? [String: Any])
        XCTAssertEqual(watch["autoStopEnabled"] as? Bool, false)
        XCTAssertEqual(watch["silenceDurationSeconds"] as? Int, 10)
        XCTAssertEqual(encoded["watchRecordingRevision"] as? Int, 7)
        XCTAssertEqual(try reopened.load().retentionPolicy, .never)
        reopened.reset()
        let reset = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reopened.load())) as? [String: Any])
        XCTAssertEqual((reset["watchRecording"] as? [String: Any])?["silenceDurationSeconds"] as? Int, 3)
    }
}


final class WatchRecordingSynchronizationIntegrationTests: XCTestCase {
    // Break: installed fixtures cannot supply the same authenticated preference envelope as the phone.
    func testDebugPeerSuppliesDisabledWatchPreferencesThroughTheProtocol() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "configuration-test-fixture", withExtension: "m4a", subdirectory: "Fixtures"))
        let peer = try XCTUnwrap(DebugPeerTransport.from(arguments: ["app", "-WhimPeerScenario", "watch-auto-stop-disabled"], fixture: fixture))
        let received = LockedRecordingPeerMessages()
        peer.activate { event in
            if case .message(let message) = event { received.append(message) }
        }
        let transfer = received.values.compactMap { message -> WatchRecordingPreferencesTransfer? in
            if case .watchRecordingPreferences(let value) = message.payload { return value }
            return nil
        }
        XCTAssertEqual(transfer, [.init(revision: 1, preferences: .init(autoStopEnabled: false, silenceDurationSeconds: 10))])
    }

    // Break: disconnected preferences are lost, accepted on the wrong device, or regress on replay.
    func testDurableWatchPreferencesSurviveRestartAndOutOfOrderMessagesWithoutWebhook() async throws {
        let phone = try RecordingSyncFixture(device: .iphone)
        let watch = try RecordingSyncFixture(device: .appleWatch)
        defer { phone.remove(); watch.remove() }
        let old = WatchRecordingPreferencesTransfer(revision: 1,
            preferences: .init(autoStopEnabled: false, silenceDurationSeconds: 10))
        let newest = WatchRecordingPreferencesTransfer(revision: 2,
            preferences: .init(autoStopEnabled: true, silenceDurationSeconds: 2))
        phone.transport.available = false
        try await phone.peer().queueWatchRecordingPreferences(old)
        try await phone.peer().queueWatchRecordingPreferences(newest)
        XCTAssertTrue(phone.transport.messages.isEmpty)
        phone.transport.available = true
        let sender = try phone.peer()
        try await sender.activated()
        let messages = phone.transport.messages.filter { if case .watchRecordingPreferences = $0.payload { true } else { false } }
        XCTAssertEqual(messages.count, 2)
        let last = try XCTUnwrap(messages.last)
        let receiver = try watch.peer()
        for message in messages.reversed() { _ = try await receiver.apply(message) }
        for message in messages { _ = try await watch.peer().apply(message) }
        XCTAssertEqual(try watch.preferences.load().watchRecording, newest.preferences)
        XCTAssertEqual(try watch.preferences.load().watchRecordingRevision, 2)
        XCTAssertEqual(try watch.preferences.load().retentionPolicy, .never)
        // Ordinary durability acknowledgement is insufficient to claim application.
        for message in messages {
            _ = try await sender.apply(.init(payload: .acknowledgement(.durable(message.messageID))))
        }
        let pending = try await sender.status()
        XCTAssertEqual(pending.recordingPreferencesState, "pending")
        try await receiver.flush()
        for message in watch.transport.messages { _ = try await sender.apply(message) }
        let applied = try await sender.status()
        XCTAssertEqual(applied.recordingPreferencesState, "synchronized")
        phone.transport.messages.removeAll()
        try await sender.activated()
        XCTAssertFalse(phone.transport.messages.contains {
            if case .watchRecordingPreferences = $0.payload { true } else { false }
        }, "Applying the newest revision retires superseded preference transfers")
        // Watch cannot overwrite the phone's recording preferences.
        _ = try await sender.apply(last)
        XCTAssertEqual(try phone.preferences.load().watchRecording, .default)
    }

    // Break: a restart completes reset then loses freshly replayed settings, or old generations resurrect them.
    func testResetReplaysOnlyNewGenerationPreferencesBeforeCapture() async throws {
        let watch = try RecordingSyncFixture(device: .appleWatch)
        defer { watch.remove() }
        let peer = try watch.peer()
        let old = ConnectivityEnvelope(payload: .watchRecordingPreferences(.init(revision: 9,
            preferences: .init(autoStopEnabled: false, silenceDurationSeconds: 10))))
        _ = try await peer.apply(old)
        let reset = try await peer.prepareReset()
        let fresh = ConnectivityEnvelope(generation: reset.generation, payload: .watchRecordingPreferences(.init(revision: 1,
            preferences: .init(autoStopEnabled: true, silenceDurationSeconds: 2))))
        // Higher-generation data is buffered, not applied before its reset.
        _ = try await peer.apply(fresh)
        _ = try await watch.peer().apply(reset)
        _ = try await watch.peer().apply(old)
        XCTAssertEqual(try watch.preferences.load().watchRecording.silenceDurationSeconds, 2)
        XCTAssertEqual(try watch.preferences.load().watchRecordingRevision, 1)
        _ = try await watch.peer().apply(reset)
        XCTAssertEqual(try watch.preferences.load().watchRecording.silenceDurationSeconds, 2)
    }

    // Break: invalid protocol values mutate local preferences or poison ordinary message replay.
    func testInvalidWatchPreferencesAreRejectedWithoutChangingSavedValues() async throws {
        let watch = try RecordingSyncFixture(device: .appleWatch)
        defer { watch.remove() }
        let message = ConnectivityEnvelope(payload: .watchRecordingPreferences(.init(revision: 1,
            preferences: .init(autoStopEnabled: true, silenceDurationSeconds: 11))))
        XCTAssertThrowsError(try ConnectivityEnvelope.decode(message.encoded()))
        do {
            _ = try await watch.peer().apply(message)
            XCTFail("Invalid preferences were accepted")
        } catch { }
        XCTAssertEqual(try watch.preferences.load().watchRecording, .default)
        _ = try await watch.peer().apply(.init(payload: .acknowledgement(.audio(NoteID()))))
    }
}

private struct RecordingSyncFixture {
    let root: URL
    let store: SQLiteWhimStore
    let files: AudioFileStore
    let preferences: UserDefaultsPreferenceStore
    let suite: String
    let device: AttemptDevice
    let transport = RecordingSyncTransport()
    init(device: AttemptDevice) throws {
        self.device = device
        suite = "watch-sync-\(UUID())"
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try .open(at: root.appendingPathComponent("whim.sqlite"))
        files = try .init(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        preferences = try .init(suiteName: suite)
        try preferences.save(.init(retentionPolicy: .never, transcriptionEnabled: false, transcriptionLocaleIdentifier: "es-ES"))
    }
    func peer() throws -> ConnectivityMergeService {
        try .init(store: store, files: files, databaseURL: root.appendingPathComponent("whim.sqlite"),
            root: root.appendingPathComponent("Peer"), device: device, transport: transport, preferences: preferences)
    }
    func remove() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class RecordingSyncTransport: PeerTransport, @unchecked Sendable {
    var available = true
    var isAvailable: Bool { available }
    var isActivated: Bool { true }
    var messages: [ConnectivityEnvelope] = []
    func activate(receive: @escaping @Sendable (PeerEvent) -> Void) {}
    func transfer(_ envelope: ConnectivityEnvelope) { messages.append(envelope) }
    func transferFile(at url: URL, metadata: ConnectivityEnvelope) {}
    func updateContext(_ envelope: ConnectivityEnvelope, credentials: StoredWebhookCredentials?) {}
}

private final class LockedRecordingPeerMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [ConnectivityEnvelope] = []
    var values: [ConnectivityEnvelope] { lock.withLock { messages } }
    func append(_ message: ConnectivityEnvelope) { lock.withLock { messages.append(message) } }
}
