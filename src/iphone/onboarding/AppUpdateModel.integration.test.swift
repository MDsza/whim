import XCTest
import WhimCore
@testable import WhimIPhone

@MainActor final class AppUpdateModelIntegrationTests: XCTestCase {
    private let storage = UpdateDefaults()
    private var suite: String { storage.suite }
    private var defaults: UserDefaults { storage.value }

    func testWatchUpdateAfterPriorAnnouncementSuggestsDefaultsWithoutWritingUntilContinue() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        defaults.set(["quick-capture-v1"], forKey: "onboarding.updates.v1.covered")
        let preferences = try UserDefaultsPreferenceStore(suiteName: suite)
        let client = harness.makeService(permissions: GrantedPermissions(), preferences: preferences)
        try await client.updatePreferences(.init(retentionPolicy: .never, transcriptionEnabled: false,
            transcriptionLocaleIdentifier: "es-ES", watchRecording: .init(autoStopEnabled: false, silenceDurationSeconds: 10)))
        let update = AppUpdateModel(client: client, defaults: defaults)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        XCTAssertTrue(editor.watchAutoStopEnabled)
        XCTAssertEqual(editor.watchSilenceDurationSeconds, 3)
        XCTAssertEqual(try preferences.load().watchRecording, .init(autoStopEnabled: false, silenceDurationSeconds: 10))
        try await client.updatePreferences(.init(retentionPolicy: .sevenDays, transcriptionEnabled: false,
            transcriptionLocaleIdentifier: "es-ES", watchRecording: .init(autoStopEnabled: false, silenceDurationSeconds: 10)))
        await update.complete()
        let saved = try preferences.load()
        XCTAssertEqual(saved.watchRecording, .init(autoStopEnabled: true, silenceDurationSeconds: 3))
        XCTAssertEqual(saved.retentionPolicy, .sevenDays)
        XCTAssertFalse(saved.transcriptionEnabled)
        XCTAssertEqual(saved.transcriptionLocaleIdentifier, "es-ES")
        XCTAssertNil(update.pendingUpdate)
    }

    func testWatchUpdateSavesTheSelectedToggleAndDuration() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = try UserDefaultsPreferenceStore(suiteName: suite)
        let update = AppUpdateModel(client: harness.makeService(preferences: preferences), defaults: defaults)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        editor.watchAutoStopEnabled = false
        editor.watchSilenceDurationSeconds = 2
        await update.complete()
        XCTAssertEqual(try preferences.load().watchRecording, .init(autoStopEnabled: false, silenceDurationSeconds: 2))
        XCTAssertNil(update.pendingUpdate)
    }

    func testSkippingWatchUpdatePreservesTheSavedChoice() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = try UserDefaultsPreferenceStore(suiteName: suite)
        let client = harness.makeService(preferences: preferences)
        try await client.updatePreferences(.init(retentionPolicy: .never, transcriptionEnabled: false,
            transcriptionLocaleIdentifier: nil, watchRecording: .init(autoStopEnabled: false, silenceDurationSeconds: 10)))
        let update = AppUpdateModel(client: client, defaults: defaults)
        update.prepare(onboardingCompleted: true)
        await update.load()
        update.skip()
        XCTAssertEqual(try preferences.load().watchRecording, .init(autoStopEnabled: false, silenceDurationSeconds: 10))
        XCTAssertNil(update.pendingUpdate)
    }

    func testFailedWatchSaveRetainsTheAnnouncementAndDraftForRetry() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = try UserDefaultsPreferenceStore(suiteName: suite)
        let update = AppUpdateModel(client: harness.makeService(preferences: preferences), defaults: defaults)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        editor.watchSilenceDurationSeconds = 11
        await update.complete()
        XCTAssertNotNil(update.pendingUpdate)
        XCTAssertNotNil(update.error)
        XCTAssertEqual(editor.watchSilenceDurationSeconds, 11)
        XCTAssertFalse(update.isPending)
        XCTAssertEqual(try preferences.load().watchRecording.silenceDurationSeconds, 3)
        editor.watchSilenceDurationSeconds = 10
        await update.complete()
        XCTAssertNil(update.pendingUpdate)
        XCTAssertEqual(try preferences.load().watchRecording.silenceDurationSeconds, 10)
    }

    func testFreshInstallNeverSeesItsAnnouncementAfterCompletingOnboardingOrRelaunching() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let onboarding = UserDefaultsOnboardingStore(suiteName: suite)
        let client = harness.makeService(onboarding: onboarding)
        let update = AppUpdateModel(client: client, defaults: defaults)
        update.prepare(onboardingCompleted: onboarding.isComplete())
        XCTAssertNil(update.pendingUpdate)
        let interrupted = AppUpdateModel(client: client, defaults: defaults)
        interrupted.prepare(onboardingCompleted: onboarding.isComplete())
        try await client.completeOnboarding()
        interrupted.prepare(onboardingCompleted: onboarding.isComplete())
        XCTAssertNil(interrupted.pendingUpdate)
        let relaunched = AppUpdateModel(client: client, defaults: defaults)
        relaunched.prepare(onboardingCompleted: onboarding.isComplete())
        XCTAssertNil(relaunched.pendingUpdate)
    }

    func testExistingInstallWithNoMarkerSeesAnnouncementUntilExplicitAcknowledgement() throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService()
        let update = AppUpdateModel(client: client, defaults: defaults)
        update.prepare(onboardingCompleted: true)
        XCTAssertEqual(update.pendingUpdate?.id, AppUpdate.current.id)
        let interrupted = AppUpdateModel(client: client, defaults: defaults)
        interrupted.prepare(onboardingCompleted: true)
        XCTAssertNotNil(interrupted.pendingUpdate)
        interrupted.skip()
        let relaunched = AppUpdateModel(client: client, defaults: defaults)
        relaunched.prepare(onboardingCompleted: true)
        XCTAssertNil(relaunched.pendingUpdate)
        let later = AppUpdate(id: "later-update", title: "Later", detail: "Another change", sections: [])
        let upgraded = AppUpdateModel(client: client, defaults: defaults, update: later)
        upgraded.prepare(onboardingCompleted: true)
        XCTAssertEqual(upgraded.pendingUpdate?.id, "later-update")
    }

    func testContinueSavesOnlyWatchPreferencesBeforePersistingAcknowledgement() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = try UserDefaultsPreferenceStore(suiteName: suite)
        let client = harness.makeService(preferences: preferences)
        let update = AppUpdateModel(client: client, defaults: defaults, update: watchSettingsUpdate)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        editor.watchAutoStopEnabled = false
        editor.watchSilenceDurationSeconds = 10
        editor.transcriptionEnabled = false
        editor.retentionPolicy = .never
        XCTAssertEqual(try preferences.load(), .default, "Editing must not change saved defaults")
        await update.complete()
        XCTAssertNil(update.pendingUpdate)
        let saved = try preferences.load()
        XCTAssertEqual(saved.watchRecording, .init(autoStopEnabled: false, silenceDurationSeconds: 10))
        XCTAssertTrue(saved.transcriptionEnabled)
        XCTAssertEqual(saved.retentionPolicy, PreferenceInput.default.retentionPolicy)
        let relaunched = AppUpdateModel(client: client, defaults: defaults, update: watchSettingsUpdate)
        relaunched.prepare(onboardingCompleted: true)
        XCTAssertNil(relaunched.pendingUpdate)
    }

    // Regression: a non-Watch announcement must not reset the new Watch preferences.
    func testQuickCaptureAnnouncementPreservesLatestPreferences() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = try UserDefaultsPreferenceStore(suiteName: suite)
        let client = harness.makeService(preferences: preferences)
        let announcement = AppUpdate(id: "quick-capture-update", title: "Quick capture", detail: "Set up your Action button.",
                                     sections: [.quickCaptureGuide])
        let update = AppUpdateModel(client: client, defaults: defaults, update: announcement)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let latest = PreferenceInput(retentionPolicy: .never, transcriptionEnabled: false, transcriptionLocaleIdentifier: "es-ES",
                                     watchRecording: .init(autoStopEnabled: false, silenceDurationSeconds: 10))
        try await client.updatePreferences(latest)
        let savedBeforeContinue = try preferences.load()
        await update.complete()
        XCTAssertEqual(try preferences.load(), savedBeforeContinue)
        XCTAssertNil(update.pendingUpdate)
    }

    func testContinuingDeferredWatchAnnouncementPreservesNewerTitleAndRetentionSettings() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = try UserDefaultsPreferenceStore(suiteName: suite)
        let client = harness.makeService(preferences: preferences)
        let update = AppUpdateModel(client: client, defaults: defaults, update: watchSettingsUpdate)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        editor.watchSilenceDurationSeconds = 10
        // Settings can be opened by a deep link while an announcement is deferred.
        try await client.updatePreferences(.init(retentionPolicy: .never, transcriptionEnabled: false,
                                                transcriptionLocaleIdentifier: "fr-FR"))
        await update.load()
        await update.complete()
        let saved = try preferences.load()
        XCTAssertEqual(saved.watchRecording.silenceDurationSeconds, 10)
        XCTAssertFalse(saved.transcriptionEnabled)
        XCTAssertEqual(saved.retentionPolicy, .never)
        XCTAssertEqual(saved.transcriptionLocaleIdentifier, "fr-FR")
    }

    func testFailedSaveKeepsAnnouncementAndDraftForRetry() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = UpdateFailingPreferences()
        let client = harness.makeService(preferences: preferences)
        let update = AppUpdateModel(client: client, defaults: defaults, update: watchSettingsUpdate)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        editor.watchSilenceDurationSeconds = 10
        await update.complete()
        XCTAssertNotNil(update.pendingUpdate)
        XCTAssertNotNil(update.error)
        XCTAssertEqual(editor.watchSilenceDurationSeconds, 10)
        let relaunched = AppUpdateModel(client: client, defaults: defaults, update: watchSettingsUpdate)
        relaunched.prepare(onboardingCompleted: true)
        XCTAssertNotNil(relaunched.pendingUpdate)
        await preferences.allowSave()
        await update.complete()
        XCTAssertNil(update.pendingUpdate)
    }

    func testResetDuringSaveCannotAcknowledgeOrReviveTheOldPresentation() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = BlockingFacadePreferences()
        let update = AppUpdateModel(client: harness.makeService(preferences: preferences), defaults: defaults, update: watchSettingsUpdate)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        editor.watchSilenceDurationSeconds = 10
        let saving = Task { await update.complete() }
        await preferences.waitUntilSaving()
        update.prepare(onboardingCompleted: false)
        await preferences.finishSaving()
        await saving.value
        XCTAssertNil(update.pendingUpdate)
        XCTAssertNil(update.editor)
        update.prepare(onboardingCompleted: true)
        XCTAssertNil(update.pendingUpdate)
    }

    func testRootDefersAnnouncementDuringCaptureHistoryAndInactiveScenes() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService(permissions: GrantedPermissions())
        try await client.completeOnboarding()
        let model = IPhoneModel(client: client, appUpdateDefaults: defaults)
        await model.start()
        defer { model.stop() }
        XCTAssertTrue(model.offersAppUpdate)
        model.openHistory()
        XCTAssertFalse(model.offersAppUpdate)
        await model.closeHistory()
        XCTAssertTrue(model.offersAppUpdate)
        await model.setSceneActive(false)
        XCTAssertFalse(model.offersAppUpdate)
        await model.setSceneActive(true)
        await model.startRecording()
        XCTAssertFalse(model.offersAppUpdate)
        XCTAssertNotNil(model.appUpdate.pendingUpdate, "Deferral must not acknowledge an announcement")
        await model.discardRecording()
        XCTAssertTrue(model.offersAppUpdate)
        await model.perform { try await client.reset() }
        XCTAssertFalse(model.offersAppUpdate)
        try await client.completeOnboarding()
        await model.refresh()
        XCTAssertFalse(model.offersAppUpdate)
    }

    private var watchSettingsUpdate: AppUpdate {
        AppUpdate(id: "watch-settings-update", title: "Apple Watch", detail: "Choose your Watch settings.",
                  sections: [.watchRecording])
    }
}

private final class UpdateDefaults {
    let suite = "app-update-\(UUID().uuidString)"
    let value: UserDefaults
    init() { value = UserDefaults(suiteName: suite)! }
    deinit { value.removePersistentDomain(forName: suite) }
}

private actor UpdateFailingPreferences: PreferenceStoring {
    var value = PreferenceInput.default
    var fails = true
    func load() -> PreferenceInput { value }
    func save(_ input: PreferenceInput) throws {
        if fails { throw CocoaError(.fileWriteNoPermission) }
        value = input
    }
    func reset() { value = .default }
    func allowSave() { fails = false }
}
