import Foundation
import SocketIO

/// Handles all Socket.IO signaling with the Rocs media server.
/// Implements the same protocol as the web SDK.
final class SocketSignaling {

    // MARK: - Public callbacks (set by WebRTCManager / RocsClient)

    var onNewProducer: (([String: Any]) -> Void)?            // producer dict from server
    var onConversationMessage: ((String, String, String, Int64) -> Void)? // (sessionId, role, content, ts)
    var onNewMessage: ((ConversationMessage) -> Void)?
    var onSpeakingStatusChanged: ((String) -> Void)?
    var onConversationStarted: (() -> Void)?
    var onConversationEnded: (([String: Any]) -> Void)?
    var onUserStartedSpeaking: (() -> Void)?
    var onUserStoppedSpeaking: (() -> Void)?
    var onAIStartedSpeaking: (() -> Void)?
    var onAIStoppedSpeaking: (() -> Void)?
    var onTranscriptUpdate: ((String) -> Void)?               // partial transcript from STT
    var onVolumeChanged: ((Double, Bool) -> Void)?            // (volume dBFS, isAI)
    var onServerError: ((String) -> Void)?
    var onDisconnect: (() -> Void)?
    var onError: ((String) -> Void)?

    // MARK: Meeting callbacks
    var onParticipantJoined: (([String: Any]) -> Void)?
    var onParticipantLeft: (([String: Any]) -> Void)?
    var onParticipantRemoved: (([String: Any]) -> Void)?
    var onParticipantsUpdated: (([String: Any]) -> Void)?
    var onYouWereMuted: (([String: Any]) -> Void)?
    var onYouWereRemoved: (([String: Any]) -> Void)?
    var onAllMuted: (([String: Any]) -> Void)?
    var onAllUnmuted: (([String: Any]) -> Void)?
    var onHostChanged: (([String: Any]) -> Void)?
    var onMeetingEnded: (([String: Any]) -> Void)?
    var onRoomLockedChanged: (([String: Any]) -> Void)?
    var onTranscriptionToggled: (([String: Any]) -> Void)?
    var onLiveTranscription: (([String: Any]) -> Void)?
    var onAskAiStarted: (([String: Any]) -> Void)?
    var onAskAiProcessing: (() -> Void)?
    var onAskAiCancelled: (([String: Any]) -> Void)?
    var onAskAiTextStarted: (([String: Any]) -> Void)?
    var onAskAiTextChunk: (([String: Any]) -> Void)?
    var onAskAiTextResponse: (([String: Any]) -> Void)?
    var onAskAiTextError: (([String: Any]) -> Void)?
    var onWaitingRoom: (([String: Any]) -> Void)?
    var onAdmitted: (([String: Any]) -> Void)?
    var onDenied: (([String: Any]) -> Void)?
    var onWaitingRoomUpdated: (([String: Any]) -> Void)?
    var onWaitingRoomToggled: (([String: Any]) -> Void)?
    var onSummaryGenerating: (([String: Any]) -> Void)?
    var onSummaryGenerated: (([String: Any]) -> Void)?
    var onMinutesGenerating: (([String: Any]) -> Void)?
    var onMinutesGenerated: (([String: Any]) -> Void)?
    var onBookmarkAdded: (([String: Any]) -> Void)?
    var onBookmarkRemoved: (([String: Any]) -> Void)?
    var onJustinAction: (([String: Any]) -> Void)?
    var onSearching: (([String: Any]) -> Void)?
    var onClearAction: (([String], String) -> Void)?

    /// The underlying Socket.IO client ID (used for host-changed comparison).
    var socketId: String? { socket?.sid }

    // MARK: - Private

    private var manager: SocketManager!
    private var socket: SocketIOClient!

    // Pending ack closures keyed by event name (simple single-pending model)
    private var pendingAck: [String: ([Any]) -> Void] = [:]
    private let ackQueue = DispatchQueue(label: "com.rocs.signaling.ack")

    // MARK: - Init

    init(serverUrl: String) {
        guard let url = URL(string: serverUrl) else {
            fatalError("[Signaling] Invalid server URL: \(serverUrl)")
        }

        manager = SocketManager(socketURL: url, config: [
            .log(false),
            .compress,
            .reconnects(true),
            .reconnectAttempts(3),
            .reconnectWait(1),
            .reconnectWaitMax(20),
            .forceWebsockets(true)
        ])
        socket = manager.defaultSocket
        registerListeners()
    }

    // MARK: - Connection

