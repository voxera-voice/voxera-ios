import Foundation
@_exported import WebRTC

// MARK: - Connection & Conversation Status

public enum ConnectionStatus: String {
    case idle
    case connecting
    case connected
    case reconnecting
    case disconnected
    case error
}

public enum ConversationStatus: String {
    case idle
    case starting
    case active
    case ending
    case ended
}

public enum SpeakingStatus: String {
    case user
    case ai
    case none
    case searching
}

// MARK: - Tool Calls

public struct ToolCallFunction {
    public let name: String
    public let arguments: [String: Any]

    public init(name: String, arguments: [String: Any]) {
        self.name = name
        self.arguments = arguments
    }

    public init?(dict: [String: Any]) {
        guard let name = dict["name"] as? String else { return nil }
        self.name = name
        self.arguments = dict["arguments"] as? [String: Any] ?? [:]
    }
}

public struct ToolCall: Identifiable {
    public let id: String
    public let type: String
    public let function: ToolCallFunction

    public init(id: String, type: String, function: ToolCallFunction) {
        self.id = id
        self.type = type
        self.function = function
    }

    public init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let funcDict = dict["function"] as? [String: Any],
              let function = ToolCallFunction(dict: funcDict) else { return nil }
        self.id = id
        self.type = dict["type"] as? String ?? "function"
        self.function = function
    }
}

// MARK: - Messages

public struct ConversationMessage: Identifiable {
    public let id: String
    public let messageId: String
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public var metadata: [String: Any]?
    public var fullText: String?
    public var isFinal: Bool


    public init(id: String = UUID().uuidString, messageId: String, role: MessageRole, content: String,
                timestamp: Date = Date(), metadata: [String: Any]? = nil, fullText: String?, isFinal:Bool=false) {
        self.id        = id
        self.messageId = messageId
        self.role      = role
        self.content   = content
        self.timestamp = timestamp
        self.metadata  = metadata
        self.fullText  = fullText
        self.isFinal = isFinal
    }

    public enum MessageRole: String {
        case user
        case assistant
        case system
    }
}

// MARK: - Stats

public struct WebRTCStats {
    public var bytesReceived: Int = 0
    public var bytesSent: Int = 0
    public var packetsReceived: Int = 0
    public var packetsSent: Int = 0
    public var roundTripTime: Double?
    public var jitter: Double?
    public var audioLevel: Double?

    public init() {}

    /// Build from the raw JSON dict returned by WebRTCManager.getStats().
    public init(raw: [String: Any]) {
        let send = raw["send"] as? [String: Any] ?? [:]
        let recv = raw["recv"] as? [String: Any] ?? [:]
        bytesSent      = send["bytesSent"]      as? Int ?? 0
        bytesReceived  = recv["bytesReceived"]  as? Int ?? 0
        packetsSent    = send["packetsSent"]    as? Int ?? 0
        packetsReceived = recv["packetsReceived"] as? Int ?? 0
        roundTripTime  = send["roundTripTime"]  as? Double
        jitter         = recv["jitter"]         as? Double
        audioLevel     = recv["audioLevel"]     as? Double
    }
}

// MARK: - Meeting / Room Types

public enum RoomMode: String {
    case aiMeeting    = "ai-meeting"
    case normalMeeting = "normal-meeting"
}

public struct RoomParticipant {
    public let id: String
    public let name: String
    public var userId: String?
    public var isMuted: Bool
    public var isSpeaking: Bool
    public let sessionId: String

    public init(id: String, name: String, userId: String? = nil,
                isMuted: Bool = false, isSpeaking: Bool = false, sessionId: String) {
        self.id = id
        self.name = name
        self.userId = userId
        self.isMuted = isMuted
        self.isSpeaking = isSpeaking
        self.sessionId = sessionId
    }

    public init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String,
              let sessionId = dict["sessionId"] as? String else { return nil }
        self.id = id
        self.name = name
        self.userId = dict["userId"] as? String
        self.isMuted = dict["isMuted"] as? Bool ?? false
        self.isSpeaking = dict["isSpeaking"] as? Bool ?? false
        self.sessionId = sessionId
    }
}

public struct TranscriptionEntry {
    public let clientId: String
    public let displayName: String
    public let text: String
    public let timestamp: TimeInterval

    public init(clientId: String, displayName: String, text: String, timestamp: TimeInterval) {
        self.clientId = clientId
        self.displayName = displayName
        self.text = text
        self.timestamp = timestamp
    }

