// ContentView — Rocs iOS Demo
// Matches the React Native ROCS demo: setup screen + active call screen.

import SwiftUI
import RocsSDK
import JitsiMeetSDK

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Voice options (static)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct StaticVoice: Identifiable {
    let id: String       // label sent to server: "emma" or "sara"
    let label: String
    let description: String
}

private let kStaticVoices: [StaticVoice] = [
    StaticVoice(id: "emma", label: "Emma",  description: "Default voice · BosonAI"),
    StaticVoice(id: "sara", label: "Sara",  description: "ElevenLabs · Multilingual"),
]

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Status config (conversation pill)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct StatusCfg {
    let icon: String
    let color: Color
    let label: String
    let shouldPulse: Bool
}

private let statusConfigs: [ConversationStatus: StatusCfg] = [
    .idle:       StatusCfg(icon: "○", color: Color(hex: "#94a3b8"), label: "Idle",        shouldPulse: false),
    .active:     StatusCfg(icon: "◉", color: Color(hex: "#3b82f6"), label: "Listening",   shouldPulse: true),
]

private func statusCfgFor(_ status: ConversationStatus, speaking: SpeakingStatus) -> StatusCfg {
    if speaking == .ai   { return StatusCfg(icon: "●", color: Color(hex: "#10b981"), label: "AI Speaking", shouldPulse: true) }
    if speaking == .user { return StatusCfg(icon: "◉", color: Color(hex: "#3b82f6"), label: "Listening",   shouldPulse: true) }
    return statusConfigs[status] ?? StatusCfg(icon: "○", color: Color(hex: "#94a3b8"), label: "Idle", shouldPulse: false)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Observation wrapper (ObservableObject + @State fix)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// @State does not subscribe to @Published changes on ObservableObject classes.
/// This wrapper holds `@ObservedObject` so SwiftUI properly re-renders when
/// any @Published property changes (mute, listen mode, volume, status, etc.).
private struct _Observed<VM: ObservableObject, Content: View>: View {
    @ObservedObject var vm: VM
    @ViewBuilder let content: (VM) -> Content
    var body: some View { content(vm) }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - ContentView
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct ContentView: View {

    // MARK: - State

    @State private var selectedServerId = Config.defaultServerId
    @State private var customServerUrl  = ""
    @State private var isServerMenuOpen = false
    @State private var selectedVoiceId  = "emma"

    // Session config inputs
    @State private var appKeyInput   = Config.appKey
    @State private var userIdInput   = Config.userId
     @State private var threadIdInput = UUID().uuidString
//    @State private var threadIdInput = "12d13b34-df89-4f4a-a7e4-8d5d387dae31"

    // Active-call state
    @State private var vm: RocsViewModel?
    @State private var activeSheet: ActiveSheet?
    @State private var textInput      = ""
    @State private var bookmarkLabel  = ""
    @State private var askAiPrompt    = ""
    @State private var lastJustinActionJson  = ""
    @State private var lastSelectActionsJson = ""
    @FocusState private var inputFocused: Bool

    enum ActiveSheet: Identifiable {
        case participants, transcription, aiTools
        var id: Int { hashValue }
    }

    private var actualServerUrl: String {
        if selectedServerId == "custom" { return customServerUrl }
        return Config.servers.first(where: { $0.id == selectedServerId })?.url ?? ""
    }

    private var isValidUrl: Bool {
        guard let url = URL(string: actualServerUrl),
              let scheme = url.scheme,
              (scheme == "http" || scheme == "https") else { return false }
        return true
    }

    private var canStart: Bool {
        isValidUrl
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let vm = vm {
                _Observed(vm: vm) { vm in
                    if vm.isConnected || vm.isConnecting {
                        activeCallView(vm: vm)
                            .onChange(of: vm.connectionStatus) { status in
                                if status == .connected {
                                    vm.startConversation()
                                }
                                if status == .disconnected {
                                    self.vm = nil
                                }
                            }
                    } else {
                        setupView
                    }
                }
            } else {
                setupView
            }
        }

    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Setup View (Pre-Call)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var setupView: some View {
        ZStack {
            Color(hex: "#0f172a").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ROCS")
                            .font(.system(size: 40, weight: .heavy))
                            .foregroundStyle(.white)
                            .tracking(-1)
                        Text("Real-time AI voice conversations")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#64748b"))
                    }
                    .padding(.bottom, 8)

                    // Error banner
                    if let vm = vm, let err = vm.error {
                        HStack(spacing: 8) {
                            Text("⚠️")
                            Text(err.message)
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.red.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // ── Server card ──
                    setupCard {
                        Text("🌐 SERVER")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "#94a3b8"))
                            .tracking(0.5)

                        // Dropdown picker
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isServerMenuOpen.toggle()
                            }
                        } label: {
                            HStack {
                                Text(Config.servers.first(where: { $0.id == selectedServerId })?.label ?? "Select…")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(hex: "#e2e8f0"))
                                Spacer()
                                Text(isServerMenuOpen ? "▲" : "▼")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: "#64748b"))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color(hex: "#0f172a"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#334155"), lineWidth: 1))
                        }

                        if isServerMenuOpen {
                            VStack(spacing: 0) {
                                ForEach(Config.servers) { server in
                                    Button {
                                        selectedServerId = server.id
                                        withAnimation { isServerMenuOpen = false }
                                    } label: {
                                        Text(server.label)
                                            .font(.system(size: 13))
                                            .foregroundStyle(selectedServerId == server.id ? .white : Color(hex: "#e2e8f0"))
                                            .fontWeight(selectedServerId == server.id ? .semibold : .regular)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 14).padding(.vertical, 12)
                                            .background(selectedServerId == server.id ? Color(hex: "#1d4ed8") : Color.clear)
                                    }
                                    if server.id != Config.servers.last?.id {
                                        Divider().background(Color(hex: "#1e293b"))
                                    }
                                }
                            }
                            .background(Color(hex: "#0f172a"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#334155"), lineWidth: 1))
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                        }

                        if selectedServerId == "custom" {
                            TextField("https://your-server.example.com", text: $customServerUrl)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#e2e8f0"))
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(Color(hex: "#0f172a"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#334155"), lineWidth: 1))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)

                            if !customServerUrl.isEmpty && !isValidUrl {
                                Text("⚠️ Enter a valid http/https URL")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                        }

                        // URL display
                        HStack(spacing: 4) {
                            Text("URL:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "#64748b"))
                            Text(actualServerUrl.isEmpty ? "—" : actualServerUrl)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: "#94a3b8"))
                                .lineLimit(1)
                        }
                        .padding(.top, 4)
                    }

                    // ── Voice card ──
                    setupCard {
                        Text("🎙 VOICE")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "#94a3b8"))
                            .tracking(0.5)

                        HStack(spacing: 10) {
                            ForEach(kStaticVoices) { voice in
                                let selected = selectedVoiceId == voice.id
                                Button { selectedVoiceId = voice.id } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(voice.label)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(selected ? .white : Color(hex: "#e2e8f0"))
                                        Text(voice.description)
                                            .font(.system(size: 11))
                                            .foregroundStyle(selected ? Color.white.opacity(0.75) : Color(hex: "#64748b"))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(selected ? Color(hex: "#1d4ed8") : Color(hex: "#0f172a"))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                        selected ? Color(hex: "#3b82f6") : Color(hex: "#334155"), lineWidth: 1))
                                }
                            }
                        }
                    }

                    // ── Session config card ──
                    setupCard {
                        Text("🔑 SESSION")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "#94a3b8"))
                            .tracking(0.5)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("App Key")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "#64748b"))
                            TextField("App Key", text: $appKeyInput)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#e2e8f0"))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color(hex: "#0f172a"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#334155"), lineWidth: 1))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("User ID")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "#64748b"))
                            TextField("User ID", text: $userIdInput)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#e2e8f0"))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color(hex: "#0f172a"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#334155"), lineWidth: 1))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Thread ID")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(hex: "#64748b"))
                                Spacer()
                                Button {
                                     threadIdInput = UUID().uuidString
//                                    threadIdInput = "12d13b34-df89-4f4a-a7e4-8d5d387dae31"
                                } label: {
                                    Text("↻ New")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#3b82f6"))
                                }
                            }
                            TextField("Thread ID", text: $threadIdInput)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#e2e8f0"))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color(hex: "#0f172a"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#334155"), lineWidth: 1))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }

                    // ── Start button ──
                    Button { handleStart() } label: {
                        HStack(spacing: 10) {
                            Text("📞")
                                .font(.system(size: 22))
                            Text("Start Call")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(canStart ? Color(hex: "#10b981") : Color(hex: "#1e293b"))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private func setupCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .background(Color(hex: "#1e293b"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Active Call View
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func activeCallView(vm: RocsViewModel) -> some View {
        ZStack {
            // Background — remote video when available, solid color otherwise
            if let remoteTrack = vm.remoteVideoTrack as? RTCVideoTrack {
                RTCVideoUIView(track: remoteTrack)
                    .ignoresSafeArea()
                Color.black.opacity(0.3).ignoresSafeArea()
            } else {
                Color(hex: "#0f172a").ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // ── Top status bar ──
                topBar(vm: vm)

                // ── Listen mode banner ──
                if vm.isListenMode {
                    HStack(spacing: 6) {
                        Text("👂")
                            .font(.system(size: 16))
                        Text("LISTEN MODE — Microphone muted")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .tracking(0.5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(hex: "#8b5cf6").opacity(0.85))
                }

                // ── Waiting room ──
                if vm.isInWaitingRoom {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Waiting for the host to admit you…")
                            .font(.callout).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#f59e0b").opacity(0.2))
                }

                if vm.isHost && !vm.waitingRoom.isEmpty {
                    waitingRoomHostBar(vm: vm)
                }

                // ── Main content area ──
                mainContentArea(vm: vm)

                // ── Subtitle strip (AI speech text) ──
                if !vm.currentTranscript.isEmpty && vm.isConversationActive {
                    Text(vm.currentTranscript)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                // ── Searching indicator ──
                if vm.speakingStatus == .searching && vm.isConversationActive {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color(hex: "#a78bfa"))
                            .scaleEffect(0.8)
                        Text("Searching…")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "#a78bfa"))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
                }

                // ── Tool calls / actions buttons ──
                if !vm.toolCalls.isEmpty && vm.isConversationActive {
                    toolCallsView(vm: vm)
                }

                // ── Text input (during conversation) ──
                if vm.isConversationActive {
                    HStack(spacing: 8) {
                        TextField("Message…", text: $textInput)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                            .tint(Color(hex: "#a78bfa"))
                            .focused($inputFocused)
                            .submitLabel(.send)
                            .onSubmit { submitText(vm: vm) }

                        Button { submitText(vm: vm) } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(
                                    textInput.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.gray.opacity(0.4)
                                    : Color(hex: "#a78bfa")
                                )
                        }
                        .disabled(textInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // ── Bottom dock ──
                bottomDock(vm: vm)
            }
        }
        .overlay(alignment: .top) {
            if let err = vm.error {
                errorToast(err.message, vm: vm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Local camera PIP
        .overlay(alignment: .topTrailing) {
            if vm.isVideoEnabled, let localTrack = vm.localVideoTrack {
                ZStack(alignment: .topTrailing) {
                    RTCVideoUIView(
                        track: localTrack,
                        mirror: vm.cameraPosition == .front
                    )
                    .frame(width: 120, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )

                    Button {
                        vm.switchCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(4)
                }
                .padding(.top, 100)
                .padding(.trailing, 16)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .participants:  participantsSheet(vm: vm)
            case .transcription: transcriptionSheet(vm: vm)
            case .aiTools:       aiToolsSheet(vm: vm)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.error != nil)
        .animation(.easeInOut(duration: 0.25), value: vm.isListenMode)
        .animation(.easeInOut(duration: 0.25), value: vm.isConversationActive)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Top Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func topBar(vm: RocsViewModel) -> some View {
        let cfg = statusCfgFor(vm.conversationStatus, speaking: vm.speakingStatus)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Connection dot
                Circle()
                    .fill(Color(hex: "#10b981"))
                    .frame(width: 8, height: 8)
                    .shadow(color: Color(hex: "#10b981").opacity(0.8), radius: 3)

                Text(vm.isConnecting ? "Connecting…" : "Live")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                // Status pill
                HStack(spacing: 5) {
                    if cfg.shouldPulse {
                        PulsingDot(color: cfg.color)
                    }
                    Text(cfg.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(cfg.color)
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(cfg.color, lineWidth: 1))

                // Participants badge
                if !vm.roomParticipants.isEmpty {
                    HStack(spacing: 2) {
                        Text("👤")
                            .font(.system(size: 12))
                        Text("\(vm.roomParticipants.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
                }

                Spacer()

                // Feature buttons (compact)
                if vm.isConnected {
                    HStack(spacing: 12) {
                        Button { activeSheet = .participants } label: {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Button { activeSheet = .transcription } label: {
                            Image(systemName: "text.quote")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Button { activeSheet = .aiTools } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }

            // Volume bars
            HStack(spacing: 4) {
                Text("🎤").font(.system(size: 14))
                VolumeBarView(value: vm.audioLevel, color: Color(hex: "#3b82f6"))
                Text("·").foregroundStyle(.white.opacity(0.3))
                Text("🤖").font(.system(size: 14))
                VolumeBarView(value: vm.aiAudioLevel, color: Color(hex: "#10b981"))
            }

            // Error strip
            if let err = vm.error {
                Text("⚠️ \(err.message)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.black.opacity(0.3))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Tool Calls / Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func toolCallsView(vm: RocsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "#94a3b8"))
                .tracking(0.5)

            // ── justin_action JSON ──
            VStack(alignment: .leading, spacing: 4) {
                Text("justin_action payload:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "#f59e0b"))
                ScrollView {
                    Text(toolCallsToJson(vm.toolCalls, messageId: vm.toolCallsMessageId))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(hex: "#10b981"))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            ForEach(vm.toolCalls) { tool in
                Button {
                    let argsStr = (try? JSONSerialization.data(withJSONObject: tool.function.arguments, options: []))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    let payload: [String: Any] = [
                        "message": tool.function.arguments,
                        "event": "justin_action_output",
                        "action_id": tool.id
                    ]
                    lastSelectActionsJson = selectActionToJson(payload)
                    vm.selectAction(message: "User has more than one contact matching Fahad Rehman: fahad - +971505191240, Fahad iPhone 15 Pro - +3197058049312, Fahad iPhone 15 pro max - +3197058049317.\n\nAsk user: You have multiple contacts named \"Fahad Rehman\". Which one would you like to call?", actionId: tool.id)
                } label: {
                    HStack(spacing: 8) {
                        Text("⚡")
                            .font(.system(size: 16))
                        Text(tool.function.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#64748b"))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(hex: "#1e293b"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "#334155"), lineWidth: 1)
                    )
                }
            }

            // ── Last select-actions payload ──
            if !lastSelectActionsJson.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("select-actions payload:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "#f59e0b"))
                    ScrollView {
                        Text(lastSelectActionsJson)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(hex: "#3b82f6"))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func toolCallsToJson(_ tools: [ToolCall], messageId: String) -> String {
        guard let tool = tools.first else { return "{}" }
        let parsedArgs: Any = tool.function.arguments
        let payload: [String: Any] = [
            "type": "justin_action",
            "content": [
                "action_id": tool.id,
                "name": tool.function.name,
                "arguments": parsedArgs
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func selectActionToJson(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Main Content (Messages + Orb)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func mainContentArea(vm: RocsViewModel) -> some View {
        VStack(spacing: 0) {
            // ── Compact AI header ──
            let oColor = orbColor(vm: vm)
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(oColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: orbIcon(vm: vm))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(oColor)
                }
                .overlay(Circle().stroke(oColor.opacity(0.4), lineWidth: 1))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Rocs")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(orbStatusText(vm: vm))
                        .font(.system(size: 11))
                        .foregroundStyle(oColor.opacity(0.9))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.25))

            Divider()
                .background(Color.white.opacity(0.07))

            // ── Chat list ──
            let chatMsgs = vm.conversationMessages.filter { !$0.content.isEmpty }
            if chatMsgs.isEmpty && !vm.isConversationActive {
                VStack {
                    Spacer()
                    emptyState(vm: vm)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(chatMsgs) { msg in
                                chatBubble(msg)
                            }
                            Color.clear.frame(height: 1).id("chat-bottom")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: chatMsgs.count) { _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                }
            }

            // ── Ask AI response ──
            if !vm.askAiTextResponse.isEmpty {
                askAiResponseCard(vm: vm)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Chat Bubble
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @ViewBuilder
    private func chatBubble(_ msg: ConversationMessage) -> some View {
        let isUser = msg.role == .user
        HStack(alignment: .bottom, spacing: 6) {
            if isUser { Spacer(minLength: 56) }
            if !isUser {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#1e293b"))
                        .frame(width: 26, height: 26)
                    Text("🤖")
                        .font(.system(size: 12))
                }
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                Text(isUser ? "You" : "Rocs")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isUser ? Color(hex: "#34d399") : Color(hex: "#a78bfa"))
                    .padding(.horizontal, 4)
                Text(msg.content)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isUser ? Color(hex: "#134e4a") : Color(hex: "#1e293b"))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isUser ? Color(hex: "#10b981").opacity(0.3) : Color(hex: "#334155"),
                                lineWidth: 1
                            )
                    )
            }
            if isUser {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#134e4a"))
                        .frame(width: 26, height: 26)
                    Text("👤")
                        .font(.system(size: 12))
                }
            }
            if !isUser { Spacer(minLength: 56) }
        }
        .id(msg.id)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Audio Orb
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func orbSection(vm: RocsViewModel) -> some View {
        let oColor = orbColor(vm: vm)
        let pulseScale = orbPulseScale(vm: vm)

        return VStack(spacing: 10) {
            ZStack {
                // Outer glow rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(oColor.opacity(0.08 - Double(i) * 0.02), lineWidth: 1)
                        .frame(width: 96 + CGFloat(i) * 28, height: 96 + CGFloat(i) * 28)
                        .scaleEffect(pulseScale + CGFloat(i) * 0.05)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: vm.speakingStatus
                        )
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [oColor.opacity(0.5), oColor.opacity(0.1)],
                            center: .center, startRadius: 5, endRadius: 48
                        )
                    )
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulseScale)
                    .animation(.easeInOut(duration: 0.15), value: vm.audioLevel)
                    .animation(.easeInOut(duration: 0.15), value: vm.aiAudioLevel)

                Image(systemName: orbIcon(vm: vm))
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(oColor)
            }
            .frame(height: 130)

            Text(orbStatusText(vm: vm))
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(oColor.opacity(0.9))
                .animation(.easeInOut(duration: 0.3), value: vm.speakingStatus)

            if !vm.roomParticipants.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill").font(.caption2)
                    Text("\(vm.roomParticipants.count) participant\(vm.roomParticipants.count == 1 ? "" : "s")")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 12)
    }

    private func orbColor(vm: RocsViewModel) -> Color {
        if vm.isAISpeaking      { return Color(hex: "#a78bfa") }
        if vm.isUserSpeaking    { return Color(hex: "#34d399") }
        if vm.isConversationActive { return Color(hex: "#60a5fa") }
        if vm.isConnected       { return Color(hex: "#6366f1") }
        return Color(hex: "#4b5563")
    }

    private func orbPulseScale(vm: RocsViewModel) -> CGFloat {
        let level = vm.isAISpeaking ? vm.aiAudioLevel : vm.audioLevel
        let base: CGFloat = vm.isConversationActive ? 1.0 : 0.85
        return base + CGFloat(min(level, 1.0)) * 0.25
    }

    private func orbIcon(vm: RocsViewModel) -> String {
        switch vm.speakingStatus {
        case .ai:        return "waveform"
        case .user:      return "mic.fill"
        case .searching: return "magnifyingglass"
        case .none:      return vm.isConversationActive ? "waveform.badge.mic" :
                                (vm.isConnected ? "checkmark.circle.fill" :
                                (vm.isConnecting ? "circle.dotted" : "circle"))
        }
    }

    private func orbStatusText(vm: RocsViewModel) -> String {
        if vm.isAISpeaking   { return "Rocs is speaking…" }
        if vm.isUserSpeaking { return "Listening to you…" }
        switch vm.connectionStatus {
        case .idle:         return "Ready to connect"
        case .connecting:   return "Connecting…"
        case .connected:    return vm.isConversationActive ? "Conversation active" : "Connected"
        case .disconnected: return "Disconnected"
        case .reconnecting: return "Reconnecting…"
        case .error:        return "Connection error"
        @unknown default:   return ""
        }
    }

    private func emptyState(vm: RocsViewModel) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 56))
                .foregroundStyle(Color(hex: "#a78bfa").opacity(0.5))
            Text(vm.isConnected ? "Starting conversation…" : "Connect to begin")
                .font(.title3).fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.6))
            if !vm.isConnected {
                Text("Tap Connect to establish a connection to the server.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Bottom Dock
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func bottomDock(vm: RocsViewModel) -> some View {
        VStack(spacing: 0) {
            // Primary control buttons
            HStack(spacing: 0) {
                dockButton(
                    icon: vm.isMuted ? "🔇" : "🎤",
                    label: vm.isMuted ? "Unmute" : "Mute",
                    active: vm.isMuted,
                    bg: vm.isMuted ? Color(hex: "#3b82f6") : Color.white.opacity(0.12)
                ) { vm.toggleMute() }

                dockButton(
                    icon: vm.isVideoEnabled ? "📹" : "📷",
                    label: vm.isVideoEnabled ? "Cam On" : "Cam Off",
                    active: vm.isVideoEnabled,
                    bg: vm.isVideoEnabled ? Color(hex: "#10b981") : Color.white.opacity(0.12)
                ) { vm.toggleCamera() }

                dockButton(
                    icon: vm.isListenMode ? "👂" : "🎧",
                    label: vm.isListenMode ? "Listening" : "Listen",
                    active: vm.isListenMode,
                    bg: vm.isListenMode ? Color(hex: "#8b5cf6") : Color.white.opacity(0.12)
                ) { _ = vm.toggleListenMode() }

                dockButton(
                    icon: vm.isSpeakerOn ? "🔊" : "🔈",
                    label: vm.isSpeakerOn ? "Speaker" : "Earpiece",
                    active: vm.isSpeakerOn,
                    bg: vm.isSpeakerOn ? Color(hex: "#f59e0b") : Color.white.opacity(0.12)
                ) { vm.toggleAudioOutput() }

                dockButton(
                    icon: "📞",
                    label: "End",
                    active: false,
                    bg: Color(hex: "#ef4444")
                ) { handleStop(vm: vm) }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Color.black.opacity(0.7))
        }
    }

    @ViewBuilder
    private func dockButton(
        icon: String,
        label: String,
        active: Bool,
        bg: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(icon)
                    .font(.system(size: 24))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .background(bg)
            .clipShape(Circle())
        }
        .frame(maxWidth: .infinity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Ask AI Response
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func askAiResponseCard(vm: RocsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color(hex: "#a78bfa"))
                Text("AI Response")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if vm.isAskAiTextProcessing {
                    ProgressView().tint(Color(hex: "#a78bfa")).scaleEffect(0.7)
                }
            }
            Text(vm.askAiTextResponse)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(12)
        .background(Color(hex: "#1e1e3a"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Waiting Room Host Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func waitingRoomHostBar(vm: RocsViewModel) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "person.badge.clock")
                    .foregroundStyle(Color(hex: "#f59e0b"))
                Text("\(vm.waitingRoom.count) waiting")
                    .font(.callout).fontWeight(.medium).foregroundStyle(.white)
                Spacer()
                Button("Admit All") { vm.admitAll() }
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(hex: "#22c55e"))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            ForEach(vm.waitingRoom, id: \.clientId) { entry in
                HStack {
                    Text(entry.displayName)
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Button { vm.admitParticipant(targetClientId: entry.clientId) } label: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: "#22c55e"))
                    }
                    Button { vm.denyParticipant(targetClientId: entry.clientId) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(hex: "#1e1e3a"))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Error Toast
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func errorToast(_ msg: String, vm: RocsViewModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(msg)
                .font(.callout).foregroundStyle(.white).lineLimit(2)
            Spacer()
            Button { vm.clearError() } label: {
                Image(systemName: "xmark").foregroundStyle(.white.opacity(0.6)).font(.caption)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(hex: "#1e1e3a").shadow(.drop(color: .black.opacity(0.4), radius: 8, y: 4)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14)
        .padding(.top, 50)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Participants Sheet
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func participantsSheet(vm: RocsViewModel) -> some View {
        NavigationView {
            List {
                if vm.roomParticipants.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.slash")
                                .font(.largeTitle).foregroundStyle(.secondary)
                            Text("No Participants").font(.headline).foregroundStyle(.secondary)
                            Text("Participants will appear here when they join.")
                                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                } else {
                    Section("In Room") {
                        ForEach(vm.roomParticipants, id: \.id) { p in
                            participantRow(p, vm: vm)
                        }
                    }
                }

                if vm.isHost {
                    Section("Host Controls") {
                        Button { vm.muteAll() } label: { Label("Mute All", systemImage: "speaker.slash.fill") }
                        Button { vm.unmuteAll() } label: { Label("Unmute All", systemImage: "speaker.wave.2.fill") }
                        Toggle("Lock Room", isOn: Binding(get: { vm.isRoomLocked }, set: { vm.lockRoom($0) }))
                        Toggle("Waiting Room", isOn: Binding(get: { vm.isWaitingRoomEnabled }, set: { vm.enableWaitingRoom($0) }))
                        Button(role: .destructive) { vm.endMeeting() } label: {
                            Label("End Meeting for All", systemImage: "xmark.circle.fill")
                        }
                    }
                }
            }
            .navigationTitle("Participants (\(vm.roomParticipants.count))")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func participantRow(_ p: RoomParticipant, vm: RocsViewModel) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(p.isSpeaking ? Color(hex: "#22c55e") : Color(hex: "#6366f1").opacity(0.4))
                .frame(width: 32, height: 32)
                .overlay {
                    Text(String(p.name.prefix(1)).uppercased())
                        .font(.caption).fontWeight(.bold).foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.body)
                if p.isSpeaking {
                    Text("Speaking…").font(.caption2).foregroundStyle(.green)
                }
            }
            Spacer()
            if p.isMuted {
                Image(systemName: "mic.slash.fill").font(.caption).foregroundStyle(.red.opacity(0.7))
            }
            if vm.isHost {
                Menu {
                    Button { vm.muteParticipant(targetClientId: p.id) } label: {
                        Label(p.isMuted ? "Unmute" : "Mute", systemImage: p.isMuted ? "mic.fill" : "mic.slash")
                    }
                    Button { vm.transferHost(targetClientId: p.id) } label: {
                        Label("Make Host", systemImage: "crown")
                    }
                    Divider()
                    Button(role: .destructive) { vm.removeParticipant(targetClientId: p.id) } label: {
                        Label("Remove", systemImage: "person.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Color(hex: "#a78bfa"))
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Transcription Sheet
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func transcriptionSheet(vm: RocsViewModel) -> some View {
        NavigationView {
            VStack(spacing: 0) {
                if vm.isHost {
                    Toggle("Live Transcription", isOn: Binding(
                        get: { vm.isTranscriptionEnabled },
                        set: { vm.toggleTranscription($0) }
                    ))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color(.systemGroupedBackground))
                }
                List {
                    if vm.transcriptions.isEmpty {
                        Section {
                            VStack(spacing: 12) {
                                Image(systemName: "text.quote").font(.largeTitle).foregroundStyle(.secondary)
                                Text("No Transcriptions").font(.headline).foregroundStyle(.secondary)
                                Text(vm.isTranscriptionEnabled
                                     ? "Transcriptions will appear as participants speak."
                                     : "Enable transcription to start capturing.")
                                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                        }
                    } else {
                        ForEach(Array(vm.transcriptions.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.displayName)
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(Color(hex: "#a78bfa"))
                                    Spacer()
                                    Text(formatTimestamp(entry.timestamp))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(entry.text).font(.body)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Transcription").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - AI Tools Sheet
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func aiToolsSheet(vm: RocsViewModel) -> some View {
        NavigationView {
            List {
                Section("Ask AI") {
                    HStack {
                        TextField("Ask anything…", text: $askAiPrompt)
                        Button {
                            vm.askAiText(prompt: askAiPrompt.isEmpty ? nil : askAiPrompt)
                            askAiPrompt = ""
                        } label: {
                            Image(systemName: "paperplane.fill").foregroundStyle(Color(hex: "#a78bfa"))
                        }
                    }

                    if !vm.askAiTextResponse.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "sparkles").foregroundStyle(Color(hex: "#a78bfa"))
                                Text("Response").font(.caption).fontWeight(.semibold)
                                if vm.isAskAiTextProcessing { ProgressView().scaleEffect(0.7) }
                            }
                            Text(vm.askAiTextResponse).font(.body)
                        }
                    }

                    Button { vm.askAi() } label: {
                        Label("Ask AI (Voice)", systemImage: "mic.badge.plus")
                    }
                    .disabled(!vm.isConversationActive)
                }

                Section("Bookmarks (\(vm.bookmarks.count))") {
                    HStack {
                        TextField("Bookmark label…", text: $bookmarkLabel)
                        Button {
                            guard !bookmarkLabel.isEmpty else { return }
                            vm.addBookmark(label: bookmarkLabel)
                            bookmarkLabel = ""
                        } label: {
                            Image(systemName: "bookmark.fill").foregroundStyle(Color(hex: "#f59e0b"))
                        }
                    }

                    ForEach(vm.bookmarks, id: \.id) { bm in
                        HStack {
                            Image(systemName: bm.isActionItem ? "exclamationmark.circle.fill" : "bookmark.fill")
                                .foregroundStyle(bm.isActionItem ? .orange : Color(hex: "#a78bfa")).font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bm.label).font(.body)
                                Text(bm.displayName).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { vm.removeBookmark(bookmarkId: bm.id) } label: {
                                Image(systemName: "trash").font(.caption).foregroundStyle(.red.opacity(0.6))
                            }
                        }
                    }
                }

                Section("Meeting Intelligence") {
                    Button { vm.generateSummary() } label: {
                        Label("Generate Summary", systemImage: "doc.text.magnifyingglass")
                    }
                    Button { vm.generateMinutes() } label: {
                        Label("Generate Minutes", systemImage: "list.clipboard")
                    }

                    ForEach(vm.summaries, id: \.id) { s in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Summary").font(.caption).fontWeight(.bold).foregroundStyle(Color(hex: "#a78bfa"))
                            Text(s.summary).font(.body)
                            if !s.actionItems.isEmpty {
                                Text("Action Items:").font(.caption).fontWeight(.semibold).padding(.top, 2)
                                ForEach(s.actionItems, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 4) {
                                        Text("•").foregroundStyle(Color(hex: "#a78bfa"))
                                        Text(item).font(.caption)
                                    }
                                }
                            }
                            if !s.keyTopics.isEmpty {
                                Text("Key Topics: \(s.keyTopics.joined(separator: ", "))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if let minutes = vm.currentMinutes {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Minutes: \(minutes.title)")
                                .font(.caption).fontWeight(.bold).foregroundStyle(Color(hex: "#a78bfa"))
                            if !minutes.attendees.isEmpty {
                                Text("Attendees: \(minutes.attendees.joined(separator: ", "))").font(.caption)
                            }
                            ForEach(minutes.sections, id: \.heading) { section in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(section.heading).font(.caption).fontWeight(.semibold)
                                    Text(section.content).font(.caption)
                                }
                            }
                            if !minutes.actionItems.isEmpty {
                                Text("Action Items:").font(.caption).fontWeight(.semibold).padding(.top, 2)
                                ForEach(minutes.actionItems, id: \.task) { item in
                                    HStack(alignment: .top, spacing: 4) {
                                        Text("•").foregroundStyle(Color(hex: "#a78bfa"))
                                        VStack(alignment: .leading) {
                                            Text(item.task).font(.caption)
                                            if let assignee = item.assignee {
                                                Text("→ \(assignee)").font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("AI Tools").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func handleStart() {
        let config = RocsConfig(
            appKey: appKeyInput.trimmingCharacters(in: .whitespaces),
            serverUrl: actualServerUrl,
            userId: userIdInput.trimmingCharacters(in: .whitespaces),
            threadId:threadIdInput.trimmingCharacters(in: .whitespaces).isEmpty ? nil : threadIdInput.trimmingCharacters(in: .whitespaces),
           
            selectedVoice: selectedVoiceId.isEmpty ? nil : selectedVoiceId,
            username:"Mohammad Naim Almani"
        )
        let newVm = RocsViewModel(config: config)
        vm = newVm
        newVm.connect()
    }

    private func handleStop(vm: RocsViewModel) {
        vm.disconnect()
        self.vm = nil
    }

    private func submitText(vm: RocsViewModel) {
        let trimmed = textInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        vm.sendMessage(trimmed)
        textInput = ""
        inputFocused = false
    }



    private func formatTimestamp(_ ts: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: ts / 1000)
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Pulsing Dot
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct PulsingDot: View {
    let color: Color
    @State private var scale: CGFloat = 1

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    scale = 1.6
                }
            }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Volume Bar
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct VolumeBarView: View {
    let value: Double
    let color: Color

    private var percentage: CGFloat {
        CGFloat(max(0, min(1, value)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * percentage)
                    .animation(.easeInOut(duration: 0.1), value: value)
            }
        }
        .frame(height: 4)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - WebRTC Video View (UIViewRepresentable)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#if canImport(WebRTC)
import WebRTC

struct RTCVideoUIView: UIViewRepresentable {
    let track: RTCVideoTrack?
    var mirror: Bool = false
    var contentMode: UIView.ContentMode = .scaleAspectFill

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        let renderer = RTCMTLVideoView()
        renderer.videoContentMode = contentMode
        renderer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(renderer)
        NSLayoutConstraint.activate([
            renderer.topAnchor.constraint(equalTo: container.topAnchor),
            renderer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            renderer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            renderer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        if mirror {
            renderer.transform = CGAffineTransform(scaleX: -1, y: 1)
        }
        context.coordinator.renderer = renderer
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let renderer = context.coordinator.renderer
        let oldTrack = context.coordinator.currentTrack

        if let old = oldTrack, old != track {
            old.remove(renderer!)
        }
        if let t = track, t != oldTrack {
            t.add(renderer!)
        }
        context.coordinator.currentTrack = track

        if mirror {
            renderer?.transform = CGAffineTransform(scaleX: -1, y: 1)
        } else {
            renderer?.transform = .identity
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let track = coordinator.currentTrack, let renderer = coordinator.renderer {
            track.remove(renderer)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var renderer: RTCMTLVideoView?
        var currentTrack: RTCVideoTrack?
    }
}
#endif

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Hex Color
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

extension Color {
    init(hex: String) {
        let hex  = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double((int >>  0) & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
