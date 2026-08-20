import Foundation

// MARK: - ORTC Logic
// Implements mediasoup ORTC capability negotiation (ported from mediasoup-client ortc.ts)

enum ORTC {

    // MARK: - Get Extended RTP Capabilities

    /// Match local RTP capabilities against remote (router) capabilities.
    static func getExtendedRtpCapabilities(
        localCaps: RtpCapabilities,
        remoteCaps: RtpCapabilities
    ) -> ExtendedRtpCapabilities {
        var extended = ExtendedRtpCapabilities()

        // Match media codecs (order preferred by remote/router).
        for remoteCodec in remoteCaps.codecs ?? [] {
            if isRtxCodec(remoteCodec.mimeType) { continue }

            guard let matchingLocal = (localCaps.codecs ?? []).first(where: { localCodec in
                matchCodecs(a: localCodec, b: remoteCodec, strict: true)
            }) else { continue }

            let extCodec = ExtendedRtpCodec(
                kind: remoteCodec.kind ?? matchingLocal.kind ?? "audio",
                mimeType: remoteCodec.mimeType,
                clockRate: remoteCodec.clockRate,
                channels: remoteCodec.channels,
                localPayloadType: matchingLocal.preferredPayloadType,
                localRtxPayloadType: nil,
                remotePayloadType: remoteCodec.preferredPayloadType,
                remoteRtxPayloadType: nil,
                localParameters: matchingLocal.parameters,
                remoteParameters: remoteCodec.parameters,
                rtcpFeedback: reduceRtcpFeedback(
                    a: matchingLocal.rtcpFeedback ?? [],
                    b: remoteCodec.rtcpFeedback ?? []
                )
            )
            extended.codecs.append(extCodec)
        }

        // Match RTX codecs.
        for i in 0..<extended.codecs.count {
            let extCodec = extended.codecs[i]

            let matchingLocalRtx = (localCaps.codecs ?? []).first { c in
                isRtxCodec(c.mimeType) && c.parameters?["apt"]?.intValue == extCodec.localPayloadType
            }
            let matchingRemoteRtx = (remoteCaps.codecs ?? []).first { c in
                isRtxCodec(c.mimeType) && c.parameters?["apt"]?.intValue == extCodec.remotePayloadType
            }

            if let localRtx = matchingLocalRtx, let remoteRtx = matchingRemoteRtx {
                extended.codecs[i].localRtxPayloadType = localRtx.preferredPayloadType
                extended.codecs[i].remoteRtxPayloadType = remoteRtx.preferredPayloadType
            }
        }

        // Match header extensions.
        for remoteExt in remoteCaps.headerExtensions ?? [] {
            guard let matchingLocal = (localCaps.headerExtensions ?? []).first(where: { localExt in
                matchHeaderExtensions(a: localExt, b: remoteExt)
            }) else { continue }

            let direction: String
            switch remoteExt.direction ?? "sendrecv" {
            case "sendrecv": direction = "sendrecv"
            case "recvonly": direction = "sendonly"
            case "sendonly": direction = "recvonly"
            case "inactive": direction = "inactive"
            default:         direction = "sendrecv"
            }

            let extExt = ExtendedRtpHeaderExtension(
                kind: remoteExt.kind,
                uri: remoteExt.uri,
                sendId: matchingLocal.preferredId,
                recvId: remoteExt.preferredId,
                encrypt: matchingLocal.preferredEncrypt ?? false,
                direction: direction
            )
            extended.headerExtensions.append(extExt)
        }

        return extended
    }

    // MARK: - Get Recv RTP Capabilities (for device.rtpCapabilities())

    static func getRecvRtpCapabilities(
        extendedRtpCapabilities: ExtendedRtpCapabilities
    ) -> RtpCapabilities {
        var codecs: [RtpCodecCapability] = []
        var headerExtensions: [RtpHeaderExtensionCapability] = []

        for ext in extendedRtpCapabilities.codecs {
            let codec = RtpCodecCapability(
                kind: ext.kind,
                mimeType: ext.mimeType,
                preferredPayloadType: ext.remotePayloadType,
                clockRate: ext.clockRate,
                channels: ext.channels,
                parameters: ext.localParameters,
                rtcpFeedback: ext.rtcpFeedback
            )
            codecs.append(codec)

            if let remoteRtxPt = ext.remoteRtxPayloadType {
                let rtxCodec = RtpCodecCapability(
                    kind: ext.kind,
                    mimeType: "\(ext.kind)/rtx",
                    preferredPayloadType: remoteRtxPt,
                    clockRate: ext.clockRate,
                    channels: nil,
                    parameters: ["apt": .int(ext.remotePayloadType)],
                    rtcpFeedback: []
                )
                codecs.append(rtxCodec)
            }
        }

        for ext in extendedRtpCapabilities.headerExtensions {
            if ext.direction != "sendrecv" && ext.direction != "recvonly" { continue }

            let headerExt = RtpHeaderExtensionCapability(
                kind: ext.kind,
                uri: ext.uri,
                preferredId: ext.recvId,
                preferredEncrypt: ext.encrypt,
                direction: ext.direction
            )
            headerExtensions.append(headerExt)
        }

        return RtpCapabilities(codecs: codecs, headerExtensions: headerExtensions)
    }

