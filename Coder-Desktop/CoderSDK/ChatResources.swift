import Foundation

// Supporting resources for the Coder Agents Chats API: selectable models, MCP servers,
// and diff contents. Kept separate from Chats.swift (the client + core chat/message types).

public struct ChatModelConfig: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    /// Dropped from the server in coder/coder #26877 — optional so decoding doesn't fail against
    /// current deployments, and still populated by older ones.
    public let provider: String?
    /// Replaced `provider`; identifies the model's AI provider.
    public let ai_provider_id: UUID?
    public let model: String
    public let display_name: String
    public let is_default: Bool?
    /// The model's compaction threshold percent — the server's default when the user has no
    /// per-model override (chatd: `effectiveThreshold = modelConfig.CompressionThreshold`).
    public let compression_threshold: Int?
    /// Selectable reasoning efforts, ordered low to high through the model's configured
    /// maximum. Empty/nil for models that don't expose reasoning effort.
    public let reasoning_efforts: [String]?
    /// Per-call defaults, including the default reasoning effort.
    public let model_config: ChatModelCallConfig?

    public init(
        id: UUID, provider: String? = nil, ai_provider_id: UUID? = nil,
        model: String, display_name: String,
        is_default: Bool? = nil, compression_threshold: Int? = nil,
        reasoning_efforts: [String]? = nil, model_config: ChatModelCallConfig? = nil
    ) {
        self.id = id
        self.provider = provider
        self.ai_provider_id = ai_provider_id
        self.model = model
        self.display_name = display_name
        self.is_default = is_default
        self.compression_threshold = compression_threshold
        self.reasoning_efforts = reasoning_efforts
        self.model_config = model_config
    }

    /// The efforts the picker can offer, empty when the model has no reasoning control.
    public var selectableEfforts: [String] {
        reasoning_efforts ?? []
    }

    /// Picks an effort: the requested one, else the model's default, else the highest offered.
    /// Mirrors the web's `pickReasoningEffort`.
    public func pickEffort(_ requested: String?) -> String? {
        let efforts = selectableEfforts
        guard !efforts.isEmpty else { return nil }
        if let requested, efforts.contains(requested) { return requested }
        if let fallback = model_config?.reasoning_effort?.default, efforts.contains(fallback) {
            return fallback
        }
        return efforts.last
    }

    /// Display label, falling back to the model id when the server gives no display name.
    public var label: String {
        display_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model : display_name
    }
}

/// Per-call model behaviour defaults. Only the fields the client reads are modelled.
public struct ChatModelCallConfig: Codable, Sendable, Equatable {
    public let reasoning_effort: ChatModelReasoningEffortConfig?

    public init(reasoning_effort: ChatModelReasoningEffortConfig? = nil) {
        self.reasoning_effort = reasoning_effort
    }
}

public struct ChatModelReasoningEffortConfig: Codable, Sendable, Equatable {
    public let `default`: String?
    public let max: String?

    public init(default defaultValue: String? = nil, max: String? = nil) {
        self.default = defaultValue
        self.max = max
    }
}

public struct ChatDiffContents: Codable, Sendable, Equatable {
    public let chat_id: UUID?
    public let provider: String?
    public let remote_origin: String?
    public let branch: String?
    public let pull_request_url: String?
    public let diff: String?

    public init(
        chat_id: UUID? = nil, provider: String? = nil, remote_origin: String? = nil,
        branch: String? = nil, pull_request_url: String? = nil, diff: String? = nil
    ) {
        self.chat_id = chat_id
        self.provider = provider
        self.remote_origin = remote_origin
        self.branch = branch
        self.pull_request_url = pull_request_url
        self.diff = diff
    }
}

/// Cached branch/PR summary for a chat — counts and a link, available even when the full
/// diff text can't be fetched. All fields optional for forward-compatible decoding.
public struct ChatDiffStatus: Codable, Sendable, Equatable {
    public let chat_id: UUID?
    public let url: String?
    public let pull_request_state: String?
    public let pull_request_title: String?
    public let pull_request_draft: Bool?
    public let additions: Int?
    public let deletions: Int?
    public let changed_files: Int?
    public let head_branch: String?
    public let base_branch: String?
    public let pr_number: Int?

