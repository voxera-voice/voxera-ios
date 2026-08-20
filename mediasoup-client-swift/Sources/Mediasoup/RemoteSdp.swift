import Foundation

// MARK: - Remote SDP Builder
// Constructs remote SDP strings for mediasoup signaling.
// - For sending: builds a remote ANSWER SDP in response to the local PC's OFFER.
// - For receiving: builds a remote OFFER SDP that the local PC will ANSWER.

final class RemoteSdp {
    private let iceParameters: IceParametersJSON
    private let iceCandidates: [IceCandidateJSON]
    private let dtlsParameters: DtlsParametersJSON
    private var dtlsRole: String  // "client" or "server"

    private var mediaSections: [MediaSectionSdp] = []
    private var sessionVersion: Int = 0

    init(
        iceParameters: IceParametersJSON,
        iceCandidates: [IceCandidateJSON],
        dtlsParameters: DtlsParametersJSON
    ) {
        self.iceParameters = iceParameters
        self.iceCandidates = iceCandidates
        self.dtlsParameters = dtlsParameters
        self.dtlsRole = dtlsParameters.role ?? "auto"
    }

    func updateDtlsRole(_ role: String) {
        dtlsRole = role
    }

    // MARK: - Send (build answer for local offer)

    func addSendMediaSection(
        mid: String,
        kind: String,
        offerPayloads: String,
        answerRtpParameters: MsRtpParameters,
        offerExtmapLines: [String],
        extmapAllowMixed: Bool = true
    ) {
        let section = buildAnswerMediaSection(
            mid: mid,
            kind: kind,
            payloads: filterPayloads(offerPayloads, answerRtpParameters),
            direction: "recvonly",
            rtpParameters: answerRtpParameters,
            offerExtmapLines: offerExtmapLines,
            extmapAllowMixed: extmapAllowMixed
        )
        mediaSections.append(section)
    }

    // MARK: - Receive (build offer for local answer)

    func addRecvMediaSection(
        mid: String,
        kind: String,
        offerRtpParameters: MsRtpParameters,
        streamId: String,
        trackId: String
    ) {
        let section = buildOfferMediaSection(
            mid: mid,
            kind: kind,
            rtpParameters: offerRtpParameters,
            streamId: streamId,
            trackId: trackId
        )
        mediaSections.append(section)
    }

    // MARK: - Close a media section (set port=0)

    func closeMediaSection(mid: String) {
        guard let idx = mediaSections.firstIndex(where: { $0.mid == mid }) else { return }
        mediaSections[idx].closed = true
    }

    // MARK: - Get full SDP string

    func getSdp() -> String {
        sessionVersion += 1

        let fingerprint = dtlsParameters.fingerprints.last
        let setup: String
        switch dtlsRole {
        case "client": setup = "active"    // remote is DTLS client → active (initiates)
        case "server": setup = "passive"   // remote is DTLS server → passive (waits)
        default:       setup = "actpass"
        }

        let bundleMids = mediaSections.filter { !$0.closed }.map(\.mid).joined(separator: " ")

        var sdp = ""
        sdp += "v=0\r\n"
        sdp += "o=- 10000 \(sessionVersion) IN IP4 0.0.0.0\r\n"
        sdp += "s=-\r\n"
        sdp += "t=0 0\r\n"
        sdp += "a=ice-options:ice2\r\n"

        if iceParameters.iceLite == true {
            sdp += "a=ice-lite\r\n"
        }
        if let fp = fingerprint {
            sdp += "a=fingerprint:\(fp.algorithm) \(fp.value)\r\n"
        }
        sdp += "a=msid-semantic: WMS *\r\n"
        sdp += "a=group:BUNDLE \(bundleMids)\r\n"

        for section in mediaSections {
            if section.closed {
                sdp += buildClosedSection(mid: section.mid, kind: section.kind)
            } else {
                sdp += buildActiveSection(section: section, setup: setup)
            }
        }

        return sdp
    }

    // MARK: - Private

