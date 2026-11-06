#if DEBUG
import AVFoundation
import Foundation

/// Deterministic microphone boundary for compiled development journeys only.
public actor DebugFixtureRecorder: AudioRecorder {
    private let fixture: URL
    private let speechThenSilence: Bool
    private let pair = AsyncStream.makeStream(of: RecordingEvent.self)
    private var timer: Task<Void, Never>?
    public init(fixture: URL, speechThenSilence: Bool = false) {
        self.fixture = fixture; self.speechThenSilence = speechThenSilence
    }
    public static func from(arguments: [String]) throws -> DebugFixtureRecorder? {
        guard let index = arguments.firstIndex(of: "-WhimFixtureAudio") else { return nil }
        guard arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("/"),
              FileManager.default.isReadableFile(atPath: arguments[index + 1]) else {
            throw WhimServiceError.setupRequired("The development audio fixture is unavailable.")
        }
        var speechThenSilence = false
        if let sequence = arguments.firstIndex(of: "-WhimFixtureMeterSequence") {
            guard arguments.indices.contains(sequence + 1), arguments[sequence + 1] == "speech-then-silence" else {
                throw WhimServiceError.setupRequired("Unknown development microphone sequence.")
            }
            speechThenSilence = true
        }
        return .init(fixture: URL(fileURLWithPath: arguments[index + 1]), speechThenSilence: speechThenSilence)
    }
    public func events() -> AsyncStream<RecordingEvent> { pair.stream }
    public func start(at url: URL) throws {
        try FileManager.default.copyItem(at: fixture, to: url)
        let continuation = pair.continuation
        let speechThenSilence = speechThenSilence
        timer = Task {
            let start = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                let power: Float = speechThenSilence && elapsed >= 0.4 ? -60 : -12
                continuation.yield(.meter(elapsed: elapsed, peakPowerDBFS: power))
                continuation.yield(.elapsed(elapsed))
                continuation.yield(.peakPower(power))
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }
    public func stop() async throws {
        timer?.cancel(); timer = nil
        let duration = try await AVURLAsset(url: fixture).load(.duration).seconds
        pair.continuation.yield(.encoderCompleted(duration: duration, peakPowerDBFS: -12))
    }
    public func discard() { timer?.cancel(); timer = nil }
}
#endif
