import Foundation
import WebRTC

// MARK: - Handler
// Manages a single RTCPeerConnection for either send or recv direction.
// Implements the mediasoup-client unified-plan handler pattern.

final class Handler: NSObject {

    enum Direction {
        case send
        case recv
    }

    struct SendResult {
        let localId: String       // transceiver mid
        let rtpParameters: MsRtpParameters
    }

    struct RecvResult {
        let localId: String
        let track: RTCMediaStreamTrack
    }

    private let direction: Direction
    private let pc: RTCPeerConnection
    private let remoteSdp: RemoteSdp
    private let extendedRtpCapabilities: ExtendedRtpCapabilities

    private var transportReady = false
    private var mapMidTransceiver: [String: RTCRtpTransceiver] = [:]

    // For send: local stream to use
    private let sendStream: RTCMediaStream

    // Called when transport needs to connect (first ICE + DTLS handshake)
    var onConnect: ((String) async -> Void)?  // dtlsParameters JSON
    // Called when connection state changes
    var onConnectionStateChange: ((TransportConnectionState) -> Void)?

    init(
        direction: Direction,
        pcFactory: RTCPeerConnectionFactory,
        iceParameters: IceParametersJSON,
        iceCandidates: [IceCandidateJSON],
        dtlsParameters: DtlsParametersJSON,
        iceServers: [RTCIceServer],
        iceTransportPolicy: RTCIceTransportPolicy,
        extendedRtpCapabilities: ExtendedRtpCapabilities
    ) {
        self.direction = direction
        self.extendedRtpCapabilities = extendedRtpCapabilities

        let config = RTCConfiguration()
        config.iceServers = iceServers
        print("[Mediasoup.Handler] 🔵 init - direction: \(direction), iceServers: \(iceServers.map { $0.urlStrings }), policy: \(iceTransportPolicy.rawValue)")
        config.iceTransportPolicy = iceTransportPolicy
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        pc = pcFactory.peerConnection(with: config, constraints: constraints, delegate: nil)!
        sendStream = pcFactory.mediaStream(withStreamId: "mediasoup-send")

        remoteSdp = RemoteSdp(
            iceParameters: iceParameters,
            iceCandidates: iceCandidates,
            dtlsParameters: dtlsParameters
        )

        super.init()
        pc.delegate = self
    }

    func close() {
        pc.close()
    }

    var stats: String {
        // Synchronous stats not easily available; return empty for now
        return "[]"
    }

    /// Log outbound RTP stats to diagnose audio flow
    func logSenderStats() {
        pc.statistics { report in
            for (_, stat) in report.statistics {
                let type = stat.type
                if type == "outbound-rtp" {
                    let kind = stat.values["kind"] as? String ?? "?"
                    let bytesSent = stat.values["bytesSent"] as? NSNumber ?? 0
                    let packetsSent = stat.values["packetsSent"] as? NSNumber ?? 0
                    let codec = stat.values["codecId"] as? String ?? "?"
                    let ssrc = stat.values["ssrc"] as? NSNumber ?? 0
                    let active = stat.values["active"] as? NSNumber ?? 0
                    let muted = stat.values["muted"] as? NSNumber ?? 0
                    print("[Mediasoup.Handler] 📊 STATS outbound-rtp: kind=\(kind), bytesSent=\(bytesSent), packetsSent=\(packetsSent), ssrc=\(ssrc), active=\(active), muted=\(muted), codec=\(codec)")
                } else if type == "remote-inbound-rtp" {
                    let packetsReceived = stat.values["packetsReceived"] as? NSNumber ?? 0
                    let packetsLost = stat.values["packetsLost"] as? NSNumber ?? 0
                    let roundTripTime = stat.values["roundTripTime"] as? NSNumber ?? 0
                    print("[Mediasoup.Handler] 📊 STATS remote-inbound-rtp: received=\(packetsReceived), lost=\(packetsLost), rtt=\(roundTripTime)")
                } else if type == "transport" {
                    let bytesSent = stat.values["bytesSent"] as? NSNumber ?? 0
                    let bytesReceived = stat.values["bytesReceived"] as? NSNumber ?? 0
                    let dtlsState = stat.values["dtlsState"] as? String ?? "?"
                    print("[Mediasoup.Handler] 📊 STATS transport: bytesSent=\(bytesSent), bytesReceived=\(bytesReceived), dtlsState=\(dtlsState)")
                }
            }
        }
    }

