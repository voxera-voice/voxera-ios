import AVFoundation
import Foundation
import WebRTC

// MARK: - Public Types

/// Audio output route (speaker or earpiece)
public enum AudioOutputRoute {
    case speaker      // Loud speaker
    case earpiece     // Earphone/receiver
}

// MARK: - RocsClientDelegate

/// Callbacks mirroring the React Native SDK event emitter.
public protocol RocsClientDelegate: AnyObject {
    func client(_ client: RocsClient, didChangeConnectionStatus status: ConnectionStatus)
    func client(_ client: RocsClient, didChangeConversationStatus status: ConversationStatus)
    func client(_ client: RocsClient, didChangeSpeakingStatus status: SpeakingStatus)
    func client(_ client: RocsClient, didReceiveMessage message: ConversationMessage)
    func client(_ client: RocsClient, didFailWithError error: RocsError)
    func client(_ client: RocsClient, didReceiveRemoteAudioTrack track: RTCMediaStreamTrack)
    func client(_ client: RocsClient, didReceiveRemoteVideoTrack track: RTCMediaStreamTrack)
    func client(_ client: RocsClient, didUpdateAudioLevel level: Float)
    func client(_ client: RocsClient, didUpdateAIAudioLevel level: Float)
    func client(_ client: RocsClient, didUpdateTranscript transcript: String)

    // Meeting delegate methods
    func client(_ client: RocsClient, didUpdateParticipants participants: [RoomParticipant])
    func client(_ client: RocsClient, didUpdateRoomMode mode: RoomMode?)
    func client(_ client: RocsClient, didUpdateIsHost isHost: Bool)
    func client(_ client: RocsClient, didReceiveMeetingEvent event: String, data: [String: Any])
    func client(_ client: RocsClient, didReceiveTranscriptionEntry entry: TranscriptionEntry)
    func client(_ client: RocsClient, didUpdateWaitingRoom entries: [WaitingRoomEntry])
    func client(_ client: RocsClient, didReceiveBookmarkEvent bookmark: MeetingBookmark?, removed bookmarkId: String?)
    func client(_ client: RocsClient, didReceiveSummary summary: MeetingSummary)
    func client(_ client: RocsClient, didReceiveMinutes minutes: MeetingMinutes)
    func client(_ client: RocsClient, didReceiveAskAiTextChunk token: String)
    func client(_ client: RocsClient, didReceiveAskAiTextResponse text: String)
    func client(_ client: RocsClient, didReceiveToolCalls tools: [ToolCall], messageId: String)
    func client(_ client: RocsClient, didReceiveClearAction actionIds: [String], sessionId: String)
    func client(_ client: RocsClient, didStartSearching query: String)
}

public extension RocsClientDelegate {
    func client(_ client: RocsClient, didChangeConnectionStatus status: ConnectionStatus) {}
    func client(_ client: RocsClient, didChangeConversationStatus status: ConversationStatus) {}
    func client(_ client: RocsClient, didChangeSpeakingStatus status: SpeakingStatus) {}
    func client(_ client: RocsClient, didReceiveMessage message: ConversationMessage) {}
    func client(_ client: RocsClient, didFailWithError error: RocsError) {}
    func client(_ client: RocsClient, didReceiveRemoteAudioTrack track: RTCMediaStreamTrack) {}
    func client(_ client: RocsClient, didReceiveRemoteVideoTrack track: RTCMediaStreamTrack) {}
    func client(_ client: RocsClient, didUpdateAudioLevel level: Float) {}
    func client(_ client: RocsClient, didUpdateAIAudioLevel level: Float) {}
    func client(_ client: RocsClient, didUpdateTranscript transcript: String) {}

    // Meeting delegate defaults
    func client(_ client: RocsClient, didUpdateParticipants participants: [RoomParticipant]) {}
    func client(_ client: RocsClient, didUpdateRoomMode mode: RoomMode?) {}
    func client(_ client: RocsClient, didUpdateIsHost isHost: Bool) {}
    func client(_ client: RocsClient, didReceiveMeetingEvent event: String, data: [String: Any]) {}
    func client(_ client: RocsClient, didReceiveTranscriptionEntry entry: TranscriptionEntry) {}
    func client(_ client: RocsClient, didUpdateWaitingRoom entries: [WaitingRoomEntry]) {}
    func client(_ client: RocsClient, didReceiveBookmarkEvent bookmark: MeetingBookmark?, removed bookmarkId: String?) {}
    func client(_ client: RocsClient, didReceiveSummary summary: MeetingSummary) {}
    func client(_ client: RocsClient, didReceiveMinutes minutes: MeetingMinutes) {}
    func client(_ client: RocsClient, didReceiveAskAiTextChunk token: String) {}
    func client(_ client: RocsClient, didReceiveAskAiTextResponse text: String) {}
    func client(_ client: RocsClient, didReceiveToolCalls tools: [ToolCall], messageId: String) {}
    func client(_ client: RocsClient, didReceiveClearAction actionIds: [String], sessionId: String) {}
    func client(_ client: RocsClient, didStartSearching query: String) {}
}

// MARK: - RocsClient

/// Main iOS SDK client. Mirrors the React Native `RocsClient` API.
///
/// ```swift
/// let config = RocsConfig(appKey: "KEY", serverUrl: "wss://...")
/// let client = RocsClient(config: config)
/// client.delegate = self
/// await client.connect()
/// ```
public final class RocsClient {

    // MARK: - Public state

    public weak var delegate: RocsClientDelegate?

    public private(set) var connectionStatus:   ConnectionStatus   = .idle
    public private(set) var conversationStatus: ConversationStatus = .idle
    public private(set) var speakingStatus:     SpeakingStatus     = .none
    public private(set) var messages:           [ConversationMessage] = []
    public private(set) var sessionId:          String?
    public private(set) var isMuted:            Bool = false
    public private(set) var isListenMode:       Bool = false
    public private(set) var isVideoEnabled:     Bool = false
    public private(set) var isScreenSharing:    Bool = false
    public private(set) var audioLevel:         Float = 0
    public private(set) var aiAudioLevel:       Float = 0
    public private(set) var currentTranscript:  String = ""
    public private(set) var lastError:          RocsError?

