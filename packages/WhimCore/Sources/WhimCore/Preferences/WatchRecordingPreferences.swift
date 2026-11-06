import Foundation

public struct WatchRecordingPreferences: Codable, Equatable, Sendable {
    public let autoStopEnabled: Bool
    public let silenceDurationSeconds: Int
    public static let `default` = Self(autoStopEnabled: true, silenceDurationSeconds: 3)

    public init(autoStopEnabled: Bool, silenceDurationSeconds: Int) {
        self.autoStopEnabled = autoStopEnabled
        self.silenceDurationSeconds = silenceDurationSeconds
    }

    public func validate() throws {
        guard (2...10).contains(silenceDurationSeconds) else {
            throw ValidationError.invalidSilenceDuration
        }
    }

    public enum ValidationError: Error, LocalizedError {
        case invalidSilenceDuration
        public var errorDescription: String? { "Choose a silence duration between 2 and 10 seconds." }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(autoStopEnabled: try values.decode(Bool.self, forKey: .autoStopEnabled),
            silenceDurationSeconds: try values.decode(Int.self, forKey: .silenceDurationSeconds))
        try validate()
    }
}
