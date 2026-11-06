import XCTest
import WhimCore
@testable import WhimIPhone

@MainActor final class SettingsEditorIntegrationTests: XCTestCase {
    // Break: saving a Watch draft drops unrelated preferences or fails to persist the Watch choice.
    func testWatchRecordingDraftSavesWithoutChangingOtherPreferences() async throws {
        let h = try WhimFacadeHarness()
        defer { h.remove() }
        let client = h.makeService()
        try await client.updatePreferences(.init(retentionPolicy: .never, transcriptionEnabled: false,
            transcriptionLocaleIdentifier: "es-ES"))
        let editor = SettingsEditor(client: client, preferences: try await client.settings().preferences, deviceLanguage: "en-US")
        XCTAssertTrue(editor.watchAutoStopEnabled)
        XCTAssertEqual(editor.watchSilenceDurationSeconds, 3)
        XCTAssertFalse(editor.isDirty)
        editor.watchAutoStopEnabled = false
        editor.watchSilenceDurationSeconds = 10
        XCTAssertTrue(editor.canSave)
        await editor.save()
        XCTAssertNil(editor.error)
        XCTAssertFalse(editor.isDirty)
        let saved = try await client.settings().preferences
        XCTAssertEqual(saved.watchRecording, .init(autoStopEnabled: false, silenceDurationSeconds: 10))
        XCTAssertEqual(saved.retentionPolicy, .never)
        XCTAssertFalse(saved.transcriptionEnabled)
        XCTAssertEqual(saved.transcriptionLocaleIdentifier, "es-ES")
        editor.retentionPolicy = .oneDay
        await editor.save()
        let updated = try await client.settings().preferences
        XCTAssertEqual(updated.watchRecording, saved.watchRecording)
        editor.watchSilenceDurationSeconds = 11
        await editor.save()
        XCTAssertNotNil(editor.error)
        XCTAssertTrue(editor.isDirty)
        XCTAssertEqual(editor.watchSilenceDurationSeconds, 11)
        let unchanged = try await client.settings().preferences
        XCTAssertEqual(unchanged, updated)
    }

    func testLanguageDefaultsToDeviceLanguageAndKeepsFollowingItWhenSaved() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService()
        let editor = SettingsEditor(client: client, preferences: try await client.settings().preferences, deviceLanguage: "es-ES")
        XCTAssertEqual(editor.language, "es-ES")
        XCTAssertFalse(editor.isDirty)
        editor.retentionPolicy = .never
        await editor.save()
        XCTAssertNil(editor.error)
        let saved = try await client.settings().preferences
        XCTAssertEqual(saved.retentionPolicy, .never)
        XCTAssertNil(saved.transcriptionLocaleIdentifier)
        editor.language = " en-GB "
        await editor.save()
        let overridden = try await client.settings().preferences.transcriptionLocaleIdentifier
        XCTAssertEqual(overridden, "en-GB")
    }

    func testSaveCommitsWebhookPreferencesAndDraftHeaderTogether() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService()
        let editor = SettingsEditor(client: client, preferences: try await client.settings().preferences, deviceLanguage: "en-US")
        editor.webhook.endpoint = "https://example.com/receive"
        XCTAssertFalse(editor.webhook.isAddingHeader)
        editor.webhook.addHeader(configuration: nil)
        XCTAssertTrue(editor.webhook.isAddingHeader)
        editor.webhook.newName = "X-Workspace"
        editor.webhook.newValue = "private"
        editor.transcriptionEnabled = false
        XCTAssertTrue(editor.isDirty)
        await editor.save()
        XCTAssertNil(editor.error)
        XCTAssertFalse(editor.isDirty)
        XCTAssertFalse(editor.webhook.isAddingHeader)
        let settings = try await client.settings()
        XCTAssertEqual(settings.webhook?.customHeaders.map(\.name), ["X-Workspace"])
        XCTAssertEqual(settings.preferences.transcriptionEnabled, false)
    }

    func testInvalidWebhookKeepsAllEditsAndDoesNotSavePreferences() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService()
        let editor = SettingsEditor(client: client, preferences: try await client.settings().preferences, deviceLanguage: "en-US")
        editor.webhook.endpoint = "http://example.com"
        editor.retentionPolicy = .oneDay
        await editor.save()
        XCTAssertNotNil(editor.error)
        XCTAssertTrue(editor.isDirty)
        XCTAssertEqual(editor.retentionPolicy, .oneDay)
        let retention = try await client.settings().preferences.retentionPolicy
        XCTAssertEqual(retention, PreferenceInput.default.retentionPolicy)
    }

    func testCancellingDraftHeaderLeavesWebhookClean() throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let editor = WebhookEditor(client: harness.makeService())
        editor.addHeader(configuration: nil)
        editor.newName = "X-Draft"
        editor.cancelHeader()
        XCTAssertFalse(editor.isAddingHeader)
        XCTAssertFalse(editor.isDirty)
    }
}