    // Meeting state
    public private(set) var roomMode:            RoomMode?
    public private(set) var isHost:              Bool = false
    public private(set) var roomParticipants:    [RoomParticipant] = []
    public private(set) var transcriptions:      [TranscriptionEntry] = []
    public private(set) var waitingRoom:         [WaitingRoomEntry] = []
    public private(set) var bookmarks:           [MeetingBookmark] = []
    public private(set) var summaries:           [MeetingSummary] = []
    public private(set) var currentMinutes:      MeetingMinutes?
    public private(set) var isTranscriptionEnabled: Bool = false
    public private(set) var isAskAiActive:       Bool = false
    public private(set) var isRoomLocked:        Bool = false
    public private(set) var isWaitingRoomEnabled: Bool = false
    public private(set) var isInWaitingRoom:     Bool = false
    public private(set) var askAiTextResponse:   String = ""
    public private(set) var isAskAiTextProcessing: Bool = false

    public var isConnected:          Bool { connectionStatus == .connected }
    public var isConnecting:         Bool { connectionStatus == .connecting }
    public var isConversationActive: Bool { conversationStatus == .active }
    public var isUserSpeaking:       Bool { speakingStatus == .user }
    public var isAISpeaking:         Bool { speakingStatus == .ai }

    // MARK: - Private

    private var config:    RocsConfig
    private var signaling: SocketSignaling?
    private var webRTC:    WebRTCManager?
    private var meetingCallbacks = MeetingCallbacks()

    // MARK: - Init

    public init(config: RocsConfig) {
        precondition(!config.appKey.isEmpty,    "RocsConfig.appKey must not be empty")
        precondition(!config.serverUrl.isEmpty, "RocsConfig.serverUrl must not be empty")
        self.config = config
    }

    // MARK: - Connect / Disconnect

    public func connect() {
        guard connectionStatus == .idle || connectionStatus == .disconnected || connectionStatus == .error else { return }
        setConnectionStatus(.connecting)
        Task { await _connect() }
    }

    public func disconnect() {
        signaling?.disconnect()
        webRTC?.cleanup()
        webRTC    = nil
        signaling = nil
        setConnectionStatus(.disconnected)
        setConversationStatus(.idle)
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
        meetingCallbacks = MeetingCallbacks()
    }

    // MARK: - Conversation

    public func startConversation() {
        guard isConnected else {
            print("[RocsClient] ⚠️ startConversation called but not connected")
            return
        }
        if conversationStatus == .active { return }
        print("[RocsClient] 🔵 startConversation emitting conversation:start")
        setConversationStatus(.starting)
        isMuted = false
        signaling?.emit("conversation:start", data: [:])
        setConversationStatus(.active)
    }

    public func endConversation() {
        guard conversationStatus == .active else { return }
        setConversationStatus(.ending)
        signaling?.emit("conversation:end", data: [:])
        webRTC?.cleanup(); webRTC = nil
        setConversationStatus(.idle)
        setSpeakingStatus(.none)
    }

    public func sendMessage(_ text: String) {
        guard isConnected else { return }
        Task {
            _ = await emit("send-message", data: ["sessionId": sessionId ?? "", "message": text])
        }
    }

    public func selectAction(message: String, actionId: String) {
        guard isConversationActive else { return }
        
        Task {
            _ = await emit("select-actions", data: [
                "message": message,
                "event": "justin_action_output",
                "action_id": actionId
            ])
        }
    }

