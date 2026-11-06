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
