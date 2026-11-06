import XCTest
import WhimCore
@testable import WhimIPhone

@MainActor final class WatchRecordingUpdateIntegrationTests: XCTestCase {
    // Break: opening the update edits storage, or continuing overwrites unrelated settings with a stale snapshot.
    func testDefaultsAreOnlySavedOnContinueAndPreserveLatestOtherPreferences() async throws {
        let h = try WhimFacadeHarness()
        defer { h.remove() }
        let client = h.makeService(permissions: GrantedPermissions())
        try await client.updatePreferences(.init(retentionPolicy: .never, transcriptionEnabled: false,
            transcriptionLocaleIdentifier: "es-ES", watchRecording: .init(autoStopEnabled: false, silenceDurationSeconds: 10)))
        let update = WatchRecordingUpdate(client: client)
        XCTAssertTrue(update.autoStopEnabled)
        XCTAssertEqual(update.silenceDurationSeconds, 3)
        let before = try await client.settings().preferences
        XCTAssertEqual(before.watchRecording, .init(autoStopEnabled: false, silenceDurationSeconds: 10))
        try await client.updatePreferences(.init(retentionPolicy: .sevenDays, transcriptionEnabled: false,
            transcriptionLocaleIdentifier: "es-ES", watchRecording: before.watchRecording))
        let completed = await update.save()
        XCTAssertTrue(completed)
        let saved = try await client.settings().preferences
        XCTAssertEqual(saved.watchRecording, .init(autoStopEnabled: true, silenceDurationSeconds: 3))
        XCTAssertEqual(saved.retentionPolicy, .sevenDays)
        XCTAssertFalse(saved.transcriptionEnabled)
        XCTAssertEqual(saved.transcriptionLocaleIdentifier, "es-ES")
    }

    // Break: Continue saves the suggested default instead of the user's chosen toggle and duration.
    func testContinueSavesTheChosenWatchSettings() async throws {
        let h = try WhimFacadeHarness()
        defer { h.remove() }
        let client = h.makeService(permissions: GrantedPermissions())
        let update = WatchRecordingUpdate(client: client)
        update.autoStopEnabled = false
        update.silenceDurationSeconds = 2
        let completed = await update.save()
        XCTAssertTrue(completed)
        let saved = try await client.settings().preferences
        XCTAssertEqual(saved.watchRecording, .init(autoStopEnabled: false, silenceDurationSeconds: 2))
    }

    // Break: a failed save dismisses the update or loses the draft instead of allowing a retry.
    func testFailedSaveKeepsTheDraftAndAllowsRetry() async throws {
        let h = try WhimFacadeHarness()
        defer { h.remove() }
        let client = h.makeService(permissions: GrantedPermissions())
        let update = WatchRecordingUpdate(client: client)
        update.silenceDurationSeconds = 11
        let failed = await update.save()
        XCTAssertFalse(failed)
        XCTAssertNotNil(update.error)
        XCTAssertEqual(update.silenceDurationSeconds, 11)
        XCTAssertFalse(update.isPending)
        let unchanged = try await client.settings().preferences
        XCTAssertEqual(unchanged.watchRecording, .init(autoStopEnabled: true, silenceDurationSeconds: 3))
        update.silenceDurationSeconds = 10
        let completed = await update.save()
        XCTAssertTrue(completed)
        XCTAssertNil(update.error)
        let saved = try await client.settings().preferences
        XCTAssertEqual(saved.watchRecording.silenceDurationSeconds, 10)
    }
}
