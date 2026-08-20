import Foundation

// MARK: - SDP Parser
// Extracts structured data from SDP text.

enum SdpExtractor {

    /// Extract native RTP capabilities from a local offer SDP.
    static func extractRtpCapabilities(sdp: String) -> RtpCapabilities {
        let sections = splitMediaSections(sdp: sdp)
        var codecsMap = [Int: RtpCodecCapability]()
        var headerExtMap = [Int: RtpHeaderExtensionCapability]()

        for section in sections {
            guard let kind = mediaKind(section) else { continue }

            // Parse a=rtpmap lines
            for line in lines(section, prefix: "a=rtpmap:") {
                // a=rtpmap:111 opus/48000/2
                let parts = line.split(separator: " ", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let pt = Int(parts[0]) ?? 0
                let codecParts = parts[1].split(separator: "/")
                let codecName = String(codecParts[0])
                let clockRate = codecParts.count > 1 ? (Int(codecParts[1]) ?? 0) : 0
                let channels = codecParts.count > 2 ? Int(codecParts[2]) : nil

                let codec = RtpCodecCapability(
                    kind: kind,
                    mimeType: "\(kind)/\(codecName)",
                    preferredPayloadType: pt,
                    clockRate: clockRate,
                    channels: channels,
                    parameters: [:],
                    rtcpFeedback: []
                )
                codecsMap[pt] = codec
            }

            // Parse a=fmtp lines
            for line in lines(section, prefix: "a=fmtp:") {
                // a=fmtp:111 minptime=10;useinbandfec=1
                let parts = line.split(separator: " ", maxSplits: 1)
                guard parts.count == 2, let pt = Int(parts[0]) else { continue }
                let params = parseFormatParams(String(parts[1]))
                codecsMap[pt]?.parameters = params
            }

            // Parse a=rtcp-fb lines
            for line in lines(section, prefix: "a=rtcp-fb:") {
                // a=rtcp-fb:111 transport-cc
                // a=rtcp-fb:* nack
                let parts = line.split(separator: " ", maxSplits: 2)
                guard !parts.isEmpty else { continue }
                let fbType = parts.count > 1 ? String(parts[1]) : ""
                let fbParam = parts.count > 2 ? String(parts[2]) : nil

                let feedback = RtcpFeedback(type: fbType, parameter: fbParam)

                if parts[0] == "*" {
                    for pt in codecsMap.keys {
                        if let k = codecsMap[pt]?.kind, k == kind,
                           !isRtxCodec(codecsMap[pt]?.mimeType ?? "") {
                            codecsMap[pt]?.rtcpFeedback?.append(feedback)
                        }
                    }
                } else if let pt = Int(parts[0]) {
                    codecsMap[pt]?.rtcpFeedback?.append(feedback)
                }
            }

            // Parse a=extmap lines
            for line in lines(section, prefix: "a=extmap:") {
                // a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level
                let parts = line.split(separator: " ", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let idStr = parts[0].split(separator: "/").first ?? parts[0]
                guard let id = Int(idStr) else { continue }
                let uri = String(parts[1])

                if let existing = headerExtMap[id] {
                    // Same extmap ID in different media section → set kind to nil
                    // (applies to both audio and video), matching reference mediasoup-client
                    if existing.kind != kind {
                        headerExtMap[id]?.kind = nil
                    }
                } else {
                    let ext = RtpHeaderExtensionCapability(
                        kind: kind,
                        uri: uri,
                        preferredId: id,
                        preferredEncrypt: false,
                        direction: "sendrecv"
                    )
                    headerExtMap[id] = ext
                }
            }
        }

        return RtpCapabilities(
            codecs: Array(codecsMap.values).sorted { $0.preferredPayloadType < $1.preferredPayloadType },
            headerExtensions: Array(headerExtMap.values).sorted { $0.preferredId < $1.preferredId }
        )
    }

    /// Extract DTLS parameters from a local SDP.
    static func extractDtlsParameters(sdp: String) -> DtlsParametersJSON {
        let sdp = sdp.replacingOccurrences(of: "\r\n", with: "\n")
        var setup: String?
        var fingerprint: (algorithm: String, value: String)?

        // Check session-level first
        for line in sdp.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("a=setup:") && setup == nil {
                setup = String(l.dropFirst("a=setup:".count))
            }
            if l.hasPrefix("a=fingerprint:") && fingerprint == nil {
                let parts = l.dropFirst("a=fingerprint:".count).split(separator: " ", maxSplits: 1)
                if parts.count == 2 {
                    fingerprint = (String(parts[0]), String(parts[1]))
                }
            }
        }

        let role: String
        switch setup {
        case "active":  role = "client"
        case "passive": role = "server"
        default:        role = "auto"
        }

        return DtlsParametersJSON(
            fingerprints: fingerprint.map { [FingerprintJSON(algorithm: $0.algorithm, value: $0.value)] } ?? [],
            role: role
        )
    }

    /// Extract CNAME from the first a=ssrc line with cname attribute.
    static func extractCname(sdp: String) -> String {
        let sdp = sdp.replacingOccurrences(of: "\r\n", with: "\n")
        for line in sdp.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // a=ssrc:1234 cname:localcname
            if l.hasPrefix("a=ssrc:") && l.contains(" cname:") {
                if let cnameRange = l.range(of: " cname:") {
                    return String(l[cnameRange.upperBound...])
                }
            }
        }
        return ""
    }

