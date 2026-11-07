import Foundation

/// Recording-relative measurements only: absence of a measurement is never silence.
struct SilenceAutoStopPolicy {
    let preferences: WatchRecordingPreferences
    private var lastElapsed: TimeInterval?
    private var meaningfulSince: TimeInterval?
    private var quietSince: TimeInterval?
    private var armed = false

    init(preferences: WatchRecordingPreferences) { self.preferences = preferences }

    mutating func invalidateTiming() {
        lastElapsed = nil
        meaningfulSince = nil
        quietSince = nil
    }

    mutating func consume(elapsed: TimeInterval, peakPowerDBFS: Float) -> Bool {
        guard elapsed.isFinite, elapsed >= 0, peakPowerDBFS.isFinite else {
            invalidateTiming()
            return false
        }
        if let lastElapsed {
            if elapsed < lastElapsed {
                armed = false
                invalidateTiming()
            } else if elapsed - lastElapsed > RecordingLimits.maximumMeterGapSeconds {
                invalidateTiming()
            }
        }
        lastElapsed = elapsed
        if !armed {
            if peakPowerDBFS >= RecordingLimits.meaningfulPeakPowerDBFS {
                meaningfulSince = meaningfulSince ?? elapsed
                armed = elapsed - (meaningfulSince ?? elapsed) + 1e-6 >= RecordingLimits.autoStopArmingSeconds
            } else { meaningfulSince = nil }
        }
        guard armed, peakPowerDBFS <= RecordingLimits.autoStopQuietPowerDBFS else {
            quietSince = nil
            return false
        }
        quietSince = quietSince ?? elapsed
        return elapsed >= RecordingLimits.autoStopMinimumDurationSeconds
            && elapsed - (quietSince ?? elapsed) + 1e-6 >= Double(preferences.silenceDurationSeconds)
    }
}
