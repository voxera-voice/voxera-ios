import Foundation
import WebRTC

// MARK: - Producer

public class Producer {
    public weak var delegate: (any ProducerDelegate)?

    public let id: String
    public let localId: String
    public private(set) var track: RTCMediaStreamTrack
    public let kind: MediaKind
    public private(set) var closed: Bool = false
    public private(set) var paused: Bool = false
    public var maxSpatialLayer: UInt8 { 0 }
    public let appData: String
    public let rtpParameters: String
    public var stats: String { "" }

    // Internal callback to handler for cleanup
    var onClose: ((String) -> Void)?

    init(
        id: String,
        localId: String,
        track: RTCMediaStreamTrack,
        kind: MediaKind,
        rtpParameters: String,
        appData: String
    ) {
        self.id = id
        self.localId = localId
        self.track = track
        self.kind = kind
        self.rtpParameters = rtpParameters
        self.appData = appData
    }

    public func pause() {
        guard !closed else { return }
        paused = true
        track.isEnabled = false
    }

    public func resume() {
        guard !closed else { return }
        paused = false
        track.isEnabled = true
    }

    public func close() {
        guard !closed else { return }
        closed = true
        track.isEnabled = false
        onClose?(localId)
    }

    public func replaceTrack(_ newTrack: RTCMediaStreamTrack) throws {
        guard !closed else {
            throw MediasoupError.invalidState("Producer closed")
        }
        track = newTrack
    }

    public func setMaxSpatialLayer(_ layer: Int) throws {}

    public func updateSenderParameters(_ updater: @escaping (RTPParameters) -> RTPParameters) {}

    public func getStats() throws -> String { return "[]" }

    // Called by transport when it closes
    func transportClosed() {
        if closed { return }
        closed = true
        track.isEnabled = false
        delegate?.onTransportClose(in: self)
    }

    deinit {}
}
