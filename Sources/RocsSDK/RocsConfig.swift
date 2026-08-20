import Foundation
import WebRTC

// MARK: - Chat / Voice / Video configuration

// Note: WebRTC is re-exported by the Mediasoup module.

public struct ChatConfig {
    public var systemPrompt: String?
    public var welcomeMessage: String?
    public var model: String?
    public var temperature: Double?
    public var maxTokens: Int?

    public init(
        systemPrompt: String? = nil,
        welcomeMessage: String? = nil,
        model: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.welcomeMessage = welcomeMessage
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public struct VoiceConfig {
    public var voiceId: String?
    public var language: String?
    public var stability: Double?
    public var similarityBoost: Double?

    public init(voiceId: String? = nil, language: String? = nil,
                stability: Double? = nil, similarityBoost: Double? = nil) {
        self.voiceId = voiceId
        self.language = language
        self.stability = stability
        self.similarityBoost = similarityBoost
    }
}

public struct VideoConfig {
    public var enabled: Bool
    public var width: Int
    public var height: Int
    public var frameRate: Int
    /// Enable server-side AI frame analysis
    public var enableVideoAI: Bool
    /// Use front (true) or back (false) camera
    public var useFrontCamera: Bool

    public init(
        enabled: Bool = false,
        width: Int = 1280,
        height: Int = 720,
        frameRate: Int = 30,
        enableVideoAI: Bool = false,
        useFrontCamera: Bool = true
    ) {
        self.enabled = enabled
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.enableVideoAI = enableVideoAI
        self.useFrontCamera = useFrontCamera
    }
}

public struct ConnectionOptions {
    public var autoReconnect: Bool
    public var reconnectAttempts: Int
    public var reconnectDelay: TimeInterval
    public var timeout: TimeInterval

    public init(
        autoReconnect: Bool = true,
        reconnectAttempts: Int = 3,
        reconnectDelay: TimeInterval = 1.0,
        timeout: TimeInterval = 30.0
    ) {
        self.autoReconnect = autoReconnect
        self.reconnectAttempts = reconnectAttempts
        self.reconnectDelay = reconnectDelay
        self.timeout = timeout
    }
}

// MARK: - Main configuration

public struct RocsConfig {
    // Required
    public let appKey: String
    public let serverUrl: String

    // Optional – legacy fields
    @available(*, deprecated, renamed: "agentId")
    public var configurationId: String?
    public var agentId: String?
    public var userId: String?
    public var metadata: [String: String]?
    public var videoConfig: VideoConfig?
    public var connectionOptions: ConnectionOptions

    // Voice-session fields
    public var sessionId: String?
    public var threadId: String?
    public var chatProfile: [String: Any]?
    public var user: [String: Any]?
    public var ttsConfig: [String: Any]?
    public var transcriptionConfig: [String: Any]?
    public var modelConfig: [String: Any]?
    public var tools: [[String: Any]]?
    public var additionalSystemPrompts: [String]?
    public var initialMessages: [[String: Any]]?
    public var selectedModel: String?
    public var selectedVoice: String?
    public var workspaceId: String?
    /// Display name of the person speaking — passed to the AI in the system prompt.
    public var username: String?
    /// Additional context/metadata about the user — appended to the AI system prompt.
    public var userInfo: [String: String]?

    // Callbacks
    public var onConnectionStatusChange: ((ConnectionStatus) -> Void)?
    public var onConversationStatusChange: ((ConversationStatus) -> Void)?
    public var onSpeakingStatusChange: ((SpeakingStatus) -> Void)?
    public var onMessage: ((ConversationMessage) -> Void)?
    public var onTranscript: ((String, Bool) -> Void)?
    public var onError: ((RocsError) -> Void)?
    public var onLocalVideoTrack: ((RTCVideoTrack?) -> Void)?
    public var onRemoteAudioTrack: ((RTCMediaStreamTrack?) -> Void)?
    public var onRemoteVideoTrack: ((RTCMediaStreamTrack?) -> Void)?
    public var onAudioLevelChange: ((Float) -> Void)?
    public var onAIAudioLevelChange: ((Float) -> Void)?
    public var onChessUpdate: (([String: Any]) -> Void)?
    public var onSearching: ((String) -> Void)?

    // Meeting
    public var meetingCallbacks: MeetingCallbacks?

    public init(
        appKey: String,
        serverUrl: String,
        agentId: String? = nil,
        userId: String? = nil,
        sessionId: String? = nil,
        threadId: String? = nil,
        chatProfile: [String: Any]? = nil,
        user: [String: Any]? = nil,
        ttsConfig: [String: Any]? = nil,
        transcriptionConfig: [String: Any]? = nil,
        modelConfig: [String: Any]? = nil,
        tools: [[String: Any]]? = nil,
        additionalSystemPrompts: [String]? = nil,
        initialMessages: [[String: Any]]? = nil,
        selectedModel: String? = nil,
        selectedVoice: String? = nil,
        workspaceId: String? = nil,
        username: String? = nil,
        userInfo: [String: String]? = nil,
        videoConfig: VideoConfig? = nil,
        connectionOptions: ConnectionOptions = ConnectionOptions(),
        configurationId: String? = nil,
        onConnectionStatusChange: ((ConnectionStatus) -> Void)? = nil,
        onConversationStatusChange: ((ConversationStatus) -> Void)? = nil,
        onSpeakingStatusChange: ((SpeakingStatus) -> Void)? = nil,
        onMessage: ((ConversationMessage) -> Void)? = nil,
        onError: ((RocsError) -> Void)? = nil,
        onRemoteAudioTrack: ((RTCMediaStreamTrack?) -> Void)? = nil,
        onRemoteVideoTrack: ((RTCMediaStreamTrack?) -> Void)? = nil
    ) {
        self.appKey = appKey
        self.serverUrl = serverUrl
        self.agentId = agentId
        self.userId = userId
        self.sessionId = sessionId
        self.threadId = threadId
        self.chatProfile = chatProfile
        self.user = user
        self.ttsConfig = ttsConfig
        self.transcriptionConfig = transcriptionConfig
        self.modelConfig = modelConfig
        self.tools = tools
        self.additionalSystemPrompts = additionalSystemPrompts
        self.initialMessages = initialMessages
        self.selectedModel = selectedModel
        self.selectedVoice = selectedVoice
        self.workspaceId = workspaceId
        self.username = username
        self.userInfo = userInfo
        self.videoConfig = videoConfig
        self.connectionOptions = connectionOptions
        self.configurationId = configurationId
        self.onConnectionStatusChange = onConnectionStatusChange
        self.onConversationStatusChange = onConversationStatusChange
        self.onSpeakingStatusChange = onSpeakingStatusChange
        self.onMessage = onMessage
        self.onError = onError
        self.onRemoteAudioTrack = onRemoteAudioTrack
        self.onRemoteVideoTrack = onRemoteVideoTrack
    }
}

// MARK: - Partial config update (used by updateConfig)

/// Subset of config fields that can be updated at runtime.
public struct RocsConfigUpdate {
    public var systemPrompt: String?
    public var voiceId:      String?
    public var language:     String?

    public init(systemPrompt: String? = nil, voiceId: String? = nil, language: String? = nil) {
        self.systemPrompt = systemPrompt
        self.voiceId      = voiceId
        self.language     = language
    }
}
