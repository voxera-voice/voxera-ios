import AVFoundation
import Combine
import Foundation
import WebRTC

/// SwiftUI ViewModel that wraps `RocsClient` and exposes the same
/// state surface as the React Native `useRocsChat` hook.
///
/// **Usage (SwiftUI):**
/// ```swift
/// @StateObject private var vm = RocsViewModel(config: .init(
///     appKey: "YOUR_APP_KEY",
///     serverUrl: "http://localhost:8004"
/// ))
///
/// var body: some View {
///     VStack {
///         Text(vm.connectionStatus.rawValue)
///         Button("Connect") { vm.connect() }
///     }
/// }
/// ```
@MainActor
public final class RocsViewModel: ObservableObject {

    // ──────────────────────────────────────────────
    // MARK: - Published state (mirrors useRocsChat)
    // ──────────────────────────────────────────────

    @Published public private(set) var connectionStatus:     ConnectionStatus   = .idle
    @Published public private(set) var conversationStatus:   ConversationStatus = .idle
    @Published public private(set) var speakingStatus:       SpeakingStatus     = .none
    @Published public private(set) var conversationMessages: [ConversationMessage] = []
    @Published public private(set) var currentTranscript:    String = ""
    @Published public private(set) var audioLevel:           Double = 0
    @Published public private(set) var aiAudioLevel:         Double = 0
    @Published public private(set) var error:                RocsError?
    @Published public private(set) var isMuted:              Bool = false
    @Published public private(set) var isListenMode:         Bool = false
    @Published public private(set) var isSpeakerOn:          Bool = true
    @Published public private(set) var isVideoEnabled:       Bool = false
    @Published public private(set) var isScreenSharing:      Bool = false
    @Published public private(set) var remoteAudioTrack:     RTCMediaStreamTrack?
    @Published public private(set) var remoteVideoTrack:     RTCMediaStreamTrack?

    // Meeting state
    @Published public private(set) var roomMode:               RoomMode?
    @Published public private(set) var isHost:                 Bool = false
    @Published public private(set) var roomParticipants:       [RoomParticipant] = []
    @Published public private(set) var transcriptions:         [TranscriptionEntry] = []
    @Published public private(set) var waitingRoom:            [WaitingRoomEntry] = []
    @Published public private(set) var bookmarks:              [MeetingBookmark] = []
    @Published public private(set) var summaries:              [MeetingSummary] = []
    @Published public private(set) var currentMinutes:         MeetingMinutes?
    @Published public private(set) var isTranscriptionEnabled: Bool = false
    @Published public private(set) var isAskAiActive:          Bool = false
    @Published public private(set) var isRoomLocked:           Bool = false
    @Published public private(set) var isWaitingRoomEnabled:   Bool = false
    @Published public private(set) var isInWaitingRoom:        Bool = false
    @Published public private(set) var askAiTextResponse:      String = ""
    @Published public private(set) var isAskAiTextProcessing:  Bool = false
    @Published public private(set) var toolCalls:              [ToolCall] = []
    @Published public private(set) var toolCallsMessageId:     String = ""

    // Derived convenience booleans
    public var isConnected:          Bool { connectionStatus == .connected }
    public var isConnecting:         Bool { connectionStatus == .connecting }
    public var isConversationActive: Bool { conversationStatus == .active }
    public var isUserSpeaking:       Bool { speakingStatus == .user }
    public var isAISpeaking:         Bool { speakingStatus == .ai }
    public var isSpeaking:           Bool { speakingStatus != .none }

    // ──────────────────────────────────────────────
    // MARK: - Private
    // ──────────────────────────────────────────────

    private let client: RocsClient

    // ──────────────────────────────────────────────
    // MARK: - Init
    // ──────────────────────────────────────────────

    public init(config: RocsConfig) {
        client = RocsClient(config: config)
        client.delegate = self
    }

    // ──────────────────────────────────────────────
    // MARK: - Actions
    // ──────────────────────────────────────────────

    public func connect() {
        client.connect()
    }

    public func disconnect() {
        client.disconnect()
        // Reset meeting state
        roomMode = nil
        isHost = false
        roomParticipants = []
        transcriptions = []
        waitingRoom = []
        bookmarks = []
        summaries = []
        currentMinutes = nil
        isTranscriptionEnabled = false
        isAskAiActive = false
        isRoomLocked = false
        isWaitingRoomEnabled = false
        isInWaitingRoom = false
        askAiTextResponse = ""
        isAskAiTextProcessing = false
    }

    public func startConversation() {
        client.startConversation()
    }

    public func endConversation() {
        client.endConversation()
    }

    public func sendMessage(_ content: String) {
        client.sendMessage(content)
    }

    public func selectAction(message: String, actionId: String) {
        client.selectAction(message: message, actionId: actionId)
        toolCalls = []
        toolCallsMessageId = ""
    }

    public func setMuted(_ muted: Bool) {
        client.setMuted(muted)
        isMuted = muted
    }

