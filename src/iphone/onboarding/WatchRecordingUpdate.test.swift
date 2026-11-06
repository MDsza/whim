import XCTest
@testable import WhimIPhone

@MainActor final class WatchRecordingUpdateTests: XCTestCase {
    // Break: first-time, acknowledged, or actively recording users are interrupted by an update.
    func testUpdateOnlyInterruptsUnacknowledgedExistingUsersWhileIdle() {
        XCTAssertTrue(WatchRecordingUpdate.needsPresentation(onboardingCompleted: true, acknowledged: false, isRecording: false))
        XCTAssertFalse(WatchRecordingUpdate.needsPresentation(onboardingCompleted: false, acknowledged: false, isRecording: false))
        XCTAssertFalse(WatchRecordingUpdate.needsPresentation(onboardingCompleted: true, acknowledged: true, isRecording: false))
        XCTAssertFalse(WatchRecordingUpdate.needsPresentation(onboardingCompleted: true, acknowledged: false, isRecording: true))
    }
}
