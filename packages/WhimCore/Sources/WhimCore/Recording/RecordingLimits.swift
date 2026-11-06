import Foundation

public enum RecordingLimits {
    public static let maximumDuration: Duration = .seconds(300)
    public static let warningLeadTime: Duration = .seconds(15)
    public static let silenceDiscardDuration: Duration = .seconds(1)
    public static let meaningfulPeakPowerDBFS: Float = -45
    static let autoStopQuietPowerDBFS: Float = -50
    static let autoStopArmingSeconds: TimeInterval = 0.2
    static let maximumMeterGapSeconds: TimeInterval = 0.5
    static let autoStopMinimumDurationSeconds: TimeInterval = 2
}