    public func toggleMute() {
        setMuted(!isMuted)
    }

    public func setListenMode(_ mode: Bool) {
        client.setListenMode(mode)
        isListenMode = mode
    }

    @discardableResult
    public func toggleListenMode() -> Bool {
        let next = !isListenMode
        setListenMode(next)
        return next
    }

    public func setAudioOutput(_ route: AudioOutputRoute) {
        client.setAudioOutput(route)
        isSpeakerOn = (route == .speaker)
    }

    public func toggleAudioOutput() {
        let newRoute: AudioOutputRoute = isSpeakerOn ? .earpiece : .speaker
        setAudioOutput(newRoute)
    }

    public func enableVideo() {
        // Video requires a track; use enableVideoWithCapturer(_:track:) instead
        isVideoEnabled = true
    }

    public func disableVideo() {
        client.disableVideo()
        isVideoEnabled = false
    }

    public func toggleVideo() {
        if isVideoEnabled { disableVideo() } else { enableVideo() }
    }

    public func enableVideoWithCapturer(_ capturer: RTCCameraVideoCapturer, track: RTCVideoTrack) {
        client.enableVideo(track: track)
        isVideoEnabled = true
    }

    /// Start the camera and produce a video track. Updates `isVideoEnabled` and `localVideoTrack`.
    public func startCamera(position: AVCaptureDevice.Position = .front) {
        Task {
            do {
                try await client.startCamera(position: position)
                isVideoEnabled = true
                localVideoTrack = client.localVideoTrack
            } catch {
                isVideoEnabled = false
                localVideoTrack = nil
                self.error = (error as? RocsError) ?? RocsError(error.localizedDescription, code: .webRTCError)
            }
        }
    }

    /// Stop the camera. Clears `isVideoEnabled` and `localVideoTrack`.
    public func stopCamera() {
        client.stopCamera()
        isVideoEnabled = false
        localVideoTrack = nil
    }

    /// Toggle camera on/off.
    public func toggleCamera() {
        if isVideoEnabled { stopCamera() } else { startCamera() }
    }

    /// Switch between front and back camera.
    public func switchCamera() {
        client.switchCamera()
    }

    /// Current camera position (.front or .back).
    public var cameraPosition: AVCaptureDevice.Position { client.cameraPosition }

    /// The local video track being sent. Nil when camera is off.
    @Published public private(set) var localVideoTrack: RTCVideoTrack?

    public func startScreenShare(track: RTCVideoTrack) {
        client.startScreenShare(track: track)
        isScreenSharing = true
    }

    public func stopScreenShare() {
        client.stopScreenShare()
        isScreenSharing = false
    }

    public func toggleScreenShare(track: RTCVideoTrack) {
        if isScreenSharing { stopScreenShare() } else { startScreenShare(track: track) }
    }

    public func getStats() async -> WebRTCStats? {
        await client.getStats()
    }

    public func updateConfig(_ update: RocsConfigUpdate) {
        client.updateConfig(update)
    }

    public func clearError() {
        client.clearError()
        error = nil
    }

    // ──────────────────────────────────────────────
    // MARK: - Meeting Actions
    // ──────────────────────────────────────────────

    public func setMeetingCallbacks(_ callbacks: MeetingCallbacks) {
        client.setMeetingCallbacks(callbacks)
    }

    public func setRoomInfo(roomMode: RoomMode?, isHost: Bool) {
        client.setRoomInfo(roomMode: roomMode, isHost: isHost)
        self.roomMode = roomMode
        self.isHost = isHost
    }

    public func connectSocketOnly() {
        client.connectSocketOnly()
    }

    public func setupRoomWebRTC() {
        client.setupRoomWebRTC()
    }

    public func setupMeetingListeners() {
        client.setupMeetingListeners()
    }

    // Host controls
    public func muteParticipant(targetClientId: String) {
        client.muteParticipant(targetClientId: targetClientId)
    }

    public func muteAll() { client.muteAll() }
    public func unmuteAll() { client.unmuteAll() }

    public func removeParticipant(targetClientId: String) {
        client.removeParticipant(targetClientId: targetClientId)
    }

    public func lockRoom(_ locked: Bool) { client.lockRoom(locked) }
    public func endMeeting() { client.endMeeting() }

    public func transferHost(targetClientId: String) {
        client.transferHost(targetClientId: targetClientId)
    }

    public func toggleTranscription(_ enabled: Bool) {
        client.toggleTranscription(enabled)
    }

    public func askAi() { client.askAi() }
    public func cancelAskAi() { client.cancelAskAi() }
    public func askAiText(prompt: String? = nil) { client.askAiText(prompt: prompt) }

    public func enableWaitingRoom(_ enabled: Bool) {
        client.enableWaitingRoom(enabled)
    }

    public func admitParticipant(targetClientId: String) {
        client.admitParticipant(targetClientId: targetClientId)
    }

    public func denyParticipant(targetClientId: String) {
        client.denyParticipant(targetClientId: targetClientId)
    }

