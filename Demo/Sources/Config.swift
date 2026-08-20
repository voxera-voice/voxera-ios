// Server configuration
// Edit these values before running the demo.

import Foundation

struct ServerOption: Identifiable {
    let id: String
    let label: String
    let url: String
}

enum Config {
    /// Preset server list (matches RN demo).
    static let servers: [ServerOption] = [
        ServerOption(id: "local", label: "Local (localhost:8004)", url: "http://localhost:8004"),
        ServerOption(id: "custom", label: "Custom server", url: ""),
    ]

    /// Default selected server ID.
    static let defaultServerId = "local"

    /// App key obtained from the Rocs dashboard.
    static let appKey = "replace-with-a-test-app-key"

    /// User identifier sent with init-session.
    static let userId = "cc207543-877b-45b2-809d-c04acdf6f9d3"

    /// Default AI system prompt shown in the settings.
    static let defaultSystemPrompt =
        "You are a helpful AI assistant. Keep responses concise and conversational."
}