    // MARK: - Send

    func send(
        track: RTCMediaStreamTrack,
        encodings: [RTCRtpEncodingParameters]?,
        codecOptions: String?,
        codec: String?
    ) async throws -> SendResult {
        let kind = track.kind  // "audio" or "video"
        print("[Mediasoup.Handler] 🔵 send() - kind: \(kind)")

        // Add transceiver with sendonly direction
        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .sendOnly
        transceiverInit.streamIds = [sendStream.streamId]

        if let encs = encodings, !encs.isEmpty {
            transceiverInit.sendEncodings = encs
        }

        guard let transceiver = pc.addTransceiver(with: track, init: transceiverInit) else {
            throw MediasoupError.invalidState("Failed to add transceiver")
        }

        // Create offer
        let offer = try await createOffer()
        let localSdpStr = offer.sdp

        // Get local RTP capabilities from the offer SDP
        let nativeRtpCaps = SdpExtractor.extractRtpCapabilities(sdp: localSdpStr)

        // Compute extended caps for send direction
        _ = ORTC.getExtendedRtpCapabilities(
            localCaps: nativeRtpCaps,
            remoteCaps: ORTC.getRecvRtpCapabilities(extendedRtpCapabilities: extendedRtpCapabilities)
        )

        // Build sending RTP parameters
        var sendingRtpParameters = ORTC.getSendingRtpParameters(
            kind: kind,
            extendedRtpCapabilities: extendedRtpCapabilities
        )

        // Reduce codecs to just the first codec (+ its RTX), matching
        // the reference mediasoup-client behavior.
        sendingRtpParameters.codecs = ORTC.reduceCodecs(sendingRtpParameters.codecs)

        // Build remote answer RTP parameters
        var sendingRemoteRtpParameters = ORTC.getSendingRemoteRtpParameters(
            kind: kind,
            extendedRtpCapabilities: extendedRtpCapabilities
        )
        sendingRemoteRtpParameters.codecs = ORTC.reduceCodecs(sendingRemoteRtpParameters.codecs)

        // Set local description first (matching reference mediasoup-client ordering)
        try await setLocalDescription(offer)

        // Setup transport on first send/recv (AFTER setLocalDescription, as in reference)
        if !transportReady {
            try await setupTransport(localSdp: localSdpStr)
        }

        // Get the mid from the transceiver
        let mid = transceiver.mid
        guard !mid.isEmpty else {
            throw MediasoupError.invalidState("Transceiver has no mid after setLocalDescription")
        }

        let localId = mid

        // Re-parse local description to get final SDP
        guard let localDesc = pc.localDescription else {
            throw MediasoupError.invalidState("No local description after setLocalDescription")
        }
        let finalLocalSdp = localDesc.sdp

        // Set mid
        sendingRtpParameters.mid = localId

        // Extract CNAME
        sendingRtpParameters.rtcp = RtcpParam(
            cname: SdpExtractor.extractCname(sdp: finalLocalSdp),
            reducedSize: true
        )

        // Extract encodings (SSRCs) from the media section
        let mediaIndex = pc.transceivers.firstIndex(where: { $0.mid == mid }) ?? 0
        let sdpEncodings = SdpExtractor.extractEncodings(sdp: finalLocalSdp, mediaIndex: mediaIndex)

        var rtpEncodings: [RtpEncodingParam] = []
        for enc in sdpEncodings {
            var rtpEnc = RtpEncodingParam(ssrc: enc.ssrc)
            if let rtx = enc.rtxSsrc, sendingRtpParameters.codecs.count > 1 {
                rtpEnc.rtx = RtxSsrc(ssrc: rtx)
            }
            rtpEncodings.append(rtpEnc)
        }
        sendingRtpParameters.encodings = rtpEncodings

        // Extract extmap lines from offer for matching in the answer
        let offerExtmapLines = extractExtmapLines(sdp: finalLocalSdp, mediaIndex: mediaIndex)

        // Build remote answer SDP
        let offerPayloads = extractPayloads(sdp: finalLocalSdp, mediaIndex: mediaIndex)

        remoteSdp.addSendMediaSection(
            mid: localId,
            kind: kind,
            offerPayloads: offerPayloads,
            answerRtpParameters: sendingRemoteRtpParameters,
            offerExtmapLines: offerExtmapLines
        )

        let answerSdp = remoteSdp.getSdp()
        print("[Mediasoup.Handler] 🔵 Answer SDP:\n\(answerSdp)")
        let answer = RTCSessionDescription(type: .answer, sdp: answerSdp)
        try await setRemoteDescription(answer)

        print("[Mediasoup.Handler] ✅ send() complete - PC signaling state: \(pc.signalingState.rawValue), ICE state: \(pc.iceConnectionState.rawValue), sender track enabled: \(transceiver.sender.track?.isEnabled ?? false)")

        // Store transceiver
        mapMidTransceiver[localId] = transceiver

        return SendResult(localId: localId, rtpParameters: sendingRtpParameters)
    }