    // MARK: - Get Sending RTP Parameters

    /// Generate RTP parameters for sending a given media kind.
    /// NOTE: mid, encodings, and rtcp are left empty — filled later from local SDP.
    static func getSendingRtpParameters(
        kind: String,
        extendedRtpCapabilities: ExtendedRtpCapabilities
    ) -> MsRtpParameters {
        var codecs: [RtpCodecParameters] = []
        var headerExtensions: [RtpHeaderExtensionParam] = []

        for ext in extendedRtpCapabilities.codecs {
            if ext.kind != kind { continue }

            let codec = RtpCodecParameters(
                mimeType: ext.mimeType,
                payloadType: ext.localPayloadType,
                clockRate: ext.clockRate,
                channels: ext.channels,
                parameters: ext.localParameters,
                rtcpFeedback: ext.rtcpFeedback
            )
            codecs.append(codec)

            if let localRtxPt = ext.localRtxPayloadType {
                let rtxCodec = RtpCodecParameters(
                    mimeType: "\(ext.kind)/rtx",
                    payloadType: localRtxPt,
                    clockRate: ext.clockRate,
                    channels: nil,
                    parameters: ["apt": .int(ext.localPayloadType)],
                    rtcpFeedback: []
                )
                codecs.append(rtxCodec)
            }
        }

        for ext in extendedRtpCapabilities.headerExtensions {
            if let k = ext.kind, k != kind { continue }
            if ext.direction != "sendrecv" && ext.direction != "sendonly" { continue }

            let headerExt = RtpHeaderExtensionParam(
                uri: ext.uri,
                id: ext.sendId,
                encrypt: ext.encrypt
            )
            headerExtensions.append(headerExt)
        }

        return MsRtpParameters(
            mid: nil,
            codecs: codecs,
            headerExtensions: headerExtensions,
            encodings: [],
            rtcp: RtcpParam()
        )
    }

    // MARK: - Get Sending Remote RTP Parameters (for answer SDP)

    /// Generate RTP parameters suitable for the remote SDP answer.
    static func getSendingRemoteRtpParameters(
        kind: String,
        extendedRtpCapabilities: ExtendedRtpCapabilities
    ) -> MsRtpParameters {
        var codecs: [RtpCodecParameters] = []
        var headerExtensions: [RtpHeaderExtensionParam] = []

        for ext in extendedRtpCapabilities.codecs {
            if ext.kind != kind { continue }

            let codec = RtpCodecParameters(
                mimeType: ext.mimeType,
                payloadType: ext.localPayloadType,
                clockRate: ext.clockRate,
                channels: ext.channels,
                parameters: ext.remoteParameters,
                rtcpFeedback: ext.rtcpFeedback
            )
            codecs.append(codec)

            if let localRtxPt = ext.localRtxPayloadType {
                let rtxCodec = RtpCodecParameters(
                    mimeType: "\(ext.kind)/rtx",
                    payloadType: localRtxPt,
                    clockRate: ext.clockRate,
                    channels: nil,
                    parameters: ["apt": .int(ext.localPayloadType)],
                    rtcpFeedback: []
                )
                codecs.append(rtxCodec)
            }
        }

        for ext in extendedRtpCapabilities.headerExtensions {
            if let k = ext.kind, k != kind { continue }
            if ext.direction != "sendrecv" && ext.direction != "sendonly" { continue }

            let headerExt = RtpHeaderExtensionParam(
                uri: ext.uri,
                id: ext.sendId,
                encrypt: ext.encrypt
            )
            headerExtensions.append(headerExt)
        }

        // Reduce RTCP feedback: prefer transport-cc over goog-remb.
        let hasTransportCC = headerExtensions.contains {
            $0.uri == "http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01"
        }
        let hasAbsSendTime = headerExtensions.contains {
            $0.uri == "http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time"
        }

        for i in 0..<codecs.count {
            if hasTransportCC {
                codecs[i].rtcpFeedback = codecs[i].rtcpFeedback?.filter { $0.type != "goog-remb" }
            } else if hasAbsSendTime {
                codecs[i].rtcpFeedback = codecs[i].rtcpFeedback?.filter { $0.type != "transport-cc" }
            } else {
                codecs[i].rtcpFeedback = codecs[i].rtcpFeedback?.filter {
                    $0.type != "transport-cc" && $0.type != "goog-remb"
                }
            }
        }

        return MsRtpParameters(
            mid: nil,
            codecs: codecs,
            headerExtensions: headerExtensions,
            encodings: [],
            rtcp: RtcpParam()
        )
    }