    public init(
        chat_id: UUID? = nil, url: String? = nil, pull_request_state: String? = nil,
        pull_request_title: String? = nil, pull_request_draft: Bool? = nil,
        additions: Int? = nil, deletions: Int? = nil, changed_files: Int? = nil,
        head_branch: String? = nil, base_branch: String? = nil, pr_number: Int? = nil
    ) {
        self.chat_id = chat_id
        self.url = url
        self.pull_request_state = pull_request_state
        self.pull_request_title = pull_request_title
        self.pull_request_draft = pull_request_draft
        self.additions = additions
        self.deletions = deletions
        self.changed_files = changed_files
        self.head_branch = head_branch
        self.base_branch = base_branch
        self.pr_number = pr_number
    }

    public var changeCount: Int {
        (additions ?? 0) + (deletions ?? 0) + (changed_files ?? 0)
    }

    /// Whether this refers to a real pull request (vs. a bare branch). Mirrors the web,
    /// which only links to PRs (`/pull/N`), never to `/tree/<branch>` pages (those 404
    /// once the ephemeral branch is gone).
    public var isPullRequest: Bool {
        pr_number != nil || (url?.contains("/pull/") ?? false)
    }

    /// A clickable PR URL, only when it actually points to a pull request.
    public var pullRequestURL: URL? {
        guard let url, url.contains("/pull/") else { return nil }
        return URL(string: url)
    }

    /// True when there's a PR or actual change counts worth showing.
    public var hasContent: Bool {
        changeCount > 0 || isPullRequest
    }

    /// A short label like "PR #123" or the head branch name.
    public var label: String? {
        if let number = pr_number { return "PR #\(number)" }
        if let branch = head_branch, !branch.isEmpty { return branch }
        return nil
    }
}

/// Result of disconnecting a connector's OAuth2 credentials. The grant is always dropped
/// locally; `token_revocation_error` reports that the provider's revocation call failed.
public struct MCPOAuthDisconnect: Codable, Sendable, Equatable {
    public let token_revoked: Bool?
    public let token_revocation_error: String?

    public init(token_revoked: Bool? = nil, token_revocation_error: String? = nil) {
        self.token_revoked = token_revoked
        self.token_revocation_error = token_revocation_error
    }
}

public struct MCPServer: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let display_name: String
    public let enabled: Bool
    public let availability: MCPAvailability?
    public let icon_url: String? // relative (e.g. /icon/github.svg) or absolute
    public let description: String?
    public let auth_type: String? // none | oauth2 | api_key | custom_headers | user_oidc
    public let auth_connected: Bool? // whether the user has connected (OAuth2)

    public init(
        id: UUID, display_name: String, enabled: Bool,
        availability: MCPAvailability? = nil, icon_url: String? = nil,
        description: String? = nil, auth_type: String? = nil, auth_connected: Bool? = nil
    ) {
        self.id = id
        self.display_name = display_name
        self.enabled = enabled
        self.availability = availability
        self.icon_url = icon_url
        self.description = description
        self.auth_type = auth_type
        self.auth_connected = auth_connected
    }

    /// Whether this server is selected by default in a new chat.
    public var defaultsOn: Bool {
        availability == .defaultOn || availability == .forceOn
    }

    /// Whether the user can toggle it (force_on servers are always on).
    public var locked: Bool {
        availability == .forceOn
    }

    /// An OAuth2 server the user hasn't connected yet — needs an Authenticate step before
    /// it can be turned on (mirrors the web picker).
    public var needsAuth: Bool {
        auth_type == "oauth2" && auth_connected != true
    }

    /// Whether this server exposes any auth at all (for the status label).
    public var hasAuth: Bool {
        let type = auth_type ?? "none"
        return type != "none" && !type.isEmpty
    }

    /// A connected OAuth2 server, whose credentials can be disconnected (and revoked upstream).
    public var canDisconnectAuth: Bool {
        auth_type == "oauth2" && auth_connected == true
    }
}

public enum MCPAvailability: String, Codable, Sendable, Equatable {
    case defaultOn = "default_on"
    case defaultOff = "default_off"
    case forceOn = "force_on"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MCPAvailability(rawValue: raw) ?? .unknown
    }
}