    // MARK: - Receive

    func receive(
        trackId: String,
        kind: String,
        rtpParameters: MsRtpParameters
    ) async throws -> RecvResult {
        let localId = rtpParameters.mid ?? String(mapMidTransceiver.count)

        let streamId = rtpParameters.rtcp?.cname ?? "-"

        // Add media section to remote offer SDP
        remoteSdp.addRecvMediaSection(
            mid: localId,
            kind: kind,
            offerRtpParameters: rtpParameters,
            streamId: streamId,
            trackId: trackId
        )

        let offerSdp = remoteSdp.getSdp()
        let offer = RTCSessionDescription(type: .offer, sdp: offerSdp)

        try await setRemoteDescription(offer)

        let answer = try await createAnswer()

        if !transportReady {
            try await setupTransport(localSdp: answer.sdp)
        }

        try await setLocalDescription(answer)

        // Find the transceiver for this mid
        guard let transceiver = pc.transceivers.first(where: { $0.mid == localId }) else {
            throw MediasoupError.invalidState("Transceiver not found for mid \(localId)")
        }

        mapMidTransceiver[localId] = transceiver

        let track = transceiver.receiver.track!

        return RecvResult(localId: localId, track: track)
    }

    // MARK: - Stop sending/receiving

    func stopSending(localId: String) async throws {
        guard let transceiver = mapMidTransceiver[localId] else { return }
        transceiver.sender.track = nil
        pc.removeTrack(transceiver.sender)
        remoteSdp.closeMediaSection(mid: localId)

        let offer = try await createOffer()
        try await setLocalDescription(offer)

        let answer = RTCSessionDescription(type: .answer, sdp: remoteSdp.getSdp())
        try await setRemoteDescription(answer)
        mapMidTransceiver.removeValue(forKey: localId)
    }

    func stopReceiving(localId: String) async throws {
        remoteSdp.closeMediaSection(mid: localId)

        let offer = RTCSessionDescription(type: .offer, sdp: remoteSdp.getSdp())
        try await setRemoteDescription(offer)
        let answer = try await createAnswer()
        try await setLocalDescription(answer)
        mapMidTransceiver.removeValue(forKey: localId)
    }

    // MARK: - Update ICE servers

    func updateIceServers(_ iceServers: [RTCIceServer]) {
        let config = pc.configuration
        config.iceServers = iceServers
        pc.setConfiguration(config)
    }

    // MARK: - Private: WebRTC operations

