import SwiftUI
import RocsSDK
import WebRTC

// ──────────────────────────────────────────────
// MARK: - VoiceChatView
// ──────────────────────────────────────────────

struct VoiceChatView: View {

    // Change serverUrl / appKey to match your deployment.
    @StateObject private var vm = RocsViewModel(config: RocsConfig(
        appKey: "demo-app-key",
        serverUrl: "http://localhost:8004",
        chatConfig: ChatConfig(systemPrompt: "You are a helpful voice assistant."),
        voiceConfig: VoiceConfig(language: "en")
    ))

    @State private var inputText = ""
    @State private var showParticipants = false
    @State private var showTranscription = false
    @State private var showAITools = false
    @State private var bookmarkLabel = ""
    @State private var askAiPrompt = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar

                // Waiting room banner
                if vm.isInWaitingRoom {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Waiting for the host to admit you…")
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.15))
                }

                // Host: pending admissions
                if vm.isHost && !vm.waitingRoom.isEmpty {
                    waitingRoomBar
                }

                messagesArea

                // Ask AI response
                if !vm.askAiTextResponse.isEmpty {
                    askAiResponseBanner
                }

                inputBar
            }
            .navigationTitle("Rocs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        .alert("Error", isPresented: .constant(vm.error != nil), presenting: vm.error) { _ in
            Button("Dismiss") { vm.clearError() }
        } message: { err in
            Text(err.message)
        }
        .sheet(isPresented: $showParticipants) { participantsSheet }
        .sheet(isPresented: $showTranscription) { transcriptionSheet }
        .sheet(isPresented: $showAITools) { aiToolsSheet }
    }

    // ──────────────────────────────────────────────
    // MARK: - Toolbar
    // ──────────────────────────────────────────────

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if vm.isConnected {
                // Participants
                Button { showParticipants = true } label: {
                    Label("Participants", systemImage: "person.2")
                }

                // Transcription
                Button { showTranscription = true } label: {
                    Label("Transcription", systemImage: "text.quote")
                }

                // AI Tools
                Button { showAITools = true } label: {
                    Label("AI", systemImage: "sparkles")
                }
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 4) {
                if let mode = vm.roomMode {
                    Text(mode == .aiMeeting ? "AI" : "Room")
                        .font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(mode == .aiMeeting ? Color.purple.opacity(0.2) : Color.blue.opacity(0.2))
                        .foregroundStyle(mode == .aiMeeting ? .purple : .blue)
                        .clipShape(Capsule())
                }
                if vm.isHost {
                    Text("Host")
                        .font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                if vm.isRoomLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    // ──────────────────────────────────────────────
    // MARK: - Header
    // ──────────────────────────────────────────────

    private var headerBar: some View {
        VStack(spacing: 8) {
            // Audio orb
            ZStack {
                Circle()
                    .stroke(speakingColor.opacity(0.3), lineWidth: 12)
                    .frame(width: 80, height: 80)
                    .scaleEffect(vm.isSpeaking
                        ? 1 + CGFloat(max(vm.audioLevel, vm.aiAudioLevel)) * 0.4
                        : 1)
                    .animation(.easeInOut(duration: 0.15), value: vm.audioLevel)

                Image(systemName: connectionIcon)
                    .font(.system(size: 32))
                    .foregroundStyle(speakingColor)
            }
            .padding(.top, 12)

            Text(statusLabel)
                .font(.caption).foregroundStyle(.secondary)

            // Participant count
            if !vm.roomParticipants.isEmpty {
                Text("\(vm.roomParticipants.count) participant\(vm.roomParticipants.count == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            // Control row
            HStack(spacing: 16) {
                connectButton
                conversationButton
                muteButton
                listenModeButton
            }
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }

    // ──────────────────────────────────────────────
    // MARK: - Waiting Room Bar
    // ──────────────────────────────────────────────

    private var waitingRoomBar: some View {
        VStack(spacing: 6) {
            HStack {
                Label("\(vm.waitingRoom.count) waiting", systemImage: "person.badge.clock")
                    .font(.callout).fontWeight(.medium)
                Spacer()
                Button("Admit All") { vm.admitAll() }
                    .font(.caption).buttonStyle(.borderedProminent).tint(.green)
            }
            ForEach(vm.waitingRoom, id: \.clientId) { entry in
                HStack {
                    Text(entry.displayName).font(.caption)
                    Spacer()
                    Button { vm.admitParticipant(targetClientId: entry.clientId) } label: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Button { vm.denyParticipant(targetClientId: entry.clientId) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    // ──────────────────────────────────────────────
    // MARK: - Messages
    // ──────────────────────────────────────────────

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.conversationMessages) { msg in
                        MessageBubble(message: msg).id(msg.id)
                    }
                    if !vm.currentTranscript.isEmpty {
                        Text(vm.currentTranscript)
                            .italic().font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .id("transcript")
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: vm.conversationMessages.count) { _ in
                if let last = vm.conversationMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // ──────────────────────────────────────────────
    // MARK: - Ask AI Response Banner
    // ──────────────────────────────────────────────

    private var askAiResponseBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 4) {
                if vm.isAskAiTextProcessing {
                    ProgressView().scaleEffect(0.7)
                }
                Text(vm.askAiTextResponse).font(.callout)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // ──────────────────────────────────────────────
    // MARK: - Input Bar
    // ──────────────────────────────────────────────

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Type a message…", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .focused($textFieldFocused)
                .submitLabel(.send)
                .onSubmit(sendMessage)

            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || !vm.isConnected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // ──────────────────────────────────────────────
    // MARK: - Control Buttons
    // ──────────────────────────────────────────────

    private var connectButton: some View {
        Button {
            vm.isConnected || vm.isConnecting ? vm.disconnect() : vm.connect()
        } label: {
            Label(
                vm.isConnected ? "Disconnect" : (vm.isConnecting ? "Connecting…" : "Connect"),
                systemImage: vm.isConnected ? "phone.down.fill" : "phone.fill"
            ).font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(vm.isConnected ? .red : .green)
        .disabled(vm.isConnecting)
    }

    private var conversationButton: some View {
        Button {
            vm.isConversationActive ? vm.endConversation() : vm.startConversation()
        } label: {
            Label(
                vm.isConversationActive ? "End" : "Start",
                systemImage: vm.isConversationActive ? "stop.circle" : "play.circle"
            ).font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(vm.isConversationActive ? .orange : .blue)
        .disabled(!vm.isConnected)
    }

    private var muteButton: some View {
        Button { vm.toggleMute() } label: {
            Image(systemName: vm.isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.title3)
        }
        .buttonStyle(.bordered)
        .tint(vm.isMuted ? .red : .primary)
        .disabled(!vm.isConnected)
    }

    private var listenModeButton: some View {
        Button { _ = vm.toggleListenMode() } label: {
            Image(systemName: vm.isListenMode ? "ear.badge.checkmark" : "ear")
                .font(.title3)
        }
        .buttonStyle(.bordered)
        .tint(vm.isListenMode ? .purple : .primary)
        .disabled(!vm.isConnected)
    }

    // ──────────────────────────────────────────────
    // MARK: - Participants Sheet
    // ──────────────────────────────────────────────

    private var participantsSheet: some View {
        NavigationView {
            List {
                if vm.roomParticipants.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "person.2.slash")
                                .font(.largeTitle).foregroundStyle(.secondary)
                            Text("No participants yet")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                } else {
                    Section("In Room") {
                        ForEach(vm.roomParticipants, id: \.id) { p in
                            HStack {
                                Circle()
                                    .fill(p.isSpeaking ? .green : .blue.opacity(0.3))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Text(String(p.name.prefix(1)).uppercased())
                                            .font(.caption2).fontWeight(.bold)
                                            .foregroundStyle(.white)
                                    }
                                VStack(alignment: .leading) {
                                    Text(p.name)
                                    if p.isSpeaking {
                                        Text("Speaking…")
                                            .font(.caption2).foregroundStyle(.green)
                                    }
                                }
                                Spacer()
                                if p.isMuted {
                                    Image(systemName: "mic.slash.fill")
                                        .font(.caption).foregroundStyle(.red)
                                }
                                if vm.isHost {
                                    Menu {
                                        Button { vm.muteParticipant(targetClientId: p.id) } label: {
                                            Label(p.isMuted ? "Unmute" : "Mute",
                                                  systemImage: p.isMuted ? "mic.fill" : "mic.slash")
                                        }
                                        Button { vm.transferHost(targetClientId: p.id) } label: {
                                            Label("Make Host", systemImage: "crown")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            vm.removeParticipant(targetClientId: p.id)
                                        } label: {
                                            Label("Remove", systemImage: "person.badge.minus")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .foregroundStyle(.purple)
                                    }
                                }
                            }
                        }
                    }
                }

                if vm.isHost {
                    Section("Host Controls") {
                        Button { vm.muteAll() } label: {
                            Label("Mute All", systemImage: "speaker.slash.fill")
                        }
                        Button { vm.unmuteAll() } label: {
                            Label("Unmute All", systemImage: "speaker.wave.2.fill")
                        }
                        Toggle("Lock Room", isOn: Binding(
                            get: { vm.isRoomLocked },
                            set: { vm.lockRoom($0) }
                        ))
                        Toggle("Waiting Room", isOn: Binding(
                            get: { vm.isWaitingRoomEnabled },
                            set: { vm.enableWaitingRoom($0) }
                        ))
                        Button(role: .destructive) { vm.endMeeting() } label: {
                            Label("End Meeting", systemImage: "xmark.circle.fill")
                        }
                    }
                }
            }
            .navigationTitle("Participants (\(vm.roomParticipants.count))")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // ──────────────────────────────────────────────
    // MARK: - Transcription Sheet
    // ──────────────────────────────────────────────

    private var transcriptionSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                if vm.isHost {
                    Toggle("Transcription", isOn: Binding(
                        get: { vm.isTranscriptionEnabled },
                        set: { vm.toggleTranscription($0) }
                    ))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(.systemGroupedBackground))
                }

                List {
                    if vm.transcriptions.isEmpty {
                        Section {
                            Text(vm.isTranscriptionEnabled
                                 ? "Transcriptions will appear as participants speak."
                                 : "Enable transcription to start capturing.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                        }
                    } else {
                        ForEach(Array(vm.transcriptions.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.displayName)
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(.purple)
                                    Spacer()
                                    Text(formatTS(entry.timestamp))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(entry.text)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transcription")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // ──────────────────────────────────────────────
    // MARK: - AI Tools Sheet
    // ──────────────────────────────────────────────

    private var aiToolsSheet: some View {
        NavigationView {
            List {
                Section("Ask AI") {
                    HStack {
                        TextField("Ask anything…", text: $askAiPrompt)
                        Button {
                            vm.askAiText(prompt: askAiPrompt.isEmpty ? nil : askAiPrompt)
                            askAiPrompt = ""
                        } label: {
                            Image(systemName: "paperplane.fill").foregroundStyle(.purple)
                        }
                    }
                    if !vm.askAiTextResponse.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "sparkles").foregroundStyle(.purple)
                                Text("Response").font(.caption).fontWeight(.semibold)
                                if vm.isAskAiTextProcessing { ProgressView().scaleEffect(0.7) }
                            }
                            Text(vm.askAiTextResponse)
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
                            Image(systemName: "bookmark.fill").foregroundStyle(.orange)
                        }
                    }
                    ForEach(vm.bookmarks, id: \.id) { bm in
                        HStack {
                            Image(systemName: bm.isActionItem ? "exclamationmark.circle.fill" : "bookmark.fill")
                                .foregroundStyle(bm.isActionItem ? .orange : .purple)
                                .font(.caption)
                            VStack(alignment: .leading) {
                                Text(bm.label)
                                Text(bm.displayName).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { vm.removeBookmark(bookmarkId: bm.id) } label: {
                                Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("Intelligence") {
                    Button { vm.generateSummary() } label: {
                        Label("Generate Summary", systemImage: "doc.text.magnifyingglass")
                    }
                    Button { vm.generateMinutes() } label: {
                        Label("Generate Minutes", systemImage: "list.clipboard")
                    }

                    ForEach(vm.summaries, id: \.id) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Summary").font(.caption).fontWeight(.bold).foregroundStyle(.purple)
                            Text(s.summary)
                            if !s.actionItems.isEmpty {
                                ForEach(s.actionItems, id: \.self) { item in
                                    Label(item, systemImage: "checkmark.circle").font(.caption)
                                }
                            }
                        }
                    }

                    if let minutes = vm.currentMinutes {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Minutes: \(minutes.title)")
                                .font(.caption).fontWeight(.bold).foregroundStyle(.purple)
                            if !minutes.attendees.isEmpty {
                                Text("Attendees: \(minutes.attendees.joined(separator: ", "))")
                                    .font(.caption)
                            }
                            ForEach(minutes.sections, id: \.heading) { section in
                                Text(section.heading).font(.caption).fontWeight(.semibold)
                                Text(section.content).font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("AI Tools")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // ──────────────────────────────────────────────
    // MARK: - Helpers
    // ──────────────────────────────────────────────

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, vm.isConnected else { return }
        vm.sendMessage(text)
        inputText = ""
        textFieldFocused = false
    }

    private func formatTS(_ ts: TimeInterval) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: Date(timeIntervalSince1970: ts / 1000))
    }

    private var statusLabel: String {
        switch vm.connectionStatus {
        case .idle:         return "Tap Connect to begin"
        case .connecting:   return "Connecting…"
        case .connected:
            if vm.isAISpeaking  { return "AI is speaking…" }
            if vm.isUserSpeaking { return "Listening…" }
            if vm.isConversationActive { return "Conversation active" }
            return "Connected"
        case .disconnected: return "Disconnected"
        case .error:        return "Connection error"
        @unknown default:   return ""
        }
    }

    private var connectionIcon: String {
        switch vm.connectionStatus {
        case .connected:  return vm.isAISpeaking ? "waveform" : "checkmark.circle.fill"
        case .connecting: return "circle.dotted"
        case .error:      return "exclamationmark.circle"
        default:          return "circle"
        }
    }

    private var speakingColor: Color {
        if vm.isAISpeaking  { return .purple }
        if vm.isUserSpeaking { return .green }
        if vm.isConnected   { return .blue }
        return .gray
    }
}

// ──────────────────────────────────────────────
// MARK: - MessageBubble
// ──────────────────────────────────────────────

struct MessageBubble: View {
    let message: ConversationMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isUser ? Color.blue : Color(.secondarySystemBackground))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(timeString(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// ──────────────────────────────────────────────
// MARK: - Preview
// ──────────────────────────────────────────────

#Preview {
    VoiceChatView()
}
