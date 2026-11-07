import Foundation
import XCTest
@testable import WhimCore

final class DebugFixtureRecorderIntegrationTests: XCTestCase {
    // Break: development audio bypasses or cannot exercise the real silence policy.
    func testSpeechThenSilenceFixtureAutomaticallyFinalizesThroughRecordingService() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "configuration-test-fixture", withExtension: "m4a", subdirectory: "Fixtures"))
        let recorder = try XCTUnwrap(DebugFixtureRecorder.from(arguments: ["app", "-WhimFixtureAudio", fixture.path,
            "-WhimFixtureMeterSequence", "speech-then-silence"]))
        let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("notes.sqlite"))
        let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        let service = RecordingService(recorder: recorder, store: store, files: files)
        let events = await service.events()
        let session = try await service.start(source: .appleWatch, autoStop: .default)
        let completed = expectation(description: "fixture stops through the silence policy")
        let reading = Task {
            for await event in events {
                if case .finalized(let note) = event {
                    XCTAssertEqual(note?.id, session.noteID)
                    XCTAssertEqual(note?.captureOutcome, .completed)
                    completed.fulfill()
                    break
                }
            }
        }
        await fulfillment(of: [completed], timeout: 7)
        reading.cancel()
        let notes = try await store.listNotes(filter: .all)
        XCTAssertEqual(notes.count, 1)
        try await service.discard()
    }

    func testLaunchFixtureFinalizesThroughRealRecordingService() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "configuration-test-fixture", withExtension: "m4a", subdirectory: "Fixtures"))
        let recorder = try XCTUnwrap(DebugFixtureRecorder.from(arguments: ["app", "-WhimFixtureAudio", fixture.path]))
        let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("notes.sqlite"))
        let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        let service = RecordingService(recorder: recorder, store: store, files: files)
        _ = try await service.start(source: .iphone)
        let note = try await service.stop()
        XCTAssertNotNil(note)
        let notes = try await store.listNotes(filter: .all)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].hasLocalAudio)
        XCTAssertGreaterThan(notes[0].duration, 0)
    }
}