    private func createOffer() async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { cont in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            pc.offer(for: constraints) { sdp, error in
                if let error = error {
                    cont.resume(throwing: MediasoupError.unknown(error))
                } else if let sdp = sdp {
                    cont.resume(returning: sdp)
                } else {
                    cont.resume(throwing: MediasoupError.invalidState("createOffer returned nil"))
                }
            }
        }
    }

    private func createAnswer() async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { cont in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            pc.answer(for: constraints) { sdp, error in
                if let error = error {
                    cont.resume(throwing: MediasoupError.unknown(error))
                } else if let sdp = sdp {
                    cont.resume(returning: sdp)
                } else {
                    cont.resume(throwing: MediasoupError.invalidState("createAnswer returned nil"))
                }
            }
        }
    }

    private func setLocalDescription(_ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(sdp) { error in
                if let error = error {
                    cont.resume(throwing: MediasoupError.unknown(error))
                } else {
                    cont.resume()
                }
            }
        }
    }

    private func setRemoteDescription(_ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(sdp) { error in
                if let error = error {
                    cont.resume(throwing: MediasoupError.unknown(error))
                } else {
                    cont.resume()
                }
            }
        }
    }

    // MARK: - Private: Transport setup

    private func setupTransport(localSdp: String) async throws {
        let dtlsParams = SdpExtractor.extractDtlsParameters(sdp: localSdp)
        print("[Mediasoup.Handler] 🔵 setupTransport - dtls fingerprints: \(dtlsParams.fingerprints.count), role: \(dtlsParams.role)")

        // Force client role
        var connDtls = dtlsParams
        connDtls.role = "client"

        // Update remote SDP role accordingly
        remoteSdp.updateDtlsRole("server")

        // Notify transport to connect (await acknowledgment like reference mediasoup-client)
        let dtlsJson = try JSON.stringify(connDtls)
        print("[Mediasoup.Handler] 🔵 setupTransport - calling onConnect with dtls: \(dtlsJson.prefix(200))")
        await onConnect?(dtlsJson)
        print("[Mediasoup.Handler] ✅ setupTransport - onConnect completed")

        transportReady = true
    }

    // MARK: - Private: SDP extraction helpers

    private func extractPayloads(sdp: String, mediaIndex: Int) -> String {
        let sdp = sdp.replacingOccurrences(of: "\r\n", with: "\n")
        let sections = sdp.split(separator: "\n").filter { $0.hasPrefix("m=") }
        guard mediaIndex < sections.count else { return "" }
        let mLine = String(sections[mediaIndex])

        // m=audio 9 UDP/TLS/RTP/SAVPF 111 63 9 102
        let parts = mLine.split(separator: " ")
        guard parts.count > 3 else { return "" }
        return parts[3...].joined(separator: " ")
    }

    private func extractExtmapLines(sdp: String, mediaIndex: Int) -> [String] {
        let sections = splitMediaSections(sdp)
        guard mediaIndex < sections.count else { return [] }
        let section = sections[mediaIndex]

        var result: [String] = []
        for line in section.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("a=extmap:") {
                result.append(String(l.dropFirst("a=extmap:".count)))
            }
        }
        return result
    }

    private func splitMediaSections(_ sdp: String) -> [String] {
        let sdp = sdp.replacingOccurrences(of: "\r\n", with: "\n")
        var sections: [String] = []
        var current = ""
        var inMedia = false

        for line in sdp.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = String(line)
            if l.hasPrefix("m=") {
                if inMedia { sections.append(current) }
                current = l + "\n"
                inMedia = true
            } else if inMedia {
                current += l + "\n"
            }
        }
        if inMedia { sections.append(current) }
        return sections
    }
}

// MARK: - RTCPeerConnectionDelegate

extension Handler: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("[Mediasoup.Handler] 🔵 Signaling state: \(stateChanged.rawValue)")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCPeerConnectionState) {
        let names = ["new", "connecting", "connected", "disconnected", "failed", "closed"]
        let name = stateChanged.rawValue < names.count ? names[Int(stateChanged.rawValue)] : "unknown(\(stateChanged.rawValue))"
        print("[Mediasoup.Handler] 🔵 PeerConnection state: \(name) (\(stateChanged.rawValue)) [ICE+DTLS]")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("[Mediasoup.Handler] 🔵 ICE gathering state: \(newState.rawValue)")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("[Mediasoup.Handler] 🔵 ICE candidate: \(candidate.sdp)")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("[Mediasoup.Handler] 🔵 ICE connection state: \(newState.rawValue)")
        let state: TransportConnectionState
        switch newState {
        case .new:          state = .new
        case .checking:     state = .checking
        case .connected:    state = .connected
        case .completed:    state = .completed
        case .failed:       state = .failed
        case .disconnected: state = .disconnected
        case .closed:       state = .closed
        case .count:        state = .new
        @unknown default:   state = .new
        }
        onConnectionStateChange?(state)
    }
}
