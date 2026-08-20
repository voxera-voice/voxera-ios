import Foundation
import WebRTC

// MARK: - SendTransport

public class SendTransport: Transport {
    public let id: String
    public private(set) var closed: Bool = false
    public var connectionState: TransportConnectionState = .new
    public let appData: String
    public var stats: String { handler.stats }

    /// Log sender stats for diagnostics
    public func logSenderStats() { handler.logSenderStats() }

    public weak var delegate: (any SendTransportDelegate)?

    private let handler: Handler
    private let extendedRtpCapabilities: ExtendedRtpCapabilities
    private var producers: [String: Producer] = [:]
    private var nextProducerId = 0

    init(
        id: String,
        handler: Handler,
        extendedRtpCapabilities: ExtendedRtpCapabilities,
        appData: String
    ) {
        self.id = id
        self.handler = handler
        self.extendedRtpCapabilities = extendedRtpCapabilities
        self.appData = appData

        handler.onConnect = { [weak self] dtlsParameters in
            guard let self = self else { return }
            await self.delegate?.onConnect(transport: self, dtlsParameters: dtlsParameters)
        }

        handler.onConnectionStateChange = { [weak self] state in
            guard let self = self else { return }
            self.connectionState = state
            self.delegate?.onConnectionStateChange(transport: self, connectionState: state)
        }
    }

    /// Create a Producer for the given track.
    public func createProducer(
        for track: RTCMediaStreamTrack,
        encodings: [RTCRtpEncodingParameters]?,
        codecOptions: String?,
        codec: String?,
        appData: String?
    ) async throws -> Producer {
        guard !closed else {
            throw MediasoupError.invalidState("Transport closed")
        }

        let sendResult = try await handler.send(
            track: track,
            encodings: encodings,
            codecOptions: codecOptions,
            codec: codec
        )

        // Call onProduce delegate to get server-assigned producer ID
        let kind: MediaKind = track.kind == "audio" ? .audio : .video
        let rtpParamsJson = try JSON.stringify(sendResult.rtpParameters)
        print("[Mediasoup.SendTransport] 🔵 Calling onProduce delegate for \(kind) track...")
        print("[Mediasoup.SendTransport] 🔵 RTP params: mid=\(sendResult.rtpParameters.mid ?? "nil"), codecs=\(sendResult.rtpParameters.codecs.map { "\($0.mimeType)/\($0.payloadType)" }), encodings=\(sendResult.rtpParameters.encodings?.map { "ssrc=\($0.ssrc ?? 0)" } ?? []), cname=\(sendResult.rtpParameters.rtcp?.cname ?? "nil")")

        let producerId: String? = await withCheckedContinuation { cont in
            delegate?.onProduce(
                transport: self,
                kind: kind,
                rtpParameters: rtpParamsJson,
                appData: appData ?? ""
            ) { id in
                print("[Mediasoup.SendTransport] ✅ onProduce callback - producerId: \(id ?? "nil")")
                cont.resume(returning: id)
            }
        }

        let producer = Producer(
            id: producerId ?? "producer-\(nextProducerId)",
            localId: sendResult.localId,
            track: track,
            kind: kind,
            rtpParameters: rtpParamsJson,
            appData: appData ?? ""
        )
        nextProducerId += 1

        producer.onClose = { [weak self] localId in
            Task {
                try? await self?.handler.stopSending(localId: localId)
            }
        }

        producers[producer.id] = producer
        print("[Mediasoup.SendTransport] ✅ Producer created successfully - id: \(producer.id)")
        return producer
    }

    public func close() {
        guard !closed else { return }
        closed = true
        handler.close()

        for producer in producers.values {
            producer.transportClosed()
        }
        producers.removeAll()
    }

    public func restartICE(with iceParameters: String) throws {}

    public func updateICEServers(_ iceServers: String) throws {
        guard let data = iceServers.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let servers = arr.compactMap { dict -> RTCIceServer? in
            guard let urls = dict["urls"] as? [String] ?? (dict["urls"] as? String).map({ [$0] }) else { return nil }
            return RTCIceServer(urlStrings: urls,
                                username: dict["username"] as? String ?? "",
                                credential: dict["credential"] as? String ?? "")
        }
        handler.updateIceServers(servers)
    }
}

// MARK: - ReceiveTransport

public class ReceiveTransport: Transport {
    public let id: String
    public private(set) var closed: Bool = false
    public var connectionState: TransportConnectionState = .new
    public let appData: String
    public var stats: String { handler.stats }

    public weak var delegate: (any ReceiveTransportDelegate)?

    private let handler: Handler
    private let extendedRtpCapabilities: ExtendedRtpCapabilities
    private var consumers: [String: Consumer] = [:]

    init(
        id: String,
        handler: Handler,
        extendedRtpCapabilities: ExtendedRtpCapabilities,
        appData: String
    ) {
        self.id = id
        self.handler = handler
        self.extendedRtpCapabilities = extendedRtpCapabilities
        self.appData = appData

        handler.onConnect = { [weak self] dtlsParameters in
            guard let self = self else { return }
            await self.delegate?.onConnect(transport: self, dtlsParameters: dtlsParameters)
        }

        handler.onConnectionStateChange = { [weak self] state in
            guard let self = self else { return }
            self.connectionState = state
            self.delegate?.onConnectionStateChange(transport: self, connectionState: state)
        }
    }

    /// Consume a remote producer.
    public func consume(
        consumerId: String,
        producerId: String,
        kind: MediaKind,
        rtpParameters: String,
        appData: String?
    ) async throws -> Consumer {
        guard !closed else {
            throw MediasoupError.invalidState("Transport closed")
        }

        let rtpParams = try JSON.parse(rtpParameters, as: MsRtpParameters.self)

        let recvResult = try await handler.receive(
            trackId: consumerId,
            kind: kind.rawValue,
            rtpParameters: rtpParams
        )

        let consumer = Consumer(
            id: consumerId,
            localId: recvResult.localId,
            producerId: producerId,
            track: recvResult.track,
            kind: kind,
            rtpParameters: rtpParameters,
            appData: appData ?? ""
        )

        consumer.onClose = { [weak self] localId in
            Task {
                try? await self?.handler.stopReceiving(localId: localId)
            }
        }

        consumers[consumer.id] = consumer
        return consumer
    }

    public func close() {
        guard !closed else { return }
        closed = true
        handler.close()

        for consumer in consumers.values {
            consumer.transportClosed()
        }
        consumers.removeAll()
    }

    public func restartICE(with iceParameters: String) throws {}

    public func updateICEServers(_ iceServers: String) throws {
        guard let data = iceServers.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let servers = arr.compactMap { dict -> RTCIceServer? in
            guard let urls = dict["urls"] as? [String] ?? (dict["urls"] as? String).map({ [$0] }) else { return nil }
            return RTCIceServer(urlStrings: urls,
                                username: dict["username"] as? String ?? "",
                                credential: dict["credential"] as? String ?? "")
        }
        handler.updateIceServers(servers)
    }
}