    public init?(dict: [String: Any]) {
        // Server sends "speaker" as the identity field; "clientId" is the legacy/meeting name.
        // "displayName" may also be absent — fall back to "speaker".
        let clientId    = dict["clientId"]    as? String
                       ?? dict["speaker"]     as? String
                       ?? ""
        let displayName = dict["displayName"] as? String
                       ?? dict["speaker"]     as? String
                       ?? ""
        guard let text = dict["text"] as? String, !text.isEmpty else { return nil }
        self.clientId    = clientId
        self.displayName = displayName
        self.text        = text
        self.timestamp   = dict["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
    }
}

public struct WaitingRoomEntry {
    public let clientId: String
    public let socketId: String
    public let displayName: String
    public let joinedAt: Date

    public init(clientId: String, socketId: String, displayName: String, joinedAt: Date = Date()) {
        self.clientId = clientId
        self.socketId = socketId
        self.displayName = displayName
        self.joinedAt = joinedAt
    }

    public init?(dict: [String: Any]) {
        guard let clientId = dict["clientId"] as? String,
              let socketId = dict["socketId"] as? String,
              let displayName = dict["displayName"] as? String else { return nil }
        self.clientId = clientId
        self.socketId = socketId
        self.displayName = displayName
        if let ts = dict["joinedAt"] as? TimeInterval {
            self.joinedAt = Date(timeIntervalSince1970: ts / 1000)
        } else {
            self.joinedAt = Date()
        }
    }
}

public struct MeetingBookmark {
    public let id: String
    public let clientId: String
    public let displayName: String
    public let label: String
    public let timestamp: TimeInterval
    public let conversationIndex: Int
    public let isActionItem: Bool

    public init(id: String, clientId: String, displayName: String, label: String,
                timestamp: TimeInterval, conversationIndex: Int, isActionItem: Bool = false) {
        self.id = id
        self.clientId = clientId
        self.displayName = displayName
        self.label = label
        self.timestamp = timestamp
        self.conversationIndex = conversationIndex
        self.isActionItem = isActionItem
    }

    public init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let clientId = dict["clientId"] as? String,
              let displayName = dict["displayName"] as? String,
              let label = dict["label"] as? String else { return nil }
        self.id = id
        self.clientId = clientId
        self.displayName = displayName
        self.label = label
        self.timestamp = dict["timestamp"] as? TimeInterval ?? 0
        self.conversationIndex = dict["conversationIndex"] as? Int ?? 0
        self.isActionItem = dict["isActionItem"] as? Bool ?? false
    }
}

public struct MeetingSummary {
    public let id: String
    public let sessionId: String
    public let generatedAt: TimeInterval
    public let summary: String
    public let actionItems: [String]
    public let keyTopics: [String]
    public let requestedBy: String

    public init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let sessionId = dict["sessionId"] as? String,
              let summary = dict["summary"] as? String else { return nil }
        self.id = id
        self.sessionId = sessionId
        self.generatedAt = dict["generatedAt"] as? TimeInterval ?? 0
        self.summary = summary
        self.actionItems = dict["actionItems"] as? [String] ?? []
        self.keyTopics = dict["keyTopics"] as? [String] ?? []
        self.requestedBy = dict["requestedBy"] as? String ?? ""
    }
}

public struct MeetingMinutes {
    public let id: String
    public let sessionId: String
    public let generatedAt: TimeInterval
    public let title: String
    public let attendees: [String]
    public let duration: TimeInterval
    public let sections: [MeetingMinutesSection]
    public let actionItems: [MeetingMinutesActionItem]
    public let rawTranscript: String

    public init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let sessionId = dict["sessionId"] as? String else { return nil }
        self.id = id
        self.sessionId = sessionId
        self.generatedAt = dict["generatedAt"] as? TimeInterval ?? 0
        self.title = dict["title"] as? String ?? ""
        self.attendees = dict["attendees"] as? [String] ?? []
        self.duration = dict["duration"] as? TimeInterval ?? 0
        self.rawTranscript = dict["rawTranscript"] as? String ?? ""
        self.sections = (dict["sections"] as? [[String: Any]] ?? []).compactMap { MeetingMinutesSection(dict: $0) }
        self.actionItems = (dict["actionItems"] as? [[String: Any]] ?? []).compactMap { MeetingMinutesActionItem(dict: $0) }
    }
}

public struct MeetingMinutesSection {
    public let heading: String
    public let content: String

    public init?(dict: [String: Any]) {
        guard let heading = dict["heading"] as? String,
              let content = dict["content"] as? String else { return nil }
        self.heading = heading
        self.content = content
    }
}

public struct MeetingMinutesActionItem {
    public let task: String
    public var assignee: String?
    public var dueDate: String?

    public init?(dict: [String: Any]) {
        guard let task = dict["task"] as? String else { return nil }
        self.task = task
        self.assignee = dict["assignee"] as? String
        self.dueDate = dict["dueDate"] as? String
    }
}