    func connect(completion: @escaping (Error?) -> Void) {
        var resolved = false
        socket.once(clientEvent: .connect) { [weak self] _, _ in
            guard !resolved else { return }
            resolved = true
            completion(nil)
        }
        socket.once(clientEvent: .error) { data, _ in
            guard !resolved else { return }
            resolved = true
            let msg = (data.first as? String) ?? "Socket connection error"
            completion(NSError(domain: "Rocs", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: msg]))
        }
        socket.connect()
    }

    func disconnect() {
        socket.removeAllHandlers()
        socket.disconnect()
        manager.disconnect()
    }

    // MARK: - Emit helpers

    func emit(_ event: String, data: [String: Any] = [:]) {
        socket.emit(event, data)
    }

    func emitWithAck(_ event: String, data: [String: Any] = [:],
                     completion: @escaping ([Any]) -> Void) {
        socket.emitWithAck(event, data).timingOut(after: 15) { items in
            completion(items)
        }
    }

    // MARK: - Listener registration

    private func registerListeners() {
        // Debug: log ALL events from the server
        socket.onAny { event in
            print("[Signaling] 📩 EVENT: \(event.event) data: \(String(describing: event.items))")
        }

        socket.on("speaking-status-changed") { [weak self] data, _ in
            guard let d = data.first as? [String: Any],
                  let status = d["status"] as? String else { return }
            self?.onSpeakingStatusChanged?(status)
            switch status {
            case "user-speaking":  self?.onUserStartedSpeaking?()
            case "user-stopped":   self?.onUserStoppedSpeaking?()
            case "ai-speaking":    self?.onAIStartedSpeaking?()
            case "ai-stopped":     self?.onAIStoppedSpeaking?()
            case "searching":      self?.onSearching?(["query": d["message"] as? String ?? ""])
            default: break
            }
        }

        // socket.on("conversation-message") { [weak self] data, _ in
        //     guard let d = data.first as? [String: Any],
        //           let sessionId  = d["sessionId"] as? String,
        //           let messageId  = d["messageId"] as? String,
        //           let role       = d["role"]      as? String,
        //           let content    = d["content"]   as? String,
        //           let ts         = d["timestamp"] as? Int64 else { return }
        //           let fullText   = d["fullText"] as? String
        //     self?.onConversationMessage?(sessionId, role, content, ts)
        //     let msg = ConversationMessage(
        //         id: UUID().uuidString,
        //         messageId: messageId ?? UUID().uuidString,
        //         role: role == "user" ? .user : .assistant,
        //         content: content,
        //         timestamp: Date(timeIntervalSince1970: Double(ts) / 1000),
        //         fullText: fullText
        //     )
        //     self?.onNewMessage?(msg)
        // }

        socket.on("new-producer") { [weak self] data, _ in
            print("[Signaling] 🔵 new-producer event received: \(data)")
            guard let d = data.first as? [String: Any] else { return }
            self?.onNewProducer?(d)
        }

        // Streaming and final conversation messages share the 'message' event.
        socket.on("message") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            print("conversation messages =====")
            print(data)
            let role = d["role"] as? String ?? "assistant"
            let content = d["content"] as? String ?? d["text"] as? String ?? ""
            let isFinal = d["isFinal"] as? Bool ?? (d["output"] != nil)
            let fullText   = d["fullText"] as? String
            let messageId  = d["messageId"] as? String
            let msg = ConversationMessage(
                id: d["id"] as? String ?? UUID().uuidString,
                messageId: messageId ?? UUID().uuidString,
                role: role == "user" ? .user : .assistant,
                content: content,
                timestamp: Date(),
                fullText: fullText,
                isFinal: isFinal
            )
            print("[Signaling] 🔵 message event – role: \(role) content: \(content) isFinal: \(isFinal)")
            self?.onNewMessage?(msg)
        }

        // producer-closed: server tells us a remote producer was closed
        socket.on("producer-closed") { data, _ in
            print("[Signaling] producer-closed: \(data)")
        }

        socket.on("conversation-started") { [weak self] _, _ in
            print("[Signaling] 🔵 conversation-started")
            self?.onConversationStarted?()
        }

        socket.on("conversation-ended") { [weak self] data, _ in
            print("[Signaling] 🔵 conversation-ended: \(data)")
            let d = data.first as? [String: Any] ?? [:]
            self?.onConversationEnded?(d)
        }

        socket.on("user-started-speaking") { [weak self] _, _ in
            print("[Signaling] 🔵 user-started-speaking")
            self?.onUserStartedSpeaking?()
        }

        socket.on("user-stopped-speaking") { [weak self] _, _ in
            print("[Signaling] 🔵 user-stopped-speaking")
            self?.onUserStoppedSpeaking?()
        }

        socket.on("ai-started-speaking") { [weak self] _, _ in
            print("[Signaling] 🔵 ai-started-speaking")
            self?.onAIStartedSpeaking?()
        }

        socket.on("ai-stopped-speaking") { [weak self] _, _ in
            print("[Signaling] 🔵 ai-stopped-speaking")
            self?.onAIStoppedSpeaking?()
        }

        socket.on("server-error") { [weak self] data, _ in
            let msg = (data.first as? [String: Any])?["message"] as? String ?? "Unknown server error"
            print("[Signaling] ⚠️ server-error: \(msg)")
            self?.onServerError?(msg)
        }

        socket.on("transport-error") { data, _ in
            print("[Signaling] ⚠️ transport-error from server: \(data)")
        }

        socket.on("producer-error") { data, _ in
            print("[Signaling] ⚠️ producer-error from server: \(data)")
        }

        socket.on("volume-changed") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            let volume = (d["volume"] as? NSNumber)?.doubleValue ?? -100
            let isAI   = (d["isAi"]   as? Bool) ?? false
            self?.onVolumeChanged?(volume, isAI)
        }

        socket.on("transcript-update") { [weak self] data, _ in
            guard let d = data.first as? [String: Any],
                  let text = d["text"] as? String else { return }
            self?.onTranscriptUpdate?(text)
        }
        socket.on("clear_action") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            let actionIds = d["action_ids"] as? [String] ?? []
            let sessionId = d["sessionId"] as? String ?? ""
            print("[Signaling] 🔵 clear_action received – ids: \(actionIds)")
            self?.onClearAction?(actionIds, sessionId)
        }

        // ──────────────────────────────────────────────
        // MARK: Meeting event listeners
        // ──────────────────────────────────────────────

        // Participant events
        socket.on("participant-joined") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onParticipantJoined?(d)
        }
        socket.on("participant-left") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onParticipantLeft?(d)
        }
        socket.on("participant-removed") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onParticipantRemoved?(d)
        }
        socket.on("participants-updated") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onParticipantsUpdated?(d)
        }

        // Host control events
        socket.on("you-were-muted") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onYouWereMuted?(d)
        }
        socket.on("you-were-removed") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onYouWereRemoved?(d)
        }
        socket.on("all-muted") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onAllMuted?(d)
        }
        socket.on("all-unmuted") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onAllUnmuted?(d)
        }
        socket.on("host-changed") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onHostChanged?(d)
        }
        socket.on("meeting-ended") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onMeetingEnded?(d)
        }
        socket.on("room-locked-changed") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onRoomLockedChanged?(d)
        }

        // Transcription events
        socket.on("transcription-toggled") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onTranscriptionToggled?(d)
        }
        socket.on("live-transcription") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onLiveTranscription?(d)
        }

        // Ask AI events
        socket.on("ask-ai-started") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onAskAiStarted?(d)
        }
        socket.on("ask-ai-processing") { [weak self] _, _ in
            self?.onAskAiProcessing?()
        }
        socket.on("ask-ai-cancelled") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onAskAiCancelled?(d)
        }

        // Text-only AI events
        socket.on("ask-ai-text-started") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onAskAiTextStarted?(d)
        }
        socket.on("ask-ai-text-chunk") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onAskAiTextChunk?(d)
        }
        socket.on("ask-ai-text-response") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onAskAiTextResponse?(d)
        }
        socket.on("ask-ai-text-error") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onAskAiTextError?(d)
        }

        // Waiting room events
        socket.on("waiting-room") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onWaitingRoom?(d)
        }
        socket.on("admitted") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onAdmitted?(d)
        }
        socket.on("denied") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onDenied?(d)
        }
        socket.on("waiting-room-updated") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onWaitingRoomUpdated?(d)
        }
        socket.on("waiting-room-toggled") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onWaitingRoomToggled?(d)
        }

        // AI differentiator events
        socket.on("summary-generating") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onSummaryGenerating?(d)
        }
        socket.on("summary-generated") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onSummaryGenerated?(d)
        }
        socket.on("minutes-generating") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onMinutesGenerating?(d)
        }
        socket.on("minutes-generated") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onMinutesGenerated?(d)
        }
        socket.on("bookmark-added") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onBookmarkAdded?(d)
        }
        socket.on("bookmark-removed") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onBookmarkRemoved?(d)
        }

        // Tool calls / actions
        socket.on("justin_action") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onJustinAction?(d)
        }
        socket.on("searching") { [weak self] data, _ in
            guard let d = data.first as? [String: Any] else { return }
            self?.onSearching?(d)
        }


        // Socket lifecycle
        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            print("[Signaling] ❌ Socket DISCONNECTED – reason: \(data)")
            self?.onDisconnect?()
        }
        socket.on(clientEvent: .reconnect) { data, _ in
            print("[Signaling] 🔄 Socket RECONNECT event: \(data)")
        }
        socket.on(clientEvent: .error) { [weak self] data, _ in
            let msg = (data.first as? String) ?? "Socket error"
            print("[Signaling] ❌ Socket ERROR event: \(data)")
            self?.onError?(msg)
        }
        socket.on(clientEvent: .statusChange) { data, _ in
            print("[Signaling] 🟡 Socket status change: \(data)")
        }
    }
}