    // MARK: - Reduce Codecs

    /// Reduce codecs to only include the first one (and its RTX) or a matching codec.
    static func reduceCodecs(
        _ codecs: [RtpCodecParameters],
        capCodec: RtpCodecCapability? = nil
    ) -> [RtpCodecParameters] {
        guard !codecs.isEmpty else { return [] }

        if let capCodec = capCodec {
            for idx in 0..<codecs.count {
                if matchCodecParams(a: codecs[idx], b: capCodec) {
                    var result = [codecs[idx]]
                    if idx + 1 < codecs.count && isRtxCodec(codecs[idx + 1].mimeType) {
                        result.append(codecs[idx + 1])
                    }
                    return result
                }
            }
            return [codecs[0]]
        } else {
            var result = [codecs[0]]
            if codecs.count > 1 && isRtxCodec(codecs[1].mimeType) {
                result.append(codecs[1])
            }
            return result
        }
    }

    // MARK: - canSend

    static func canSend(kind: String, extendedCaps: ExtendedRtpCapabilities) -> Bool {
        return extendedCaps.codecs.contains { $0.kind == kind }
    }

    // MARK: - Private helpers

    private static func isRtxCodec(_ mimeType: String) -> Bool {
        mimeType.lowercased().hasSuffix("/rtx")
    }

    private static func matchCodecs(a: RtpCodecCapability, b: RtpCodecCapability, strict: Bool) -> Bool {
        let aMime = a.mimeType.lowercased()
        let bMime = b.mimeType.lowercased()
        if aMime != bMime { return false }
        if a.clockRate != b.clockRate { return false }
        if a.channels != b.channels { return false }

        if strict {
            switch aMime {
            case "video/h264":
                let aPM = a.parameters?["packetization-mode"]?.intValue ?? 0
                let bPM = b.parameters?["packetization-mode"]?.intValue ?? 0
                if aPM != bPM { return false }
                let aPLI = a.parameters?["profile-level-id"]?.stringValue?.lowercased() ?? "42e01f"
                let bPLI = b.parameters?["profile-level-id"]?.stringValue?.lowercased() ?? "42e01f"
                // Compare profile (first 4 hex chars)
                if aPLI.prefix(4) != bPLI.prefix(4) { return false }
            case "video/vp9":
                let aPI = a.parameters?["profile-id"]?.intValue ?? 0
                let bPI = b.parameters?["profile-id"]?.intValue ?? 0
                if aPI != bPI { return false }
            default:
                break
            }
        }
        return true
    }

    private static func matchCodecParams(a: RtpCodecParameters, b: RtpCodecCapability) -> Bool {
        let aMime = a.mimeType.lowercased()
        let bMime = b.mimeType.lowercased()
        if aMime != bMime { return false }
        if a.clockRate != b.clockRate { return false }
        return true
    }

    private static func matchHeaderExtensions(
        a: RtpHeaderExtensionCapability,
        b: RtpHeaderExtensionCapability
    ) -> Bool {
        if let ak = a.kind, let bk = b.kind, ak != bk { return false }
        if a.uri != b.uri { return false }
        return true
    }

    private static func reduceRtcpFeedback(a: [RtcpFeedback], b: [RtcpFeedback]) -> [RtcpFeedback] {
        var result: [RtcpFeedback] = []
        for aFb in a {
            // Treat nil and "" as equivalent for parameter matching (server may send "" where local has nil)
            if b.contains(where: { $0.type == aFb.type && ($0.parameter ?? "") == (aFb.parameter ?? "") }) {
                result.append(aFb)
            }
        }
        return result
    }
}
