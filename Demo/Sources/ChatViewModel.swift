// ChatViewModel – bridges RocsClient delegate API into SwiftUI @Published state.

import AVFoundation
import Combine
import Foundation
import RocsSDK
import WebRTC

@MainActor
final class ChatViewModel: ObservableObject {

    // ── Published state ──────────────────────────────────────────────────────
    @Published var connectionStatus:   ConnectionStatus   = .idle
    @Published var conversationStatus: ConversationStatus = .idle
    @Published var speakingStatus:     SpeakingStatus     = .none
    @Published var messages:           [ConversationMessage] = []
    @Published var errorMessage:       String?
    @Published var isMuted             = false
    @Published var isListenMode        = false
    @Published var audioLevel:         Float  = 0
    @Published var aiAudioLevel:       Float  = 0
    @Published var currentTranscript:  String = ""
    @Published var remoteAudioTrack:   RTCMediaStreamTrack?
    @Published var systemPrompt        = Config.defaultSystemPrompt
    @Published var toolCalls:          [ToolCall] = []
    @Published var toolCallsMessageId: String = ""

    // ── Derived ──────────────────────────────────────────────────────────────
    var isConnected:          Bool { connectionStatus == .connected }
    var isConnecting:         Bool { connectionStatus == .connecting }
    var isConversationActive: Bool { conversationStatus == .active }
    var isUserSpeaking:       Bool { speakingStatus == .user }
    var isAISpeaking:         Bool { speakingStatus == .ai }

    // ── SDK client ───────────────────────────────────────────────────────────
    private var client: RocsClient!

    init() { buildClient() }

    // ── Actions ───────────────────────────────────────────────────────────────

    func connect()           { client.connect() }
    func disconnect()        { client.disconnect() }
    func startConversation() { client.startConversation() }
    func endConversation()   { client.endConversation() }

    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        client.sendMessage(text)
    }

    func selectAction(message: String, actionId: String) {
        client.selectAction(message: message, actionId: actionId)
        toolCalls = []
        toolCallsMessageId = ""
    }

    func toggleMute() {
        isMuted.toggle()
        client.setMuted(isMuted)
    }

    func toggleListenMode() {
        isListenMode.toggle()
        client.setListenMode(isListenMode)
    }

    func dismissError() { errorMessage = nil }

    // ── Private ──────────────────────────────────────────────────────────────

    private func buildClient() {
        var config = RocsConfig(
            appKey:    Config.appKey,
            serverUrl: Config.servers.first(where: { $0.id == Config.defaultServerId })?.url ?? "http://localhost:8004"
        )
        config.onConnectionStatusChange  = { [weak self] s in self?.connectionStatus   = s }
        config.onConversationStatusChange = { [weak self] s in self?.conversationStatus = s }
        config.onSpeakingStatusChange    = { [weak self] s in self?.speakingStatus = s }
        config.onMessage                 = { [weak self] m in self?.messages.append(m) }
        config.onError                   = { [weak self] (e: RocsError) in self?.errorMessage = e.message }
        config.onAudioLevelChange        = { [weak self] l in self?.audioLevel   = l }
        config.onAIAudioLevelChange      = { [weak self] l in self?.aiAudioLevel = l }
        config.onRemoteAudioTrack        = { [weak self] t in self?.remoteAudioTrack = t }

        client = RocsClient(config: config)
        client.delegate = self
    }
}

// ── RocsClientDelegate ───────────────────────────────────────────────────

extension ChatViewModel: RocsClientDelegate {
    nonisolated func client(_ client: RocsClient, didChangeConnectionStatus status: ConnectionStatus) {
        Task { @MainActor in self.connectionStatus = status }
    }
    nonisolated func client(_ client: RocsClient, didChangeConversationStatus status: ConversationStatus) {
        Task { @MainActor in self.conversationStatus = status }
    }
    nonisolated func client(_ client: RocsClient, didChangeSpeakingStatus status: SpeakingStatus) {
        Task { @MainActor in self.speakingStatus = status }
    }
    nonisolated func client(_ client: RocsClient, didReceiveMessage message: ConversationMessage) {
        Task { @MainActor in self.messages.append(message) }
    }
    nonisolated func client(_ client: RocsClient, didFailWithError error: RocsError) {
        Task { @MainActor in self.errorMessage = error.message }
    }
    nonisolated func client(_ client: RocsClient, didReceiveRemoteAudioTrack track: RTCMediaStreamTrack) {
        Task { @MainActor in self.remoteAudioTrack = track }
    }
    nonisolated func client(_ client: RocsClient, didReceiveRemoteVideoTrack track: RTCMediaStreamTrack) {}
    nonisolated func client(_ client: RocsClient, didUpdateAudioLevel level: Float) {
        Task { @MainActor in self.audioLevel = level }
    }
    nonisolated func client(_ client: RocsClient, didUpdateAIAudioLevel level: Float) {
        Task { @MainActor in self.aiAudioLevel = level }
    }
    nonisolated func client(_ client: RocsClient, didUpdateTranscript transcript: String) {
        Task { @MainActor in self.currentTranscript = transcript }
    }
    nonisolated func client(_ client: RocsClient, didReceiveToolCalls tools: [ToolCall], messageId: String) {
        Task { @MainActor in
            self.toolCalls = tools
            self.toolCallsMessageId = messageId
        }
    }
    nonisolated func client(_ client: RocsClient, didReceiveClearAction actionIds: [String], sessionId: String) {
        Task { @MainActor in
            self.toolCalls = self.toolCalls.filter { !actionIds.contains($0.id) }
        }
    }
}