    public func admitAll() { client.admitAll() }

    // AI differentiators
    public func generateSummary() { client.generateSummary() }
    public func generateMinutes() { client.generateMinutes() }

    public func addBookmark(label: String, isActionItem: Bool = false) {
        client.addBookmark(label: label, isActionItem: isActionItem)
    }

    public func removeBookmark(bookmarkId: String) {
        client.removeBookmark(bookmarkId: bookmarkId)
    }

    public func getBookmarks() { client.getBookmarks() }
    public func getTranscript() { client.getTranscript() }
    public func getSummaries() { client.getSummaries() }
    public func getMinutes() { client.getMinutes() }
}

// ──────────────────────────────────────────────
// MARK: - RocsClientDelegate
// ──────────────────────────────────────────────

extension RocsViewModel: RocsClientDelegate {

    public func client(_ client: RocsClient, didChangeConnectionStatus status: ConnectionStatus) {
        Task { @MainActor in
            connectionStatus = status
        }
    }

    public func client(_ client: RocsClient, didChangeConversationStatus status: ConversationStatus) {
        Task { @MainActor in
            conversationStatus = status
        }
    }

    public func client(_ client: RocsClient, didChangeSpeakingStatus status: SpeakingStatus) {
        Task { @MainActor in
            speakingStatus = status
        }
    }

    public func client(_ client: RocsClient, didReceiveMessage message: ConversationMessage) {
        Task { @MainActor in
            conversationMessages.append(message)
        }
    }

    public func client(_ client: RocsClient, didUpdateTranscript transcript: String) {
        Task { @MainActor in
            currentTranscript = transcript
        }
    }

    public func client(_ client: RocsClient, didUpdateAudioLevel level: Float) {
        Task { @MainActor in
            audioLevel = Double(level)
        }
    }

    public func client(_ client: RocsClient, didUpdateAIAudioLevel level: Float) {
        Task { @MainActor in
            aiAudioLevel = Double(level)
        }
    }

    public func client(_ client: RocsClient, didFailWithError err: RocsError) {
        Task { @MainActor in
            error = err
        }
    }

    public func client(_ client: RocsClient, didReceiveRemoteAudioTrack track: RTCMediaStreamTrack) {
        Task { @MainActor in
            remoteAudioTrack = track
        }
    }

    public func client(_ client: RocsClient, didReceiveRemoteVideoTrack track: RTCMediaStreamTrack) {
        Task { @MainActor in
            remoteVideoTrack = track
        }
    }

    public func client(_ client: RocsClient, didUpdateParticipants participants: [RoomParticipant]) {
        Task { @MainActor in
            roomParticipants = participants
        }
    }

    public func client(_ client: RocsClient, didUpdateRoomMode mode: RoomMode?) {
        Task { @MainActor in
            roomMode = mode
        }
    }

    public func client(_ client: RocsClient, didUpdateIsHost host: Bool) {
        Task { @MainActor in
            isHost = host
        }
    }

    public func client(_ client: RocsClient, didReceiveMeetingEvent event: String, data: [String: Any]) {
        Task { @MainActor in
            isRoomLocked = client.isRoomLocked
            isTranscriptionEnabled = client.isTranscriptionEnabled
            isAskAiActive = client.isAskAiActive
            isWaitingRoomEnabled = client.isWaitingRoomEnabled
            isInWaitingRoom = client.isInWaitingRoom
            isMuted = client.isMuted
        }
    }

    public func client(_ client: RocsClient, didReceiveTranscriptionEntry entry: TranscriptionEntry) {
        Task { @MainActor in
            transcriptions = client.transcriptions
        }
    }

    public func client(_ client: RocsClient, didUpdateWaitingRoom entries: [WaitingRoomEntry]) {
        Task { @MainActor in
            waitingRoom = entries
        }
    }

    public func client(_ client: RocsClient, didReceiveBookmarkEvent bookmark: MeetingBookmark?, removed bookmarkId: String?) {
        Task { @MainActor in
            bookmarks = client.bookmarks
        }
    }

    public func client(_ client: RocsClient, didReceiveSummary summary: MeetingSummary) {
        Task { @MainActor in
            summaries = client.summaries
        }
    }

    public func client(_ client: RocsClient, didReceiveMinutes minutes: MeetingMinutes) {
        Task { @MainActor in
            currentMinutes = minutes
        }
    }

    public func client(_ client: RocsClient, didReceiveAskAiTextChunk token: String) {
        Task { @MainActor in
            askAiTextResponse = client.askAiTextResponse
            isAskAiTextProcessing = client.isAskAiTextProcessing
        }
    }

    public func client(_ client: RocsClient, didReceiveAskAiTextResponse text: String) {
        Task { @MainActor in
            askAiTextResponse = text
        }
    }

    public func client(_ client: RocsClient, didReceiveToolCalls tools: [ToolCall], messageId: String) {
        Task { @MainActor in
            toolCalls = tools
            toolCallsMessageId = messageId
        }
    }
}
