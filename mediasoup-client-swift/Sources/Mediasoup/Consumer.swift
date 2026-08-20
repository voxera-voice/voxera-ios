import Foundation
import WebRTC

// MARK: - Consumer

public class Consumer {
    public weak var delegate: (any ConsumerDelegate)?

    public let id: String
    public let localId: String
    public let producerId: String
    public let track: RTCMediaStreamTrack
    public let kind: MediaKind
    public private(set) var closed: Bool = false
    public private(set) var paused: Bool = false
    public let appData: String
    public let rtpParameters: String
    public var stats: String { "" }

    // Internal callback to handler for cleanup
    var onClose: ((String) -> Void)?

    init(
        id: String,
        localId: String,
        producerId: String,
        track: RTCMediaStreamTrack,
        kind: MediaKind,
        rtpParameters: String,
        appData: String
    ) {
        self.id = id
        self.localId = localId
        self.producerId = producerId
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

    // Called by transport when it closes
    func transportClosed() {
        if closed { return }
        closed = true
        track.isEnabled = false
        delegate?.onTransportClose(in: self)
    }

    deinit {}
}