/// Callbacks for meeting events. Set on `RocsClient` via `setMeetingCallbacks(_:)`.
public struct MeetingCallbacks {
    // Participant events
    public var onParticipantJoined: (([String: Any]) -> Void)?
    public var onParticipantLeft: (([String: Any]) -> Void)?
    public var onParticipantRemoved: (([String: Any]) -> Void)?
    public var onParticipantsUpdated: (([String: Any]) -> Void)?

    // Host control events
    public var onYouWereMuted: (([String: Any]) -> Void)?
    public var onYouWereRemoved: (([String: Any]) -> Void)?
    public var onAllMuted: (([String: Any]) -> Void)?
    public var onAllUnmuted: (([String: Any]) -> Void)?
    public var onHostChanged: (([String: Any]) -> Void)?
    public var onMeetingEnded: (([String: Any]) -> Void)?
    public var onRoomLockedChanged: (([String: Any]) -> Void)?

    // Transcription events
    public var onTranscriptionToggled: (([String: Any]) -> Void)?
    public var onLiveTranscription: (([String: Any]) -> Void)?

    // Ask AI events
    public var onAskAiStarted: (([String: Any]) -> Void)?
    public var onAskAiProcessing: (() -> Void)?
    public var onAskAiCancelled: (([String: Any]) -> Void)?

    // Text-only AI events
    public var onAskAiTextStarted: (([String: Any]) -> Void)?
    public var onAskAiTextChunk: (([String: Any]) -> Void)?
    public var onAskAiTextResponse: (([String: Any]) -> Void)?
    public var onAskAiTextError: (([String: Any]) -> Void)?

    // Waiting room events
    public var onWaitingRoom: (([String: Any]) -> Void)?
    public var onAdmitted: (([String: Any]) -> Void)?
    public var onDenied: (([String: Any]) -> Void)?
    public var onWaitingRoomUpdated: (([String: Any]) -> Void)?
    public var onWaitingRoomToggled: (([String: Any]) -> Void)?

    // AI differentiator events
    public var onSummaryGenerating: (([String: Any]) -> Void)?
    public var onSummaryGenerated: (([String: Any]) -> Void)?
    public var onMinutesGenerating: (([String: Any]) -> Void)?
    public var onMinutesGenerated: (([String: Any]) -> Void)?
    public var onBookmarkAdded: (([String: Any]) -> Void)?
    public var onBookmarkRemoved: (([String: Any]) -> Void)?

    public init() {}
}

// MARK: - Errors

public enum RocsErrorCode: String {
    case connectionFailed       = "CONNECTION_FAILED"
    case authenticationFailed   = "AUTHENTICATION_FAILED"
    case webRTCError            = "WEBRTC_ERROR"
    case mediaAccessDenied      = "MEDIA_ACCESS_DENIED"
    case timeout                = "TIMEOUT"
    case serverError            = "SERVER_ERROR"
    case invalidConfig          = "INVALID_CONFIG"
    case networkError           = "NETWORK_ERROR"
    case unknownError           = "UNKNOWN_ERROR"
}

public class RocsError: LocalizedError {
    public let code: RocsErrorCode
    public let details: [String: Any]?
    private let _message: String

    public var message: String { _message }
    public var errorDescription: String? { _message }

    public init(_ message: String, code: RocsErrorCode, details: [String: Any]? = nil) {
        self._message = message
        self.code = code
        self.details = details
    }
}

// MARK: - Mediasoup / WebRTC internal helpers

struct RtpParameters: Codable {
    let codecs: [RtpCodecParameters]
    let headerExtensions: [RtpHeaderExtension]?
    let encodings: [RtpEncoding]?
    let rtcp: RtcpParameters?

    struct RtpCodecParameters: Codable {
        let mimeType: String
        let payloadType: Int
        let clockRate: Int
        let channels: Int?
        let parameters: [String: AnyCodable]?
        let rtcpFeedback: [RtcpFeedback]?
    }

    struct RtpHeaderExtension: Codable {
        let uri: String
        let id: Int
        let encrypt: Bool?
        let parameters: [String: AnyCodable]?
    }

    struct RtpEncoding: Codable {
        let ssrc: UInt32?
        let rid: String?
        let scalabilityMode: String?
    }

    struct RtcpParameters: Codable {
        let cname: String?
        let reducedSize: Bool?
    }

    struct RtcpFeedback: Codable {
        let type: String
        let parameter: String?
    }
}

/// Wraps arbitrary Codable values to allow [String: Any]-style JSON.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self)   { value = v; return }
        if let v = try? container.decode(Int.self)    { value = v; return }
        if let v = try? container.decode(Double.self) { value = v; return }
        if let v = try? container.decode(String.self) { value = v; return }
        value = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:   try container.encode(v)
        case let v as Int:    try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        default:              try container.encodeNil()
        }
    }
}
