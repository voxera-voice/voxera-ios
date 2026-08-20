import Foundation

// MARK: - JSON Codable types for mediasoup signaling

/// A flexible JSON value type that handles mixed string/number codec parameters.
enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(v)
        case .string(let v): return Int(v)
        default: return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        default: return nil
        }
    }
}

// MARK: - RTP Capabilities (from router / device)

struct RtpCodecCapability: Codable {
    var kind: String?
    var mimeType: String
    var preferredPayloadType: Int
    var clockRate: Int
    var channels: Int?
    var parameters: [String: JSONValue]?
    var rtcpFeedback: [RtcpFeedback]?
}

struct RtpHeaderExtensionCapability: Codable {
    var kind: String?
    var uri: String
    var preferredId: Int
    var preferredEncrypt: Bool?
    var direction: String?
}

struct RtpCapabilities: Codable {
    var codecs: [RtpCodecCapability]?
    var headerExtensions: [RtpHeaderExtensionCapability]?
}

// MARK: - RTP Parameters (for produce/consume)

struct RtpCodecParameters: Codable {
    var mimeType: String
    var payloadType: Int
    var clockRate: Int
    var channels: Int?
    var parameters: [String: JSONValue]?
    var rtcpFeedback: [RtcpFeedback]?
}

struct RtpHeaderExtensionParam: Codable {
    var uri: String
    var id: Int
    var encrypt: Bool?
    var parameters: [String: JSONValue]?
}

struct RtpEncodingParam: Codable {
    var ssrc: UInt32?
    var rid: String?
    var rtx: RtxSsrc?
    var dtx: Bool?
    var scalabilityMode: String?
    var active: Bool?
    var maxBitrate: Int?
    var scaleResolutionDownBy: Double?
}

struct RtxSsrc: Codable {
    var ssrc: UInt32
}

struct RtcpParam: Codable {
    var cname: String?
    var reducedSize: Bool?
}

struct MsRtpParameters: Codable {
    var mid: String?
    var codecs: [RtpCodecParameters]
    var headerExtensions: [RtpHeaderExtensionParam]?
    var encodings: [RtpEncodingParam]?
    var rtcp: RtcpParam?
    var msid: String?
}

struct RtcpFeedback: Codable, Equatable {
    var type: String
    var parameter: String?

    // Always encode parameter (as "" if nil) to match JS mediasoup-client JSON output
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(parameter ?? "", forKey: .parameter)
    }
}

// MARK: - Transport parameters

struct IceParametersJSON: Codable {
    var usernameFragment: String
    var password: String
    var iceLite: Bool?
}

struct IceCandidateJSON: Codable {
    var foundation: String
    var priority: UInt32
    var ip: String?
    var address: String?
    var port: UInt16
    var type: String
    var `protocol`: String
    var tcpType: String?

    var effectiveIP: String { address ?? ip ?? "0.0.0.0" }
}

struct DtlsParametersJSON: Codable {
    var fingerprints: [FingerprintJSON]
    var role: String?
}

struct FingerprintJSON: Codable {
    var algorithm: String
    var value: String
}

// MARK: - Extended RTP Capabilities (internal)

struct ExtendedRtpCodec {
    var kind: String
    var mimeType: String
    var clockRate: Int
    var channels: Int?
    var localPayloadType: Int
    var localRtxPayloadType: Int?
    var remotePayloadType: Int
    var remoteRtxPayloadType: Int?
    var localParameters: [String: JSONValue]?
    var remoteParameters: [String: JSONValue]?
    var rtcpFeedback: [RtcpFeedback]
}

struct ExtendedRtpHeaderExtension {
    var kind: String?
    var uri: String
    var sendId: Int
    var recvId: Int
    var encrypt: Bool
    var direction: String
}

struct ExtendedRtpCapabilities {
    var codecs: [ExtendedRtpCodec] = []
    var headerExtensions: [ExtendedRtpHeaderExtension] = []
}

// MARK: - JSON Helpers

enum JSON {
    static func parse<T: Decodable>(_ string: String, as type: T.Type) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw MediasoupError.invalidParameters("Invalid UTF-8 string")
        }
        return try JSONDecoder().decode(type, from: data)
    }

    static func stringify<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let str = String(data: data, encoding: .utf8) else {
            throw MediasoupError.invalidParameters("JSON encode failed")
        }
        return str
    }

    static func parseDict(_ string: String) throws -> [String: Any] {
        guard let data = string.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediasoupError.invalidParameters("JSON parse failed")
        }
        return dict
    }

    static func stringifyAny(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let str = String(data: data, encoding: .utf8) else {
            throw MediasoupError.invalidParameters("JSON encode failed")
        }
        return str
    }
}
