import Foundation
import XCTest
@testable import WhimCore

final class WatchRecordingPreferencesTests: XCTestCase {
    // Break: legacy/new preferences omit the enabled, three-second Watch defaults.
    func testLegacyPreferenceDecodingPreservesExistingValuesAndAddsWatchDefaults() throws {
        let data = Data(#"{"retentionPolicy":"never","transcriptionEnabled":false,"transcriptionLocaleIdentifier":"es-ES"}"#.utf8)
        let input = try JSONDecoder().decode(PreferenceInput.self, from: data)
        XCTAssertEqual(input.retentionPolicy, .never)
        XCTAssertFalse(input.transcriptionEnabled)
        XCTAssertEqual(input.transcriptionLocaleIdentifier, "es-ES")
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        let watch = try XCTUnwrap(encoded["watchRecording"] as? [String: Any])
        XCTAssertEqual(watch["autoStopEnabled"] as? Bool, true)
        XCTAssertEqual(watch["silenceDurationSeconds"] as? Int, 3)
        XCTAssertEqual(encoded["watchRecordingRevision"] as? Int, 0)
    }

    // Break: out-of-range peer or disk values are accepted instead of rejected.
    func testDecodingRejectsInvalidSilenceDurationsAndAcceptsEndpoints() throws {
        for duration in [1, 11] {
            XCTAssertThrowsError(try JSONDecoder().decode(PreferenceInput.self, from: preferences(duration)))
        }
        for duration in [2, 3, 10] {
            let decoded = try JSONDecoder().decode(PreferenceInput.self, from: preferences(duration))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
            let watch = try XCTUnwrap(object["watchRecording"] as? [String: Any])
            XCTAssertEqual(watch["silenceDurationSeconds"] as? Int, duration)
        }
    }

    private func preferences(_ seconds: Int) -> Data {
        Data("{\"retentionPolicy\":\"thirty_days\",\"transcriptionEnabled\":true,\"watchRecording\":{\"autoStopEnabled\":true,\"silenceDurationSeconds\":\(seconds)}}".utf8)
    }
}
