import Foundation
import XCTest
@testable import WhimCore

final class ConnectivityProtocolTests: XCTestCase {
    func testUnavailabilityNamesTheFirstMissingRequirement() throws {
        XCTAssertEqual(PeerUnavailabilityReason.resolve(activated: false, paired: false, counterpartInstalled: false), .inactive)
        XCTAssertEqual(PeerUnavailabilityReason.resolve(activated: true, paired: false, counterpartInstalled: false), .unpaired)
        XCTAssertEqual(PeerUnavailabilityReason.resolve(activated: true, paired: true, counterpartInstalled: false), .appNotInstalled)
        XCTAssertEqual(PeerUnavailabilityReason.resolve(activated: true, paired: nil, counterpartInstalled: false), .appNotInstalled)
        XCTAssertNil(PeerUnavailabilityReason.resolve(activated: true, paired: true, counterpartInstalled: true))
    }

    func testWatchSettingsDecodeLegacyAndUnknownReasonsWithoutLosingCompatibility() throws {
        // Older peers and stored projections carry no reason; an available Watch never encodes one.
        let legacy = Data(#"{"availability":"unavailable","lastSynchronizedAt":null,"resetState":"idle"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(WatchSettingsProjection.self, from: legacy).availabilityReason)
        let explained = WatchSettingsProjection(availability: "unavailable", lastSynchronizedAt: nil, resetState: "idle",
            availabilityReason: PeerUnavailabilityReason.appNotInstalled.rawValue)
        let decoded = try JSONDecoder().decode(WatchSettingsProjection.self, from: JSONEncoder().encode(explained))
        XCTAssertEqual(decoded.availabilityReason, "appNotInstalled")
        let future = Data(#"{"availability":"unavailable","availabilityReason":"futureSystemReason","resetState":"idle"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(WatchSettingsProjection.self, from: future).availabilityReason,
            "futureSystemReason")
        let available = WatchSettingsProjection(availability: "available", lastSynchronizedAt: nil, resetState: "idle")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(available), as: UTF8.self).contains("availabilityReason"))
    }

    #if DEBUG
    func testInstalledFixtureLaunchesUseAnIsolatedPeerWhileOrdinaryLaunchUsesSystemPeer() throws {
        let fixture = URL(fileURLWithPath: "/fixture.m4a")
        XCTAssertNil(try DebugPeerTransport.from(arguments: ["Whim"], fixture: fixture))
        for arguments in [["Whim", "-WhimFixtureAudio", fixture.path],
                          ["Whim", "-WhimFixtureWebhookURL", "https://example.com"],
                          ["Whim", "-WhimWatchTestID", UUID().uuidString],
                          ["Whim", "-WhimWatchTestID", "malformed"], ["Whim", "-WhimFixtureAudio"]] {
            let peer = try XCTUnwrap(DebugPeerTransport.from(arguments: arguments, fixture: fixture))
            XCTAssertFalse(peer.isAvailable)
            peer.activate { event in
                if case .activated = event {} else { XCTFail("An isolated fixture must not consume another test's peer state") }
            }
            try peer.transfer(.init(payload: .reset))
            try peer.transferFile(at: fixture, metadata: .init(payload: .deletion(NoteID())))
            try peer.updateContext(.init(payload: .reset), credentials: nil)
        }
        XCTAssertThrowsError(try DebugPeerTransport.from(arguments: ["Whim", "-WhimPeerScenario", "malformed"], fixture: fixture))
        XCTAssertThrowsError(try DebugPeerTransport.from(arguments: ["Whim", "-WhimPeerScenario"], fixture: fixture))
        XCTAssertTrue(try XCTUnwrap(DebugPeerTransport.from(arguments: ["Whim", "-WhimFixtureAudio", fixture.path,
            "-WhimPeerScenario", "state-first"], fixture: fixture)).isAvailable)
    }
    #endif

    func testAdapterUsesDurableStateFileAndNewestContextWithOnlyDataDictionaries() throws {
        let session = ConnectivitySessionProbe()
        let adapter = WatchConnectivityAdapter(session: session)
        let deletion = ConnectivityEnvelope(payload: .deletion(NoteID()))
        try adapter.transfer(deletion)
        XCTAssertEqual(session.durable.count, 1)
        XCTAssertTrue(session.immediate.isEmpty)
        session.reachable = true
        try adapter.transfer(deletion)
        XCTAssertEqual(session.durable.count, 2)
        XCTAssertEqual(session.immediate.count, 1)
        try adapter.transferFile(at: URL(fileURLWithPath: "/fixture.m4a"), metadata: deletion)
        XCTAssertEqual(session.files.count, 1)
        let revision = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(),
            endpoint: .init(scheme: "https", host: "example.com", path: "/"))
        try adapter.updateContext(.init(payload: .configuration(revision)), credentials: nil)
        XCTAssertEqual(session.contexts.count, 1)
        let dictionary = try PropertyListSerialization.propertyList(from: session.durable[0], format: nil)
        XCTAssertNotNil(dictionary)
        XCTAssertEqual(try ConnectivityEnvelope.decode(session.durable[0]), deletion)
        XCTAssertThrowsError(try ConnectivityEnvelope.decode(ConnectivityEnvelope(schemaVersion: 2, payload: .reset).encoded()))
    }
}

private final class ConnectivitySessionProbe: WatchConnectivitySession, @unchecked Sendable {
    var reachable = false
    var durable: [Data] = []; var immediate: [Data] = []; var files: [URL] = []; var contexts: [Data] = []
    var isAvailable: Bool { true }; var isActivated: Bool { true }; var isReachable: Bool { reachable }
    func activate(receive: @escaping @Sendable (ConnectivitySessionEvent) -> Void) {}
    func transferUserInfo(_ data: Data) throws { durable.append(data) }
    func sendMessage(_ data: Data) { immediate.append(data) }
    func transferFile(_ url: URL, metadata: Data) throws { files.append(url) }
    func updateApplicationContext(_ data: Data, credentials: Data?) throws { contexts.append(data) }
}
