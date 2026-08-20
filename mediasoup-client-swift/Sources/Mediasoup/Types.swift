import Foundation
import WebRTC

// MARK: - MediaKind

public enum MediaKind: String, Codable {
    case audio
    case video
}

// MARK: - TransportConnectionState

public enum TransportConnectionState: String {
    case new
    case checking
    case connected
    case completed
    case failed
    case disconnected
    case closed
}

// MARK: - ICETransportPolicy

public enum ICETransportPolicy {
    case none
    case relay
    case noHost
    case all

    var rtcPolicy: RTCIceTransportPolicy {
        switch self {
        case .none:   return .none
        case .relay:  return .relay
        case .noHost: return .noHost
        case .all:    return .all
        }
    }
}

// MARK: - MediasoupError

public enum MediasoupError: Error, LocalizedError, CustomStringConvertible {
    case unsupported(String)
    case invalidState(String)
    case invalidParameters(String)
    case unknown(Error)
    
    public var description: String {
        switch self {
        case .unsupported(let msg):
            return "MediasoupError.unsupported: \(msg)"
        case .invalidState(let msg):
            return "MediasoupError.invalidState: \(msg)"
        case .invalidParameters(let msg):
            return "MediasoupError.invalidParameters: \(msg)"
        case .unknown(let error):
            return "MediasoupError.unknown: \(error.localizedDescription)"
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - Transport Protocol

public protocol Transport: AnyObject {
    var id: String { get }
    var closed: Bool { get }
    var connectionState: TransportConnectionState { get }
    var appData: String { get }
    var stats: String { get }
    func close()
    func restartICE(with iceParameters: String) throws
    func updateICEServers(_ iceServers: String) throws
}

// MARK: - Delegates

public protocol TransportDelegate: AnyObject {
    func onConnect(transport: any Transport, dtlsParameters: String) async
    func onConnectionStateChange(transport: any Transport, connectionState: TransportConnectionState)
}

public protocol SendTransportDelegate: TransportDelegate {
    func onProduce(transport: any Transport, kind: MediaKind, rtpParameters: String,
                   appData: String, callback: @escaping (String?) -> Void)
    func onProduceData(transport: any Transport, sctpParameters: String, label: String,
                       protocol dataProtocol: String, appData: String, callback: @escaping (String?) -> Void)
}

public protocol ReceiveTransportDelegate: TransportDelegate {
}

public protocol ProducerDelegate: AnyObject {
    func onTransportClose(in producer: Producer)
}

public protocol ConsumerDelegate: AnyObject {
    func onTransportClose(in consumer: Consumer)
}

// MARK: - ScalabilityMode

public struct ScalabilityMode {
    public var spatialLayers: Int
    public var temporalLayers: Int

    public static func parse(_ scalabilityModeString: String) -> ScalabilityMode {
        // Simple parse: L{spatial}T{temporal}
        var spatial = 1
        var temporal = 1
        let pattern = #"L(\d+)T(\d+)"#
        if let match = scalabilityModeString.range(of: pattern, options: .regularExpression) {
            let s = scalabilityModeString[match]
            let parts = s.split(whereSeparator: { $0 == "L" || $0 == "T" })
            if parts.count >= 2 {
                spatial = Int(parts[0]) ?? 1
                temporal = Int(parts[1]) ?? 1
            }
        }
        return ScalabilityMode(spatialLayers: spatial, temporalLayers: temporal)
    }
}

// MARK: - RTPParameters (matches existing API for updateSenderParameters)

public struct RTPParameters {
    public enum DegradationPreference {
        case disabled
        case maintainFramerate
        case maintainResolution
        case balanced
    }

    public struct RTPEncodingParameters {
        public struct Resolution {
            public var width: Int
            public var height: Int
            public var cgSizeValue: CGSize { CGSize(width: width, height: height) }
            public init(width: Int, height: Int) {
                self.width = width
                self.height = height
            }
            public init(from cgSize: CGSize) {
                self.width = Int(cgSize.width)
                self.height = Int(cgSize.height)
            }
        }
        public var scalabilityMode: String?
        public var requestedResolution: Resolution?
        public var isActive: Bool = true
        public var maxBitrateBps: Int?
        public var minBitrateBps: Int?
        public var maxFramerate: Double?
        public var numTemporalLayers: Int?
        public var scaleResolutionDownBy: Double?
        public var bitratePriority: Double = 1.0
        public var adaptiveAudioPacketTime: Bool = false
    }

    public var degradationPreference: DegradationPreference?
    public var encodings: [RTPEncodingParameters]?
}

// MARK: - DataState (stub for API compat)

public enum DataState {
    case connecting
    case open
    case closing
    case closed
}