    /// Extract SSRCs and RTX SSRCs from a media section of the local offer SDP.
    /// Returns array of (ssrc, rtxSsrc?) pairs.
    static func extractEncodings(sdp: String, mediaIndex: Int) -> [(ssrc: UInt32, rtxSsrc: UInt32?)] {
        let sections = splitMediaSections(sdp: sdp)
        guard mediaIndex < sections.count else { return [] }
        let section = sections[mediaIndex]

        var ssrcs = Set<UInt32>()
        var ssrcToRtxSsrc = [(UInt32, UInt32?)]()

        // Collect all SSRCs from a=ssrc lines
        for line in lines(section, prefix: "a=ssrc:") {
            if let ssrc = UInt32(line.split(separator: " ").first ?? "") {
                ssrcs.insert(ssrc)
            }
        }

        // Check FID groups for RTX
        for line in lines(section, prefix: "a=ssrc-group:FID ") {
            let parts = line.split(separator: " ")
            if parts.count >= 2, let ssrc = UInt32(parts[0]), let rtxSsrc = UInt32(parts[1]) {
                ssrcs.remove(ssrc)
                ssrcs.remove(rtxSsrc)
                ssrcToRtxSsrc.append((ssrc, rtxSsrc))
            }
        }

        // Remaining SSRCs without RTX
        for ssrc in ssrcs.sorted() {
            ssrcToRtxSsrc.append((ssrc, nil))
        }

        return ssrcToRtxSsrc
    }

    // MARK: - Private helpers

    /// Split SDP into media sections. Returns sections starting after each "m=" line.
    private static func splitMediaSections(sdp: String) -> [String] {
        // Normalize CRLF→LF: Swift treats \r\n as a single grapheme cluster,
        // so split(separator: "\n") won't split on CRLF boundaries.
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

    /// Get lines with a given prefix, returning the content after the prefix.
    private static func lines(_ section: String, prefix: String) -> [String] {
        var result: [String] = []
        for line in section.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix(prefix) {
                result.append(String(l.dropFirst(prefix.count)))
            }
        }
        return result
    }

    /// Parse format parameters string like "minptime=10;useinbandfec=1"
    private static func parseFormatParams(_ str: String) -> [String: JSONValue] {
        var params = [String: JSONValue]()
        for part in str.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            let key = kv[0].trimmingCharacters(in: .whitespaces)
            let value = kv.count > 1 ? kv[1].trimmingCharacters(in: .whitespaces) : ""
            if let intVal = Int(value) {
                params[key] = .int(intVal)
            } else {
                params[key] = .string(value)
            }
        }
        return params
    }

    private static func mediaKind(_ section: String) -> String? {
        if section.hasPrefix("m=audio") { return "audio" }
        if section.hasPrefix("m=video") { return "video" }
        return nil
    }

    private static func isRtxCodec(_ mimeType: String) -> Bool {
        mimeType.lowercased().hasSuffix("/rtx")
    }
}
