import Foundation
import WebRTC

// MARK: - Device

public class Device {
    private var pcFactory: RTCPeerConnectionFactory
    private var loaded = false
    private var extendedRtpCapabilities: ExtendedRtpCapabilities?
    private var recvRtpCapabilities: RtpCapabilities?

    public init(captureAudioSession: Bool = false) {
        RTCInitializeSSL()
        pcFactory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }

    public init(pcFactory: RTCPeerConnectionFactory) {
        self.pcFactory = pcFactory
    }

    deinit {
        RTCCleanupSSL()
    }

    public func isLoaded() -> Bool { loaded }

    /// Load device with router RTP capabilities (JSON string).
    public func load(with routerRTPCapabilities: String) async throws {
        print("[Mediasoup.Device] 🔵 load() called")
        guard !loaded else {
            print("[Mediasoup.Device] ⚠️ Device already loaded")
            throw MediasoupError.invalidState("Device already loaded")
        }

        // Parse router capabilities
        print("[Mediasoup.Device] 🔵 Parsing router RTP capabilities...")
        let routerCaps = try JSON.parse(routerRTPCapabilities, as: RtpCapabilities.self)
        print("[Mediasoup.Device] ✅ Router caps parsed: \(routerCaps.codecs?.count ?? 0) codecs")

        // Get native RTP capabilities from a temporary PeerConnection
        print("[Mediasoup.Device] 🔵 Getting native RTP capabilities...")
        let nativeCaps = try await getNativeRtpCapabilities()
        print("[Mediasoup.Device] ✅ Native caps obtained: \(nativeCaps.codecs?.count ?? 0) codecs")

        // Compute extended RTP capabilities
        print("[Mediasoup.Device] 🔵 Computing extended RTP capabilities...")
        print("[Mediasoup.Device] 🔵 Router audio headerExtensions: \((routerCaps.headerExtensions ?? []).filter { $0.kind == nil || $0.kind == "audio" }.map { "\($0.uri) (id:\($0.preferredId), dir:\($0.direction ?? "sendrecv"))" })")
        let extended = ORTC.getExtendedRtpCapabilities(
            localCaps: nativeCaps,
            remoteCaps: routerCaps
        )
        print("[Mediasoup.Device] ✅ Extended caps: \(extended.codecs.count) codecs, \(extended.headerExtensions.count) extensions")
        print("[Mediasoup.Device] 🔵 Extended audio extensions: \(extended.headerExtensions.filter { $0.kind == nil || $0.kind == "audio" }.map { "\($0.uri) (sendId:\($0.sendId), dir:\($0.direction))" })")

        // Check we can send at least audio or video
        let canSendAudio = ORTC.canSend(kind: "audio", extendedCaps: extended)
        let canSendVideo = ORTC.canSend(kind: "video", extendedCaps: extended)
        print("[Mediasoup.Device] 🔵 canSend - audio: \(canSendAudio), video: \(canSendVideo)")
        guard canSendAudio || canSendVideo else {
            print("[Mediasoup.Device] ❌ No matching codecs with router")
            throw MediasoupError.unsupported("No matching codecs with router")
        }

        extendedRtpCapabilities = extended
        recvRtpCapabilities = ORTC.getRecvRtpCapabilities(extendedRtpCapabilities: extended)
        loaded = true
        print("[Mediasoup.Device] ✅ Device loaded successfully")
    }

    /// Get device RTP capabilities as JSON string.
    public func rtpCapabilities() throws -> String {
        guard loaded, let caps = recvRtpCapabilities else {
            throw MediasoupError.invalidState("Device not loaded")
        }
        return try JSON.stringify(caps)
    }

    /// Get device SCTP capabilities as JSON string.
    public func sctpCapabilities() throws -> String {
        return "{\"numStreams\":{\"OS\":1024,\"MIS\":1024}}"
    }

    /// Whether the device can produce the given media kind.
    public func canProduce(_ mediaKind: MediaKind) throws -> Bool {
        guard loaded, let extended = extendedRtpCapabilities else {
            throw MediasoupError.invalidState("Device not loaded")
        }
        return ORTC.canSend(kind: mediaKind.rawValue, extendedCaps: extended)
    }

    // MARK: - Create Transports

    public func createSendTransport(
        id: String,
        iceParameters: String,
        iceCandidates: String,
        dtlsParameters: String,
        sctpParameters: String? = nil,
        iceServers: String? = nil,
        iceTransportPolicy: ICETransportPolicy = .all,
        appData: String? = nil
    ) throws -> SendTransport {
        guard loaded, let extended = extendedRtpCapabilities else {
            throw MediasoupError.invalidState("Device not loaded")
        }

        let iceParsed = try JSON.parse(iceParameters, as: IceParametersJSON.self)
        let iceCandsParsed = try JSON.parse(iceCandidates, as: [IceCandidateJSON].self)
        let dtlsParsed = try JSON.parse(dtlsParameters, as: DtlsParametersJSON.self)
        let rtcIceServers = parseIceServers(iceServers)

        let handler = Handler(
            direction: .send,
            pcFactory: pcFactory,
            iceParameters: iceParsed,
            iceCandidates: iceCandsParsed,
            dtlsParameters: dtlsParsed,
            iceServers: rtcIceServers,
            iceTransportPolicy: iceTransportPolicy.rtcPolicy,
            extendedRtpCapabilities: extended
        )

        return SendTransport(
            id: id,
            handler: handler,
            extendedRtpCapabilities: extended,
            appData: appData ?? ""
        )
    }