    private func buildActiveSection(section: MediaSectionSdp, setup: String) -> String {
        var s = ""
        s += "m=\(section.kind) 7 UDP/TLS/RTP/SAVPF \(section.payloads)\r\n"
        s += "c=IN IP4 127.0.0.1\r\n"
        s += "a=mid:\(section.mid)\r\n"
        s += "a=ice-ufrag:\(iceParameters.usernameFragment)\r\n"
        s += "a=ice-pwd:\(iceParameters.password)\r\n"

        for candidate in iceCandidates {
            var candidateLine = "a=candidate:\(candidate.foundation) 1 \(candidate.protocol) \(candidate.priority) \(candidate.effectiveIP) \(candidate.port) typ \(candidate.type)"
            if candidate.protocol.lowercased() == "tcp", let tcpType = candidate.tcpType {
                candidateLine += " tcptype \(tcpType)"
            }
            s += candidateLine + "\r\n"
        }
        s += "a=end-of-candidates\r\n"
        s += "a=ice-options:renomination\r\n"
        s += "a=setup:\(setup)\r\n"
        s += "a=\(section.direction)\r\n"

        s += section.codecLines
        s += "a=rtcp-mux\r\n"
        s += "a=rtcp-rsize\r\n"

        return s
    }

    private func buildClosedSection(mid: String, kind: String) -> String {
        var s = ""
        s += "m=\(kind) 0 UDP/TLS/RTP/SAVPF 0\r\n"
        s += "c=IN IP4 127.0.0.1\r\n"
        s += "a=mid:\(mid)\r\n"
        s += "a=inactive\r\n"
        return s
    }

    private func buildAnswerMediaSection(
        mid: String,
        kind: String,
        payloads: String,
        direction: String,
        rtpParameters: MsRtpParameters,
        offerExtmapLines: [String],
        extmapAllowMixed: Bool = false
    ) -> MediaSectionSdp {
        var codecLines = ""

        for codec in rtpParameters.codecs {
            let codecName = codecShortName(codec.mimeType)
            if let ch = codec.channels, ch > 1 {
                codecLines += "a=rtpmap:\(codec.payloadType) \(codecName)/\(codec.clockRate)/\(ch)\r\n"
            } else {
                codecLines += "a=rtpmap:\(codec.payloadType) \(codecName)/\(codec.clockRate)\r\n"
            }

            let fmtpStr = formatParams(codec.parameters)
            if !fmtpStr.isEmpty {
                codecLines += "a=fmtp:\(codec.payloadType) \(fmtpStr)\r\n"
            }

            for fb in codec.rtcpFeedback ?? [] {
                if let param = fb.parameter, !param.isEmpty {
                    codecLines += "a=rtcp-fb:\(codec.payloadType) \(fb.type) \(param)\r\n"
                } else {
                    codecLines += "a=rtcp-fb:\(codec.payloadType) \(fb.type)\r\n"
                }
            }
        }

        // Request 20ms Opus frames so the packet rate is high enough for
        // mediasoup's AudioLevelObserver (needs ≥10 packets per 250ms interval).
        if kind == "audio" {
            codecLines += "a=ptime:20\r\n"
        }

        // Use extension IDs from the offer (must match what local PC offered)
        let offerUris = Set((rtpParameters.headerExtensions ?? []).map(\.uri))
        for extLine in offerExtmapLines {
            // extLine is like "1 urn:ietf:..." — include only matched extensions
            let parts = extLine.split(separator: " ", maxSplits: 1)
            if parts.count == 2, offerUris.contains(String(parts[1])) {
                codecLines += "a=extmap:\(extLine)\r\n"
            }
        }

        // Include extmap-allow-mixed if requested (matches reference mediasoup-client)
        if extmapAllowMixed {
            codecLines += "a=extmap-allow-mixed\r\n"
        }

        return MediaSectionSdp(
            mid: mid,
            kind: kind,
            payloads: payloads,
            direction: direction,
            codecLines: codecLines,
            closed: false
        )
    }