    // MARK: - Media controls

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        webRTC?.setMuted(muted)
    }

    public func toggleMute() { setMuted(!isMuted) }

    // MARK: - Audio Output Control
    
    /// Current audio output route
    public var currentAudioRoute: AudioOutputRoute {
        webRTC?.currentAudioRoute ?? .speaker
    }
    
    /// Set audio output route (speaker or earpiece)
    public func setAudioOutput(_ route: AudioOutputRoute) {
        webRTC?.setAudioOutput(route)
    }
    
    /// Toggle audio output between speaker and earpiece
    public func toggleAudioOutput() {
        webRTC?.toggleAudioOutput()
    }

    public func setListenMode(_ listen: Bool) {
        isListenMode = listen
        webRTC?.setMuted(listen)
    }

    public func toggleListenMode() { setListenMode(!isListenMode) }

    public func enableVideo(track: RTCVideoTrack) {
        isVideoEnabled = true
        Task { try? await webRTC?.produceVideoTrack(track) }
    }

    public func disableVideo() {
        isVideoEnabled = false
        // producer.close() handled by WebRTCManager cleanup
    }

    public func toggleVideo(track: RTCVideoTrack) {
        if isVideoEnabled { disableVideo() } else { enableVideo(track: track) }
    }

    // MARK: - Camera convenience

    /// The local video track produced by the camera. Nil when camera is off.
    public var localVideoTrack: RTCVideoTrack? { webRTC?.localVideoTrack }

    /// Current camera position (.front or .back).
    public var cameraPosition: AVCaptureDevice.Position { webRTC?.cameraPosition ?? .front }

    /// Start the camera and produce a video track to the server.
    public func startCamera(position: AVCaptureDevice.Position = .front) async throws {
        // Request camera permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                throw RocsError("Camera access denied. Allow in Settings > Privacy > Camera.", code: .mediaAccessDenied)
            }
        } else if status == .denied || status == .restricted {
            throw RocsError("Camera access denied. Allow in Settings > Privacy > Camera.", code: .mediaAccessDenied)
        }

        guard let mgr = webRTC else {
            throw RocsError("WebRTC not initialized. Connect first.", code: .webRTCError)
        }
        try await mgr.startCamera(position: position)
        isVideoEnabled = true
    }

    /// Stop the camera and close the video producer.
    public func stopCamera() {
        webRTC?.stopCamera()
        isVideoEnabled = false
    }

    /// Switch between front/back camera.
    public func switchCamera() {
        try? webRTC?.switchCamera()
    }

    public func startScreenShare(track: RTCVideoTrack) {
        isScreenSharing = true
        Task { try? await webRTC?.produceVideoTrack(track) }
    }

    public func stopScreenShare() { isScreenSharing = false }

    public func toggleScreenShare(track: RTCVideoTrack) {
        if isScreenSharing { stopScreenShare() } else { startScreenShare(track: track) }
    }

    // MARK: - Meeting configuration

    public func setMeetingCallbacks(_ callbacks: MeetingCallbacks) {
        self.meetingCallbacks = callbacks
    }

    public func setRoomInfo(roomMode: RoomMode?, isHost: Bool) {
        self.roomMode = roomMode
        self.isHost = isHost
        delegate?.client(self, didUpdateRoomMode: roomMode)
        delegate?.client(self, didUpdateIsHost: isHost)
    }

    // MARK: - Meeting: Socket-only connect (multi-room)

    public func connectSocketOnly() {
        guard connectionStatus == .idle || connectionStatus == .disconnected || connectionStatus == .error else { return }
        setConnectionStatus(.connecting)
        Task {
            do {
                let sig = SocketSignaling(serverUrl: config.serverUrl)
                self.signaling = sig
                setupSignalingCallbacks(sig)
                setupMeetingSignalingCallbacks(sig)
                try await connectSocket(sig)
                setConnectionStatus(.connected)
            } catch {
                handleError(RocsError(error.localizedDescription, code: .connectionFailed))
            }
        }
    }

    public func setupRoomWebRTC() {
        guard let sig = signaling else { return }
        Task {
            do {
                let granted = await requestMicrophonePermission()
                guard granted else {
                    handleError(RocsError("Microphone access denied.", code: .mediaAccessDenied))
                    return
                }

                configureAudioSession()

                let rtpResult = await emitSig(sig, "getRtpCapabilities", data: [:])
                guard let rtpCapsDict = rtpResult.first as? [String: Any],
                      let rtpCapsData = try? JSONSerialization.data(withJSONObject: rtpCapsDict),
                      let rtpCapsStr  = String(data: rtpCapsData, encoding: .utf8)
                else { throw RocsError("No RTP capabilities", code: .webRTCError) }

                print("[RocsClient] 🔵 Creating WebRTCManager...")
                let mgr = WebRTCManager()
                self.webRTC = mgr
                setupWebRTCCallbacks(mgr)
                
                print("[RocsClient] 🔵 Loading device with router RTP capabilities...")
                do {
                    try await mgr.loadDevice(routerRtpCapabilities: rtpCapsStr)
                    print("[RocsClient] ✅ Device loaded")
                } catch {
                    print("[RocsClient] ❌ Device load error: \(error)")
                    throw error
                }
                
                let myRtpCaps = try mgr.rtpCapabilities()

                let iceResult = await emitSig(sig, "getIceServers", data: [:])
                print("[RocsClient] 🔵 ICE servers result: \(iceResult)")
                if let iceServers = iceResult.first as? [[String: Any]] {
                    print("[RocsClient] 🔵 ICE servers count: \(iceServers.count)")
                    mgr.setIceServers(iceServers)
                } else {
                    print("[RocsClient] ⚠️ No ICE servers received")
                }

                let sendParamsResult = await emitSig(sig, "createTransport", data: [:])
                if let sp = sendParamsResult.first as? [String: Any] {
                    print("[RocsClient] 🔵 Send transport params keys: \(sp.keys.sorted())")
                    mgr.onSendTransportConnect = { [weak self] dtls in
                        guard let self else {
                            print("[RocsClient] ⚠️ connectTransport (send) - self is nil!")
                            return
                        }
                        let tId = sp["id"] as? String ?? ""
                        print("[RocsClient] 🔵 connectTransport (send) - transportId: \(tId)")
                        let result = await self.emitSig(sig, "connectTransport", data: ["transportId": tId, "dtlsParameters": self.jsonObj(dtls)])
                        print("[RocsClient] 🔵 connectTransport (send) result: \(result)")
                    }
                    mgr.onProduceCallback = { [weak self] tId, kind, rtpParams, cb in
                        guard let self else { cb(nil); return }
                        Task {
                            let res = await self.emitSig(sig, "produce", data: [
                                "transportId": tId, "kind": kind, "rtpParameters": self.jsonObj(rtpParams)
                            ])
                            cb(res.first.flatMap { $0 as? [String: Any] }?["id"] as? String)
                        }
                    }
                    print("[RocsClient] 🔵 Creating send transport...")
                    do {
                        try mgr.createSendTransport(params: sp)
                        print("[RocsClient] ✅ Send transport created")
                    } catch {
                        print("[RocsClient] ❌ createSendTransport error: \(error)")
                        throw error
                    }
                }

                let recvParamsResult = await emitSig(sig, "createTransport", data: ["consuming": true])
                if let rp = recvParamsResult.first as? [String: Any] {
                    mgr.onRecvTransportConnect = { [weak self] dtls in
                        guard let self else { return }
                        let tId = rp["id"] as? String ?? ""
                        _ = await self.emitSig(sig, "connectTransport", data: ["transportId": tId, "dtlsParameters": self.jsonObj(dtls)])
                    }
                    print("[RocsClient] 🔵 Creating receive transport...")
                    do {
                        try mgr.createRecvTransport(params: rp)
                        print("[RocsClient] ✅ Receive transport created")
                    } catch {
                        print("[RocsClient] ❌ createRecvTransport error: \(error)")
                        throw error
                    }
                }

                let joinResult = await emitSig(sig, "join", data: [
                    "sessionId": sessionId ?? "",
                    "appKey": config.appKey,
                    "rtpCapabilities": jsonObj(myRtpCaps)
                ])
                if let producers = joinResult.first as? [[String: Any]] {
                    for producer in producers {
                        try await consumeProducer(producer, mgr: mgr, sig: sig, myRtpCaps: myRtpCaps)
                    }
                }

                print("[RocsClient] 🔵 Producing audio...")
                do {
                    try? await mgr.produceAudio()
                    print("[RocsClient] ✅ Audio produced")
                } catch {
                    print("[RocsClient] ❌ Produce audio error: \(error)")
                }
            } catch {
                print("[RocsClient] ❌ _connect error: \(error)")
                handleError(RocsError(error.localizedDescription, code: .webRTCError))
            }
        }
    }

    public func setupMeetingListeners() {
        guard let sig = signaling else { return }
        setupMeetingSignalingCallbacks(sig)
    }

    // MARK: - Host control methods

    public func muteParticipant(targetClientId: String) {
        Task { _ = await emit("mute-participant", data: ["sessionId": sessionId ?? "", "targetClientId": targetClientId]) }
    }

    public func muteAll() {
        Task { _ = await emit("mute-all", data: ["sessionId": sessionId ?? ""]) }
    }

    public func unmuteAll() {
        Task { _ = await emit("unmute-all", data: ["sessionId": sessionId ?? ""]) }
    }

    public func removeParticipant(targetClientId: String) {
        Task { _ = await emit("remove-participant", data: ["sessionId": sessionId ?? "", "targetClientId": targetClientId]) }
    }

    public func lockRoom(_ locked: Bool) {
        Task { _ = await emit("lock-room", data: ["sessionId": sessionId ?? "", "locked": locked]) }
    }

    public func endMeeting() {
        Task { _ = await emit("end-meeting", data: ["sessionId": sessionId ?? ""]) }
    }

    public func transferHost(targetClientId: String) {
        Task { _ = await emit("transfer-host", data: ["sessionId": sessionId ?? "", "targetClientId": targetClientId]) }
    }

    public func toggleTranscription(_ enabled: Bool) {
        Task { _ = await emit("toggle-transcription", data: ["sessionId": sessionId ?? "", "enabled": enabled]) }
    }

    public func askAi() {
        Task { _ = await emit("ask-ai", data: ["sessionId": sessionId ?? ""]) }
    }

    public func cancelAskAi() {
        Task { _ = await emit("cancel-ask-ai", data: ["sessionId": sessionId ?? ""]) }
    }

    public func askAiText(prompt: String? = nil) {
        var data: [String: Any] = ["sessionId": sessionId ?? ""]
        if let prompt { data["prompt"] = prompt }
        Task { _ = await emit("ask-ai-text", data: data) }
    }

    public func enableWaitingRoom(_ enabled: Bool) {
        Task { _ = await emit("enable-waiting-room", data: ["sessionId": sessionId ?? "", "enabled": enabled]) }
    }

    public func admitParticipant(targetClientId: String) {
        Task { _ = await emit("admit-participant", data: ["sessionId": sessionId ?? "", "targetClientId": targetClientId]) }
    }

    public func denyParticipant(targetClientId: String) {
        Task { _ = await emit("deny-participant", data: ["sessionId": sessionId ?? "", "targetClientId": targetClientId]) }
    }

    public func admitAll() {
        Task { _ = await emit("admit-all", data: ["sessionId": sessionId ?? ""]) }
    }

    // MARK: - AI differentiator methods

    public func generateSummary() {
        Task { _ = await emit("generate-summary", data: ["sessionId": sessionId ?? ""]) }
    }

    public func generateMinutes() {
        Task { _ = await emit("generate-minutes", data: ["sessionId": sessionId ?? ""]) }
    }

    public func addBookmark(label: String, isActionItem: Bool = false) {
        Task { _ = await emit("add-bookmark", data: ["sessionId": sessionId ?? "", "label": label, "isActionItem": isActionItem]) }
    }

    public func removeBookmark(bookmarkId: String) {
        Task { _ = await emit("remove-bookmark", data: ["sessionId": sessionId ?? "", "bookmarkId": bookmarkId]) }
    }

    public func getBookmarks() {
        Task {
            let result = await emit("get-bookmarks", data: ["sessionId": sessionId ?? ""])
            if let arr = result.first as? [[String: Any]] {
                bookmarks = arr.compactMap { MeetingBookmark(dict: $0) }
            }
        }
    }

    public func getTranscript() {
        Task {
            let result = await emit("get-transcript", data: ["sessionId": sessionId ?? ""])
            if let arr = result.first as? [[String: Any]] {
                transcriptions = arr.compactMap { TranscriptionEntry(dict: $0) }
            }
        }
    }

    public func getSummaries() {
        Task {
            let result = await emit("get-summaries", data: ["sessionId": sessionId ?? ""])
            if let arr = result.first as? [[String: Any]] {
                summaries = arr.compactMap { MeetingSummary(dict: $0) }
            }
        }
    }

    public func getMinutes() {
        Task {
            let result = await emit("get-minutes", data: ["sessionId": sessionId ?? ""])
            if let dict = result.first as? [String: Any] {
                currentMinutes = MeetingMinutes(dict: dict)
            }
        }
    }

    // MARK: - Stats / Config

    public func getStats() async -> WebRTCStats? {
        guard let raw = webRTC?.getStats() else { return nil }
        guard let data = raw.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return WebRTCStats(raw: dict)
    }

    public func updateConfig(_ update: RocsConfigUpdate) {
        // Config updates now managed server-side via agent settings
    }

    public func clearError() { lastError = nil }

    // MARK: - Private connection flow

    private func _connect() async {
        do {
            // 1. Request mic permission
            let granted = await requestMicrophonePermission()
            guard granted else {
                handleError(RocsError("Microphone access denied. Allow in Settings > Privacy > Microphone.", code: .mediaAccessDenied))
                return
            }

            // 1.5. Configure audio session for loudspeaker output
            configureAudioSession()

            // 2. Generate the session ID client-side; no REST bootstrap is required.
            sessionId = config.sessionId ?? UUID().uuidString

            // 3. Connect socket
            let sig = SocketSignaling(serverUrl: config.serverUrl)
            self.signaling = sig
            setupSignalingCallbacks(sig)
            setupMeetingSignalingCallbacks(sig)
            try await connectSocket(sig)

            // 4. Initialize the managed voice-session connection.
            let initResult = await emitSig(sig, "init-session-connection", data: sessionPayload())
            print("[RocsClient] 🔵 init-session-connection result: \(initResult)")

            // 5. Get router RTP capabilities
            let rtpResult = await emitSig(sig, "getRtpCapabilities", data: [:])
            guard let rtpCapsDict = rtpResult.first as? [String: Any],
                  let rtpCapsData = try? JSONSerialization.data(withJSONObject: rtpCapsDict),
                  let rtpCapsStr  = String(data: rtpCapsData, encoding: .utf8)
            else { throw RocsError("No RTP capabilities from server", code: .webRTCError) }

            // Log router codecs for diagnostics
            if let codecs = rtpCapsDict["codecs"] as? [[String: Any]] {
                for c in codecs where (c["mimeType"] as? String)?.contains("opus") == true {
                    print("[RocsClient] 🔵 Router opus codec: pt=\(c["preferredPayloadType"] ?? "?"), params=\(c["parameters"] ?? [:]), rtcpFb=\(c["rtcpFeedback"] ?? [])")
                }
            }

            // 5.5. Patch RTP capabilities: add opus PT-101 for AI audio compatibility
            let patchedRtpCapsStr = Self.patchRtpCapabilities(rtpCapsStr)

            // 6. Create WebRTC manager and load device
            let mgr = WebRTCManager()
            self.webRTC = mgr
            setupWebRTCCallbacks(mgr)
            print("[RocsClient] 🔵 Loading device with router RTP capabilities...")
            try await mgr.loadDevice(routerRtpCapabilities: patchedRtpCapsStr)
            print("[RocsClient] ✅ Device loaded")

            // 7. Get ICE servers
            let iceResult = await emitSig(sig, "getIceServers", data: [:])
            print("[RocsClient] 🔵 ICE servers result: \(iceResult)")
            if let iceServers = iceResult.first as? [[String: Any]] {
                print("[RocsClient] 🔵 ICE servers count: \(iceServers.count)")
                mgr.setIceServers(iceServers)
            } else {
                print("[RocsClient] ⚠️ No ICE servers received")
            }

            // 8. Create the send transport using the shared signaling contract.
            let sendParamsResult = await emitSig(sig, "createTransport", data: [:])
            if let sp = sendParamsResult.first as? [String: Any] {
                mgr.onSendTransportConnect = { [weak self] dtls in
                    guard let self else { return }
                    let tId = sp["id"] as? String ?? ""
                    // Fire-and-forget (matches web client: socket.emit + cb() immediately)
                    sig.emit("connectTransport", data: ["transportId": tId, "dtlsParameters": self.jsonObj(dtls) as Any])
                    print("[RocsClient] 🔵 connectTransport (send) emitted for transport: \(tId)")
                }
                mgr.onProduceCallback = { [weak self] tId, kind, rtpParams, cb in
                    guard let self else { cb(nil); return }
                    print("[RocsClient] 🔵 produce emit - kind: \(kind), transportId: \(tId)")
                    print("[RocsClient] 🔵 produce rtpParameters: \(rtpParams.prefix(500))")
                    Task {
                        let res = await self.emitSig(sig, "produce", data: [
                            "transportId": tId, "kind": kind, "rtpParameters": self.jsonObj(rtpParams)
                        ])
                        let producerId = res.first.flatMap { $0 as? [String: Any] }?["id"] as? String
                        print("[RocsClient] 🔵 produce response: \(res), producerId: \(producerId ?? "nil")")
                        cb(producerId)
                    }
                }
                try mgr.createSendTransport(params: sp)
                print("[RocsClient] ✅ Send transport created")
            }

            // 9. Produce audio (triggers internal connect event)
            print("[RocsClient] 🔵 Producing audio...")
            try await mgr.produceAudio()
            print("[RocsClient] ✅ Audio produced")

            // 10. Create the receive transport using the shared signaling contract.
            let recvParamsResult = await emitSig(sig, "createTransport", data: [:])
            if let rp = recvParamsResult.first as? [String: Any] {
                mgr.onRecvTransportConnect = { [weak self] dtls in
                    guard let self else { return }
                    let tId = rp["id"] as? String ?? ""
                    // Fire-and-forget (matches web client: socket.emit + cb() immediately)
                    sig.emit("connectTransport", data: ["transportId": tId, "dtlsParameters": self.jsonObj(dtls) as Any])
                    print("[RocsClient] 🔵 connectTransport (recv) emitted for transport: \(tId)")
                }
                try mgr.createRecvTransport(params: rp)
                print("[RocsClient] ✅ Receive transport created")
            }

            // 11. new-producer events are handled via setupSignalingCallbacks

            setConnectionStatus(.connected)
            print("[RocsClient] ✅ _connect() completed successfully - connectionStatus: connected")

        } catch {
            print("[RocsClient] ❌ _connect error: \(error)")
            handleError(RocsError(error.localizedDescription, code: .connectionFailed))
        }
    }

    private func consumeProducer(_ producer: [String: Any], mgr: WebRTCManager, sig: SocketSignaling, myRtpCaps: String) async throws {
        // Server sends { producerId } in new-producer events
        let producerId = producer["producerId"] as? String ?? producer["id"] as? String ?? ""
        print("[RocsClient] 🔵 consumeProducer - producerId: \(producerId), producer: \(producer)")
        guard !producerId.isEmpty else {
            print("[RocsClient] consumeProducer: no producerId in \(producer)")
            return
        }

        let recvTransportId = mgr.recvTransportId ?? ""
        print("[RocsClient] 🔵 consumeProducer - calling consume with recvTransportId: \(recvTransportId)")
        let consumeResult = await emitSig(sig, "consume", data: [
            "producerId": producerId,
            "rtpCapabilities": jsonObj(myRtpCaps),
            "transportId": recvTransportId
        ])
        print("[RocsClient] 🔵 consumeProducer - consume result: \(consumeResult)")

        guard let consumeParams = consumeResult.first as? [String: Any] else {
            print("[RocsClient] consumeProducer: no consume response for producer \(producerId)")
            return
        }

        // kind comes from the consume response (matches web client)
        let kind = consumeParams["kind"] as? String ?? producer["kind"] as? String ?? "audio"

        if kind == "audio" {
            try await mgr.consumeAudio(params: consumeParams)
        } else {
            try await mgr.consumeVideo(params: consumeParams)
        }
    }

    // MARK: - Signaling helpers

    private func setupSignalingCallbacks(_ sig: SocketSignaling) {
        sig.onNewProducer = { [weak self] producer in
            guard let self, let mgr = self.webRTC else { return }
            Task {
                do {
                    let myRtpCaps = try mgr.rtpCapabilities()
                    try await self.consumeProducer(producer, mgr: mgr, sig: sig, myRtpCaps: myRtpCaps)
                } catch {
                    self.handleError(RocsError(error.localizedDescription, code: .webRTCError))
                }
            }
        }
        sig.onConversationStarted = { [weak self] in
            self?.setConversationStatus(.active)
        }
        sig.onConversationEnded   = { [weak self] _ in
            self?.setConversationStatus(.idle)
            self?.setSpeakingStatus(.none)
        }
        sig.onUserStartedSpeaking = { [weak self] in self?.setSpeakingStatus(.user) }
        sig.onUserStoppedSpeaking = { [weak self] in
            if self?.speakingStatus == .user { self?.setSpeakingStatus(.none) }
        }
        sig.onAIStartedSpeaking   = { [weak self] in self?.setSpeakingStatus(.ai) }
        sig.onAIStoppedSpeaking   = { [weak self] in
            if self?.speakingStatus == .ai { self?.setSpeakingStatus(.none) }
        }
        sig.onSearching = { [weak self] data in
            guard let self else { return }
            let query = data["query"] as? String ?? ""
            self.setSpeakingStatus(.searching)
            self.delegate?.client(self, didStartSearching: query)
            self.config.onSearching?(query)
        }
        sig.onNewMessage = { [weak self] msg in
            guard let self else { return }
            self.messages.append(msg)
            if self.speakingStatus == .searching { self.setSpeakingStatus(.none) }
            self.delegate?.client(self, didReceiveMessage: msg)
        }
        sig.onVolumeChanged = { [weak self] volume, isAI in
            guard let self else { return }
            // Server sends dBFS (range ~ -100…0). Normalize to 0…1 for UI.
            let clamped = Float(max(min(volume, 0), -100))
            let level = (clamped + 100) / 100
            if isAI {
                self.aiAudioLevel = level
                self.delegate?.client(self, didUpdateAIAudioLevel: level)
                self.config.onAIAudioLevelChange?(level)
            } else {
                self.audioLevel = level
                self.delegate?.client(self, didUpdateAudioLevel: level)
                self.config.onAudioLevelChange?(level)
            }
        }
        sig.onTranscriptUpdate = { [weak self] text in
            guard let self else { return }
            self.currentTranscript = text
            self.delegate?.client(self, didUpdateTranscript: text)
        }
        sig.onDisconnect = { [weak self] in
            self?.setConnectionStatus(.disconnected)
        }
        sig.onError = { [weak self] err in
            self?.handleError(RocsError(err, code: .connectionFailed))
        }
    }

    private func setupMeetingSignalingCallbacks(_ sig: SocketSignaling) {
        // Participant events
        sig.onParticipantJoined = { [weak self] data in
            guard let self else { return }
            if let participants = data["participants"] as? [[String: Any]] {
                self.roomParticipants = participants.compactMap { RoomParticipant(dict: $0) }
                self.delegate?.client(self, didUpdateParticipants: self.roomParticipants)
            }
            self.meetingCallbacks.onParticipantJoined?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "participant-joined", data: data)
        }
        sig.onParticipantLeft = { [weak self] data in
            guard let self else { return }
            if let participants = data["participants"] as? [[String: Any]] {
                self.roomParticipants = participants.compactMap { RoomParticipant(dict: $0) }
                self.delegate?.client(self, didUpdateParticipants: self.roomParticipants)
            }
            self.meetingCallbacks.onParticipantLeft?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "participant-left", data: data)
        }
        sig.onParticipantRemoved = { [weak self] data in
            guard let self else { return }
            if let participants = data["participants"] as? [[String: Any]] {
                self.roomParticipants = participants.compactMap { RoomParticipant(dict: $0) }
                self.delegate?.client(self, didUpdateParticipants: self.roomParticipants)
            }
            self.meetingCallbacks.onParticipantRemoved?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "participant-removed", data: data)
        }
        sig.onParticipantsUpdated = { [weak self] data in
            guard let self else { return }
            if let participants = data["participants"] as? [[String: Any]] {
                self.roomParticipants = participants.compactMap { RoomParticipant(dict: $0) }
                self.delegate?.client(self, didUpdateParticipants: self.roomParticipants)
            }
            self.meetingCallbacks.onParticipantsUpdated?(data)
        }

        // Host control events
        sig.onYouWereMuted = { [weak self] data in
            guard let self else { return }
            self.isMuted = true
            self.webRTC?.setMuted(true)
            self.meetingCallbacks.onYouWereMuted?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "you-were-muted", data: data)
        }
        sig.onYouWereRemoved = { [weak self] data in
            guard let self else { return }
            self.meetingCallbacks.onYouWereRemoved?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "you-were-removed", data: data)
            self.disconnect()
        }
        sig.onAllMuted = { [weak self] data in
            guard let self else { return }
            self.isMuted = true
            self.webRTC?.setMuted(true)
            self.meetingCallbacks.onAllMuted?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "all-muted", data: data)
        }
        sig.onAllUnmuted = { [weak self] data in
            guard let self else { return }
            self.meetingCallbacks.onAllUnmuted?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "all-unmuted", data: data)
        }
        sig.onHostChanged = { [weak self] data in
            guard let self else { return }
            let newHostId = data["newHostClientId"] as? String
            self.isHost = (newHostId == sig.socketId)
            self.delegate?.client(self, didUpdateIsHost: self.isHost)
            self.meetingCallbacks.onHostChanged?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "host-changed", data: data)
        }
        sig.onMeetingEnded = { [weak self] data in
            guard let self else { return }
            self.meetingCallbacks.onMeetingEnded?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "meeting-ended", data: data)
        }
        sig.onRoomLockedChanged = { [weak self] data in
            guard let self else { return }
            self.isRoomLocked = data["locked"] as? Bool ?? false
            self.meetingCallbacks.onRoomLockedChanged?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "room-locked-changed", data: data)
        }

        // Transcription events
        sig.onTranscriptionToggled = { [weak self] data in
            guard let self else { return }
            self.isTranscriptionEnabled = data["enabled"] as? Bool ?? false
            self.meetingCallbacks.onTranscriptionToggled?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "transcription-toggled", data: data)
        }
        sig.onLiveTranscription = { [weak self] data in
            guard let self else { return }
            if let entry = TranscriptionEntry(dict: data) {
                self.transcriptions.append(entry)
                self.delegate?.client(self, didReceiveTranscriptionEntry: entry)
            }
            self.meetingCallbacks.onLiveTranscription?(data)
        }

        // Ask AI events
        sig.onAskAiStarted = { [weak self] data in
            guard let self else { return }
            self.isAskAiActive = true
            self.meetingCallbacks.onAskAiStarted?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "ask-ai-started", data: data)
        }
        sig.onAskAiProcessing = { [weak self] in
            guard let self else { return }
            self.meetingCallbacks.onAskAiProcessing?()
        }
        sig.onAskAiCancelled = { [weak self] data in
            guard let self else { return }
            self.isAskAiActive = false
            self.meetingCallbacks.onAskAiCancelled?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "ask-ai-cancelled", data: data)
        }

        // Text-only AI events
        sig.onAskAiTextStarted = { [weak self] data in
            guard let self else { return }
            self.isAskAiTextProcessing = true
            self.askAiTextResponse = ""
            self.meetingCallbacks.onAskAiTextStarted?(data)
        }
        sig.onAskAiTextChunk = { [weak self] data in
            guard let self else { return }
            if let token = data["token"] as? String {
                self.askAiTextResponse += token
                self.delegate?.client(self, didReceiveAskAiTextChunk: token)
            }
            self.meetingCallbacks.onAskAiTextChunk?(data)
        }
        sig.onAskAiTextResponse = { [weak self] data in
            guard let self else { return }
            self.isAskAiTextProcessing = false
            if let text = data["text"] as? String {
                self.askAiTextResponse = text
                self.delegate?.client(self, didReceiveAskAiTextResponse: text)
            }
            self.meetingCallbacks.onAskAiTextResponse?(data)
        }
        sig.onAskAiTextError = { [weak self] data in
            guard let self else { return }
            self.isAskAiTextProcessing = false
            self.meetingCallbacks.onAskAiTextError?(data)
        }

        // Waiting room events
        sig.onWaitingRoom = { [weak self] data in
            guard let self else { return }
            self.isInWaitingRoom = true
            self.meetingCallbacks.onWaitingRoom?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "waiting-room", data: data)
        }
        sig.onAdmitted = { [weak self] data in
            guard let self else { return }
            self.isInWaitingRoom = false
            if let modeStr = data["roomMode"] as? String, let mode = RoomMode(rawValue: modeStr) {
                self.roomMode = mode
                self.delegate?.client(self, didUpdateRoomMode: mode)
            }
            self.meetingCallbacks.onAdmitted?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "admitted", data: data)
        }
        sig.onDenied = { [weak self] data in
            guard let self else { return }
            self.isInWaitingRoom = false
            self.meetingCallbacks.onDenied?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "denied", data: data)
        }
        sig.onWaitingRoomUpdated = { [weak self] data in
            guard let self else { return }
            if let entries = data["waitingRoom"] as? [[String: Any]] {
                self.waitingRoom = entries.compactMap { WaitingRoomEntry(dict: $0) }
                self.delegate?.client(self, didUpdateWaitingRoom: self.waitingRoom)
            }
            self.meetingCallbacks.onWaitingRoomUpdated?(data)
        }
        sig.onWaitingRoomToggled = { [weak self] data in
            guard let self else { return }
            self.isWaitingRoomEnabled = data["enabled"] as? Bool ?? false
            self.meetingCallbacks.onWaitingRoomToggled?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "waiting-room-toggled", data: data)
        }

        // AI differentiator events
        sig.onSummaryGenerating = { [weak self] data in
            guard let self else { return }
            self.meetingCallbacks.onSummaryGenerating?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "summary-generating", data: data)
        }
        sig.onSummaryGenerated = { [weak self] data in
            guard let self else { return }
            if let summary = MeetingSummary(dict: data) {
                self.summaries.append(summary)
                self.delegate?.client(self, didReceiveSummary: summary)
            }
            self.meetingCallbacks.onSummaryGenerated?(data)
        }
        sig.onMinutesGenerating = { [weak self] data in
            guard let self else { return }
            self.meetingCallbacks.onMinutesGenerating?(data)
            self.delegate?.client(self, didReceiveMeetingEvent: "minutes-generating", data: data)
        }
        sig.onMinutesGenerated = { [weak self] data in
            guard let self else { return }
            if let minutes = MeetingMinutes(dict: data) {
                self.currentMinutes = minutes
                self.delegate?.client(self, didReceiveMinutes: minutes)
            }
            self.meetingCallbacks.onMinutesGenerated?(data)
        }
        sig.onBookmarkAdded = { [weak self] data in
            guard let self else { return }
            if let bookmark = MeetingBookmark(dict: data) {
                self.bookmarks.append(bookmark)
                self.delegate?.client(self, didReceiveBookmarkEvent: bookmark, removed: nil)
            }
            self.meetingCallbacks.onBookmarkAdded?(data)
        }
        sig.onBookmarkRemoved = { [weak self] data in
            guard let self else { return }
            if let bookmarkId = data["bookmarkId"] as? String {
                self.bookmarks.removeAll { $0.id == bookmarkId }
                self.delegate?.client(self, didReceiveBookmarkEvent: nil, removed: bookmarkId)
            }
            self.meetingCallbacks.onBookmarkRemoved?(data)
        }

        // Tool calls / actions
        sig.onJustinAction = { [weak self] data in
            guard let self else { return }
            if let content = data["content"] as? [String: Any] {
                let actionId = content["action_id"] as? String ?? ""
                let name = content["name"] as? String ?? ""
                let args = content["arguments"] as? [String: Any] ?? [:]
                let tool = ToolCall(
                    id: actionId,
                    type: "function",
                    function: ToolCallFunction(name: name, arguments: args)
                )
                self.delegate?.client(self, didReceiveToolCalls: [tool], messageId: "")
            }
        }

        sig.onClearAction = { [weak self] actionIds, sessionId in
            guard let self else { return }
            print("[RocsClient] 🔵 clear_action – ids: \(actionIds), sessionId: \(sessionId)")
            self.delegate?.client(self, didReceiveClearAction: actionIds, sessionId: sessionId)
        }
    }

    private func setupWebRTCCallbacks(_ mgr: WebRTCManager) {
        mgr.onRemoteAudioTrack = { [weak self] track in
            guard let self else { return }
            self.delegate?.client(self, didReceiveRemoteAudioTrack: track)
            self.config.onRemoteAudioTrack?(track)
        }
        mgr.onRemoteVideoTrack = { [weak self] track in
            guard let self else { return }
            self.delegate?.client(self, didReceiveRemoteVideoTrack: track)
            self.config.onRemoteVideoTrack?(track)
        }
        mgr.onError = { [weak self] error in
            self?.handleError(RocsError(error.localizedDescription, code: .webRTCError))
        }
    }

    private func connectSocket(_ sig: SocketSignaling) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sig.connect { error in
                if let error {
                    cont.resume(throwing: RocsError(error.localizedDescription, code: .connectionFailed))
                } else {
                    cont.resume()
                }
            }
        }
    }

    /// Patch RTP capabilities to add opus PT-101 copy for AI audio compatibility.
    /// Mirrors the web-client patchRtpCapabilities logic.
    static func patchRtpCapabilities(_ rtpCapsJson: String) -> String {
        guard let data = rtpCapsJson.data(using: .utf8),
              var caps = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var codecs = caps["codecs"] as? [[String: Any]]
        else { return rtpCapsJson }

        // Find the first opus codec
        if let opusIndex = codecs.firstIndex(where: { ($0["mimeType"] as? String)?.lowercased() == "audio/opus" }) {
            var opusCopy = codecs[opusIndex]
            opusCopy["preferredPayloadType"] = 101
            codecs.append(opusCopy)
            caps["codecs"] = codecs
        }

        guard let patched = try? JSONSerialization.data(withJSONObject: caps),
              let result  = String(data: patched, encoding: .utf8)
        else { return rtpCapsJson }
        return result
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    /// Configure AVAudioSession so audio plays through the loudspeaker (not earpiece).
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setMode(.voiceChat)
            try session.setActive(true)
        } catch {
            print("[RocsClient] Failed to configure audio session: \(error)")
        }
    }

    private func emitSig(_ sig: SocketSignaling, _ event: String, data: [String: Any]) async -> [Any] {
        await withCheckedContinuation { cont in
            sig.emitWithAck(event, data: data) { items in cont.resume(returning: items) }
        }
    }

    private func emit(_ event: String, data: [String: Any]) async -> [Any] {
        guard let sig = signaling else { return [] }
        return await emitSig(sig, event, data: data)
    }

    /// Parse a JSON string from mediasoup-client into a dictionary so Socket.IO sends it as an object.
    private func jsonObj(_ str: String) -> Any {
        if let data = str.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) { return obj }
        return str
    }

    private func sessionPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "protocol":     "voxera",
            "protocolVersion": "1.0",
            "sessionId":    sessionId ?? "",
            "threadId":     config.threadId ?? sessionId ?? "",
            "chatProfile":  config.chatProfile ?? "",
            "userId":       config.userId ?? "ios-user",
            "user":         config.user as Any,
            "clientType":   "ios",
            "appKey":       config.appKey,
        ]
        if let agentId = config.agentId ?? config.configurationId {
            payload["agentId"] = agentId
        }
        if let tts = config.ttsConfig       { payload["ttsConfig"] = tts }
        if let tx  = config.transcriptionConfig { payload["transcriptionConfig"] = tx }
        if let mc  = config.modelConfig      { payload["modelConfig"] = mc }
        if let tools = config.tools          { payload["tools"] = tools }
        if let prompts = config.additionalSystemPrompts {
            payload["additionalSystemPrompts"] = prompts
        }
        if let im  = config.initialMessages  { payload["initialMessages"] = im }
        if let sm  = config.selectedModel    { payload["selectedModel"] = sm }
        if let sv  = config.selectedVoice    { payload["selectedVoice"] = sv }
        if let ws  = config.workspaceId      { payload["workspaceId"] = ws }
        if let un  = config.username          { payload["username"] = un }
        if let ui  = config.userInfo          { payload["userInfo"] = ui }
        if let md  = config.metadata, !md.isEmpty { payload["metadata"] = md }
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withTimeZone]
        iso8601.timeZone = TimeZone.current
        payload["clientDateTime"] = iso8601.string(from: Date())
        return payload
    }

    // MARK: - Status helpers

    private func setConnectionStatus(_ s: ConnectionStatus) {
        connectionStatus = s
        delegate?.client(self, didChangeConnectionStatus: s)
        config.onConnectionStatusChange?(s)
    }

    private func setConversationStatus(_ s: ConversationStatus) {
        conversationStatus = s
        delegate?.client(self, didChangeConversationStatus: s)
        config.onConversationStatusChange?(s)
    }

    private func setSpeakingStatus(_ s: SpeakingStatus) {
        speakingStatus = s
        delegate?.client(self, didChangeSpeakingStatus: s)
        config.onSpeakingStatusChange?(s)
    }

    private func handleError(_ error: RocsError) {
        lastError = error
        setConnectionStatus(.error)
        delegate?.client(self, didFailWithError: error)
        config.onError?(error)
    }
}