    public func createReceiveTransport(
        id: String,
        iceParameters: String,
        iceCandidates: String,
        dtlsParameters: String,
        sctpParameters: String? = nil,
        iceServers: String? = nil,
        iceTransportPolicy: ICETransportPolicy = .all,
        appData: String? = nil
    ) throws -> ReceiveTransport {
        guard loaded, let extended = extendedRtpCapabilities else {
            throw MediasoupError.invalidState("Device not loaded")
        }

        let iceParsed = try JSON.parse(iceParameters, as: IceParametersJSON.self)
        let iceCandsParsed = try JSON.parse(iceCandidates, as: [IceCandidateJSON].self)
        let dtlsParsed = try JSON.parse(dtlsParameters, as: DtlsParametersJSON.self)
        let rtcIceServers = parseIceServers(iceServers)

        let handler = Handler(
            direction: .recv,
            pcFactory: pcFactory,
            iceParameters: iceParsed,
            iceCandidates: iceCandsParsed,
            dtlsParameters: dtlsParsed,
            iceServers: rtcIceServers,
            iceTransportPolicy: iceTransportPolicy.rtcPolicy,
            extendedRtpCapabilities: extended
        )

        return ReceiveTransport(
            id: id,
            handler: handler,
            extendedRtpCapabilities: extended,
            appData: appData ?? ""
        )
    }

    // MARK: - Private

    /// Get native RTP capabilities by creating a temp PeerConnection and generating an offer.
    private func getNativeRtpCapabilities() async throws -> RtpCapabilities {
        let config = RTCConfiguration()
        config.iceServers = []
        config.iceTransportPolicy = .all
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let tmpPc = pcFactory.peerConnection(with: config, constraints: constraints, delegate: nil) else {
            throw MediasoupError.invalidState("Failed to create temp PeerConnection")
        }

        // Add audio and video transceivers to get codec info in the offer
        let audioInit = RTCRtpTransceiverInit()
        audioInit.direction = .sendOnly
        let videoInit = RTCRtpTransceiverInit()
        videoInit.direction = .sendOnly

        let audioTransceiver = tmpPc.addTransceiver(of: .audio, init: audioInit)
        let videoTransceiver = tmpPc.addTransceiver(of: .video, init: videoInit)
        print("[Mediasoup.Device] 🔵 Transceivers added - audio: \(audioTransceiver != nil), video: \(videoTransceiver != nil)")
        print("[Mediasoup.Device] 🔵 PC transceivers count: \(tmpPc.transceivers.count)")

        // Create offer asynchronously
        let sdp: String = try await withCheckedThrowingContinuation { cont in
            let offerConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            tmpPc.offer(for: offerConstraints) { sdp, error in
                if let error = error {
                    cont.resume(throwing: MediasoupError.unknown(error))
                } else if let sdpStr = sdp?.sdp {
                    cont.resume(returning: sdpStr)
                } else {
                    cont.resume(throwing: MediasoupError.invalidState("createOffer returned nil SDP"))
                }
            }
        }
        print("[Mediasoup.Device] 🔵 Offer SDP:\n\(sdp)")
        tmpPc.close()

        let caps = SdpExtractor.extractRtpCapabilities(sdp: sdp)
        print("[Mediasoup.Device] 🔵 Extracted codecs: \(caps.codecs?.map { $0.mimeType } ?? [])")

        // Add NACK support for OPUS if not present (like reference implementation)
        var codecs = caps.codecs ?? []
        for i in 0..<codecs.count {
            if codecs[i].mimeType.lowercased() == "audio/opus" {
                let hasNack = codecs[i].rtcpFeedback?.contains { $0.type == "nack" && $0.parameter == nil } ?? false
                if !hasNack {
                    codecs[i].rtcpFeedback = (codecs[i].rtcpFeedback ?? []) + [RtcpFeedback(type: "nack")]
                }
            }
        }

        return RtpCapabilities(codecs: codecs, headerExtensions: caps.headerExtensions)
    }

    private func parseIceServers(_ json: String?) -> [RTCIceServer] {
        guard let json = json,
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { dict -> RTCIceServer? in
            guard let urls = dict["urls"] as? [String] ?? (dict["urls"] as? String).map({ [$0] }) else {
                return nil
            }
            let username = dict["username"] as? String ?? ""
            let credential = dict["credential"] as? String ?? ""
            return RTCIceServer(urlStrings: urls, username: username, credential: credential)
        }
    }

    // Stub methods for API compatibility
    public func retainAudioSession() {}
    public func releaseAudioSession() {}
}