    private func buildOfferMediaSection(
        mid: String,
        kind: String,
        rtpParameters: MsRtpParameters,
        streamId: String,
        trackId: String
    ) -> MediaSectionSdp {
        var codecLines = ""

        for codec in rtpParameters.codecs {
            let codecName = codecShortName(codec.mimeType)
            if let ch = codec.channels, ch > 1 {
                codecLines += "a=rtpmap:\(codec.payloadType) \(codecName)/\(codec.clockRate)/\(ch)\r\n"
            } else {
                codecLines += "a=rtpmap:\(codec.payloadType) \(codecName)/\(codec.clockRate)\r\n"
            }

            let fmtpStr = formatParams(codec.parameters)
            if !fmtpStr.isEmpty {
                codecLines += "a=fmtp:\(codec.payloadType) \(fmtpStr)\r\n"
            }

            for fb in codec.rtcpFeedback ?? [] {
                if let param = fb.parameter, !param.isEmpty {
                    codecLines += "a=rtcp-fb:\(codec.payloadType) \(fb.type) \(param)\r\n"
                } else {
                    codecLines += "a=rtcp-fb:\(codec.payloadType) \(fb.type)\r\n"
                }
            }
        }

        // Header extensions
        for ext in rtpParameters.headerExtensions ?? [] {
            codecLines += "a=extmap:\(ext.id) \(ext.uri)\r\n"
        }

        // Extmap-allow-mixed (for recv)
        codecLines += "a=extmap-allow-mixed\r\n"

        // MSID
        codecLines += "a=msid:\(streamId) \(trackId)\r\n"

        // SSRCs
        let encodings = rtpParameters.encodings ?? []
        if let enc = encodings.first, let ssrc = enc.ssrc {
            let cname = rtpParameters.rtcp?.cname ?? "mediasoup-client"
            codecLines += "a=ssrc:\(ssrc) cname:\(cname)\r\n"
            codecLines += "a=ssrc:\(ssrc) msid:\(streamId) \(trackId)\r\n"

            if let rtxSsrc = enc.rtx?.ssrc {
                codecLines += "a=ssrc:\(rtxSsrc) cname:\(cname)\r\n"
                codecLines += "a=ssrc:\(rtxSsrc) msid:\(streamId) \(trackId)\r\n"
                codecLines += "a=ssrc-group:FID \(ssrc) \(rtxSsrc)\r\n"
            }
        }

        let payloads = rtpParameters.codecs.map { String($0.payloadType) }.joined(separator: " ")

        return MediaSectionSdp(
            mid: mid,
            kind: kind,
            payloads: payloads,
            direction: "sendonly",
            codecLines: codecLines,
            closed: false
        )
    }

    private func filterPayloads(_ offerPayloads: String, _ params: MsRtpParameters) -> String {
        let allowed = Set(params.codecs.map { $0.payloadType })
        let filtered = offerPayloads.split(separator: " ")
            .filter { allowed.contains(Int($0) ?? -1) }
            .joined(separator: " ")
        return filtered.isEmpty ? offerPayloads : filtered
    }

    private func codecShortName(_ mimeType: String) -> String {
        // "audio/opus" → "opus"
        let parts = mimeType.split(separator: "/")
        return parts.count > 1 ? String(parts[1]) : mimeType
    }

    private func formatParams(_ params: [String: JSONValue]?) -> String {
        guard let params = params, !params.isEmpty else { return "" }
        return params.sorted(by: { $0.key < $1.key }).map { key, value in
            switch value {
            case .int(let v):    return "\(key)=\(v)"
            case .double(let v): return "\(key)=\(v)"
            case .string(let v): return "\(key)=\(v)"
            case .bool(let v):   return "\(key)=\(v ? 1 : 0)"
            }
        }.joined(separator: ";")
    }
}

// MARK: - Internal media section data

private struct MediaSectionSdp {
    let mid: String
    let kind: String
    let payloads: String
    let direction: String
    let codecLines: String
    var closed: Bool
}
