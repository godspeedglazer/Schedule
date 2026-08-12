import AppKit
import Foundation
import Security

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case automatic
    case openAI
    case anthropic
    case gemini
    case openRouter
    case groq
    case mistral
    case xAI
    case deepSeek
    case together
    case perplexity
    case cohere
    case azureOpenAI
    case ollama
    case lmStudio
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Google Gemini"
        case .openRouter: "OpenRouter"
        case .groq: "Groq"
        case .mistral: "Mistral"
        case .xAI: "xAI"
        case .deepSeek: "DeepSeek"
        case .together: "Together AI"
        case .perplexity: "Perplexity"
        case .cohere: "Cohere"
        case .azureOpenAI: "Azure OpenAI"
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .custom: "OpenAI-compatible"
        }
    }

    var environmentKeys: [String] {
        switch self {
        case .automatic, .ollama, .custom: []
        case .openAI: ["OPENAI_API_KEY"]
        case .anthropic: ["ANTHROPIC_API_KEY"]
        case .gemini: ["GOOGLE_API_KEY", "GEMINI_API_KEY"]
        case .openRouter: ["OPENROUTER_API_KEY"]
        case .groq: ["GROQ_API_KEY"]
        case .mistral: ["MISTRAL_API_KEY"]
        case .xAI: ["XAI_API_KEY"]
        case .deepSeek: ["DEEPSEEK_API_KEY"]
        case .together: ["TOGETHER_API_KEY"]
        case .perplexity: ["PERPLEXITY_API_KEY"]
        case .cohere: ["COHERE_API_KEY"]
        case .azureOpenAI: ["AZURE_OPENAI_API_KEY"]
        case .lmStudio: ["LM_API_TOKEN"]
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .automatic: ""
        case .openAI: "https://api.openai.com"
        case .anthropic: "https://api.anthropic.com"
        case .gemini: "https://generativelanguage.googleapis.com"
        case .openRouter: "https://openrouter.ai/api"
        case .groq: "https://api.groq.com/openai"
        case .mistral: "https://api.mistral.ai"
        case .xAI: "https://api.x.ai"
        case .deepSeek: "https://api.deepseek.com"
        case .together: "https://api.together.xyz"
        case .perplexity: "https://api.perplexity.ai"
        case .cohere: "https://api.cohere.com"
        case .azureOpenAI: ""
        case .ollama: "http://127.0.0.1:11434"
        case .lmStudio: "http://127.0.0.1:1234"
        case .custom: ""
        }
    }

    var isLocal: Bool { self == .ollama || self == .lmStudio }
}

struct SchedAISettings: Codable, Equatable {
    var provider: AIProvider
    var endpoint: String
    var model: String
    var stopOwnedServerOnQuit: Bool

    static let `default` = SchedAISettings(
        provider: .automatic,
        endpoint: "",
        model: "",
        stopOwnedServerOnQuit: true
    )
}

/// A saved packet is deliberately just a reusable brief and context selection.
/// Keys stay in Keychain and files are chosen at send time, so a preset can be
/// useful without turning into a hidden copy of the user's workspace.
struct SchedAIPacketPreset: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var request: String
    var includeReminders: Bool
    var includeTimers: Bool
    var includeAppLimits: Bool
    var includeWorkspace: Bool

    init(
        id: UUID = UUID(),
        name: String,
        request: String,
        includeReminders: Bool = true,
        includeTimers: Bool = true,
        includeAppLimits: Bool = true,
        includeWorkspace: Bool = true
    ) {
        self.id = id
        self.name = name
        self.request = request
        self.includeReminders = includeReminders
        self.includeTimers = includeTimers
        self.includeAppLimits = includeAppLimits
        self.includeWorkspace = includeWorkspace
    }
}

struct AIDetection: Equatable {
    var provider: AIProvider
    var reason: String
}

enum AIProviderDetector {
    static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        endpoint: String = "",
        keyHint: String = ""
    ) -> AIDetection? {
        if let endpointProvider = provider(forEndpoint: endpoint) {
            return AIDetection(provider: endpointProvider, reason: "endpoint")
        }
        if let keyProvider = provider(forKeyPrefix: keyHint) {
            return AIDetection(provider: keyProvider, reason: "key format")
        }
        for provider in AIProvider.allCases where provider != .automatic {
            if let variable = provider.environmentKeys.first(where: { !(environment[$0] ?? "").isEmpty }) {
                return AIDetection(provider: provider, reason: variable)
            }
        }
        if !(environment["AZURE_OPENAI_ENDPOINT"] ?? "").isEmpty {
            return AIDetection(provider: .azureOpenAI, reason: "AZURE_OPENAI_ENDPOINT")
        }
        return nil
    }

    static func provider(forEndpoint endpoint: String) -> AIProvider? {
        let lower = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return nil }
        if lower.contains("11434") || lower.contains("/api/tags") || lower.contains("ollama") { return .ollama }
        if lower.contains("1234") || lower.contains("lmstudio") { return .lmStudio }
        if lower.contains("api.openai.com") { return .openAI }
        if lower.contains("anthropic.com") { return .anthropic }
        if lower.contains("generativelanguage.googleapis.com") { return .gemini }
        if lower.contains("openrouter.ai") { return .openRouter }
        if lower.contains("groq.com") { return .groq }
        if lower.contains("mistral.ai") { return .mistral }
        if lower.contains("api.x.ai") { return .xAI }
        if lower.contains("deepseek.com") { return .deepSeek }
        if lower.contains("together.xyz") { return .together }
        if lower.contains("perplexity.ai") { return .perplexity }
        if lower.contains("cohere.com") { return .cohere }
        if lower.contains("openai.azure.com") { return .azureOpenAI }
        if URL(string: lower) != nil { return .custom }
        return nil
    }

    static func provider(forKeyPrefix key: String) -> AIProvider? {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if clean.hasPrefix("sk-ant-") { return .anthropic }
        if clean.hasPrefix("gsk_") { return .groq }
        if clean.hasPrefix("sk-or-") { return .openRouter }
        if clean.hasPrefix("AIza") { return .gemini }
        if clean.hasPrefix("xai-") { return .xAI }
        if clean.hasPrefix("pplx-") { return .perplexity }
        if clean.hasPrefix("sk-") { return .openAI }
        return nil
    }
}

enum AIKeychainStore {
    private static let service = "com.erichspringer.sched.ai"

    static func key(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String, for provider: AIProvider) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            attributes.forEach { item[$0.key] = $0.value }
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func remove(for provider: AIProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AIConnectionTester {
    static func test(provider: AIProvider, endpoint: String, key: String?) async -> String {
        let base = normalized(endpoint.isEmpty ? provider.defaultEndpoint : endpoint)
        guard !base.isEmpty else { return "Enter an endpoint first." }

        let candidatePaths: [String]
        switch provider {
        case .ollama: candidatePaths = ["/api/tags"]
        case .lmStudio: candidatePaths = ["/api/v1/models", "/v1/models"]
        case .anthropic: candidatePaths = ["/v1/models"]
        case .gemini: candidatePaths = ["/v1beta/models"]
        default: candidatePaths = ["/v1/models", "/models"]
        }

        var lastStatus: Int?
        for path in candidatePaths {
            guard var components = URLComponents(string: base + path) else { continue }
            if provider == .gemini, let key, !key.isEmpty {
                components.queryItems = [URLQueryItem(name: "key", value: key)]
            }
            guard let url = components.url else { continue }
            var request = URLRequest(url: url, timeoutInterval: 2.5)
            request.httpMethod = "GET"
            if let key, !key.isEmpty {
                if provider == .anthropic {
                    request.setValue(key, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                } else if provider != .gemini {
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                }
            }
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                lastStatus = http.statusCode
                if 200..<300 ~= http.statusCode {
                    return "Connected to \(provider.label)."
                }
                if http.statusCode == 401 || http.statusCode == 403 {
                    return "Reached \(provider.label), but the key was rejected (\(http.statusCode))."
                }
            } catch {
                continue
            }
        }
        if let lastStatus { return "Reached the endpoint, but it returned HTTP \(lastStatus)." }
        return "No server answered at \(base)."
    }

    private static func normalized(_ endpoint: String) -> String {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
            of: #"/+$"#,
            with: "",
            options: .regularExpression
        )
    }
}

@MainActor
final class AILocalServerController {
    static let shared = AILocalServerController()
    private var ownedOllamaProcess: Process?

    private init() {}

    func start(_ provider: AIProvider) -> String {
        switch provider {
        case .ollama:
            guard ownedOllamaProcess?.isRunning != true else { return "Ollama was already started by Sched." }
            guard let executable = executable(named: "ollama") else { return "Ollama CLI was not found." }
            let process = Process()
            process.executableURL = executable
            process.arguments = ["serve"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                ownedOllamaProcess = process
                return "Started Ollama. Sched owns this process and can stop it."
            } catch {
                return "Ollama could not start: \(error.localizedDescription)"
            }
        case .lmStudio:
            return runLMS(arguments: ["server", "start"], success: "Asked LM Studio to start its server.")
        default:
            return "Server controls are only available for Ollama and LM Studio."
        }
    }

    func stop(_ provider: AIProvider) -> String {
        switch provider {
        case .ollama:
            guard let process = ownedOllamaProcess, process.isRunning else {
                return "Sched did not start this Ollama server, so it was left alone."
            }
            process.terminate()
            ownedOllamaProcess = nil
            return "Stopped the Ollama server started by Sched."
        case .lmStudio:
            return runLMS(arguments: ["server", "stop"], success: "Asked LM Studio to stop its server.")
        default:
            return "Server controls are only available for Ollama and LM Studio."
        }
    }

    func stopOwnedServerOnQuit() {
        guard ScheduleStore.shared.store.aiSettings.stopOwnedServerOnQuit else { return }
        if let process = ownedOllamaProcess, process.isRunning { process.terminate() }
        ownedOllamaProcess = nil
    }

    private func runLMS(arguments: [String], success: String) -> String {
        guard let executable = executable(named: "lms") else { return "LM Studio's lms CLI was not found." }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return success
        } catch {
            return "LM Studio command failed: \(error.localizedDescription)"
        }
    }

    private func executable(named name: String) -> URL? {
        let fm = FileManager.default
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let known = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] + pathEntries
        for directory in known {
            let path = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name).path
            if fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }
}

struct SchedAIPacketReminder: Codable, Equatable {
    var title: String
    var note: String
    var fireAt: Date
    var level: String
    var repeatsDaily: Bool
    var enabled: Bool
}

struct SchedAIPacketTimer: Codable, Equatable {
    var title: String
    var note: String
    var fireAt: Date
    var level: String
    var pausedRemainingSeconds: Int?
}

struct SchedAIPacketAppLimit: Codable, Equatable {
    var appName: String
    var maxMinutes: Int
    var level: String
    var enabled: Bool
}

struct SchedAIPacketAttachment: Codable, Equatable {
    var name: String
    var byteCount: Int
    var included: Bool
    var reason: String?
}

struct AIPacketOptions: Equatable {
    var includeReminders = true
    var includeTimers = true
    var includeAppLimits = true
    var includeWorkspace = true
}

struct SchedAIWorkspaceSnapshot: Codable, Equatable {
    var frontmostApplication: String?
    var runningApplications: [String]
}

struct SchedAIPacketContext: Codable, Equatable {
    var generatedAt: Date
    var provider: String
    var endpoint: String
    var model: String
    var reminders: [SchedAIPacketReminder]
    var timers: [SchedAIPacketTimer]
    var appLimits: [SchedAIPacketAppLimit]
    var workspace: SchedAIWorkspaceSnapshot?
    var attachments: [SchedAIPacketAttachment]
}

enum AIPacketBuilder {
    static let attachmentByteLimit = 256_000

    static func files(
        store: SchedStore,
        request: String,
        options: AIPacketOptions = .init(),
        attachments: [URL] = [],
        now: Date = .now
    ) throws -> [String: Data] {
        var attachmentFiles: [String: Data] = [:]
        var attachmentMetadata: [SchedAIPacketAttachment] = []
        var usedNames: Set<String> = []
        for url in attachments {
            let name = uniqueAttachmentName(url.lastPathComponent, usedNames: &usedNames)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if data.count > attachmentByteLimit {
                attachmentMetadata.append(.init(name: name, byteCount: data.count, included: false, reason: "Larger than \(attachmentByteLimit / 1_000) KB"))
            } else {
                attachmentFiles["attachments/\(name)"] = data
                attachmentMetadata.append(.init(name: name, byteCount: data.count, included: true, reason: nil))
            }
        }
        let context = SchedAIPacketContext(
            generatedAt: now,
            provider: store.aiSettings.provider.label,
            endpoint: store.aiSettings.endpoint,
            model: store.aiSettings.model,
            reminders: options.includeReminders ? store.alarms.filter { !$0.isTimer }.map {
                SchedAIPacketReminder(
                    title: $0.title,
                    note: $0.note,
                    fireAt: $0.fireAt,
                    level: $0.level.label,
                    repeatsDaily: $0.repeatDaily,
                    enabled: $0.enabled
                )
            } : [],
            timers: options.includeTimers ? store.alarms.filter(\.isTimer).map {
                SchedAIPacketTimer(
                    title: $0.title,
                    note: $0.note,
                    fireAt: $0.fireAt,
                    level: $0.level.label,
                    pausedRemainingSeconds: $0.pausedRemainingSeconds
                )
            } : [],
            appLimits: options.includeAppLimits ? store.appWatches.map {
                SchedAIPacketAppLimit(
                    appName: $0.appName,
                    maxMinutes: $0.maxMinutes,
                    level: $0.level.label,
                    enabled: $0.enabled
                )
            } : [],
            workspace: options.includeWorkspace ? workspaceSnapshot() : nil,
            attachments: attachmentMetadata
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let contextData = try encoder.encode(context)
        let readme = """
        # Sched AI packet

        This is a portable, provider-neutral snapshot created by Sched. It contains the context you selected; it never contains API keys or Keychain data.

        - `request.md` — what you want help with
        - `sched-context.json` — structured Sched context
        - `attachments/` — selected files under \(attachmentByteLimit / 1_000) KB

        The optional workspace section is a one-time snapshot of currently open apps. It does not read or change the Dock, Spaces, or any app window. Give this folder to the model or local backend you already use. Nothing in this packet runs automatically.
        """
        let cleanRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestText = cleanRequest.isEmpty ? "# Request\n\nHelp me review and organize this schedule." : "# Request\n\n\(cleanRequest)"
        var files: [String: Data] = [
            "README.md": Data(readme.utf8),
            "request.md": Data(requestText.utf8),
            "sched-context.json": contextData,
        ]
        attachmentFiles.forEach { files[$0.key] = $0.value }
        return files
    }

    static func prompt(
        store: SchedStore,
        request: String,
        options: AIPacketOptions = .init(),
        attachments: [URL] = []
    ) throws -> String {
        let files = try self.files(store: store, request: request, options: options, attachments: attachments)
        let requestText = String(data: files["request.md"] ?? Data(), encoding: .utf8) ?? ""
        let contextText = String(data: files["sched-context.json"] ?? Data(), encoding: .utf8) ?? "{}"
        var sections = [
            "You are helping someone use Sched, a personal macOS reminder, timer, calendar, and app-limit utility.",
            requestText,
            "# Selected Sched context\n\n```json\n\(contextText)\n```",
        ]
        for (name, data) in files.sorted(by: { $0.key < $1.key }) where name.hasPrefix("attachments/") {
            if let text = String(data: data, encoding: .utf8) {
                sections.append("# Attachment: \(name)\n\n\(text)")
            } else {
                sections.append("# Attachment: \(name)\n\nBinary file included in export; its contents were not sent as text.")
            }
        }
        sections.append("Give a practical, concise answer. Do not assume you can change the schedule unless asked.")
        return sections.joined(separator: "\n\n")
    }

    @MainActor
    static func export(
        store: SchedStore,
        request: String,
        options: AIPacketOptions = .init(),
        attachments: [URL] = [],
        parent: URL
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let folder = parent.appendingPathComponent("Sched-AI-Packet-\(formatter.string(from: .now))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        for (name, data) in try files(store: store, request: request, options: options, attachments: attachments) {
            let destination = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
        return folder
    }

    private static func uniqueAttachmentName(_ proposed: String, usedNames: inout Set<String>) -> String {
        let clean = proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "attachment" : proposed
        guard usedNames.contains(clean) else {
            usedNames.insert(clean)
            return clean
        }
        let stem = (clean as NSString).deletingPathExtension
        let ext = (clean as NSString).pathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            if !usedNames.contains(candidate) {
                usedNames.insert(candidate)
                return candidate
            }
            index += 1
        }
    }

    private static func workspaceSnapshot() -> SchedAIWorkspaceSnapshot {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
            .filter { !$0.isTerminated && !$0.isHidden && $0.activationPolicy != .prohibited }
            .compactMap { $0.localizedName }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return SchedAIWorkspaceSnapshot(
            frontmostApplication: workspace.frontmostApplication?.localizedName,
            runningApplications: apps
        )
    }
}

enum AIConversationClient {
    static func send(provider: AIProvider, endpoint: String, model: String, key: String?, prompt: String) async throws -> String {
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel: String
        switch provider {
        case .gemini: resolvedModel = selectedModel.isEmpty ? "gemini-2.0-flash" : selectedModel
        case .ollama: resolvedModel = selectedModel.isEmpty ? "llama3" : selectedModel
        case .lmStudio: resolvedModel = selectedModel.isEmpty ? "local-model" : selectedModel
        default:
            guard !selectedModel.isEmpty else { throw AIConversationError.missingModel(provider.label) }
            resolvedModel = selectedModel
        }
        let base = normalized(endpoint.isEmpty ? provider.defaultEndpoint : endpoint)
        guard !base.isEmpty else { throw AIConversationError.missingEndpoint }

        switch provider {
        case .ollama:
            return try await ollama(base: base, model: resolvedModel, prompt: prompt)
        case .anthropic:
            return try await anthropic(base: base, model: resolvedModel, key: key, prompt: prompt)
        case .gemini:
            return try await gemini(base: base, model: resolvedModel, key: key, prompt: prompt)
        case .cohere:
            return try await cohere(base: base, model: resolvedModel, key: key, prompt: prompt)
        default:
            return try await openAICompatible(base: base, model: resolvedModel, key: key, prompt: prompt)
        }
    }

    private static func ollama(base: String, model: String, prompt: String) async throws -> String {
        let body: [String: Any] = ["model": model, "messages": [["role": "user", "content": prompt]], "stream": false]
        let object = try await post(url: makeURL(base, "/api/chat"), body: body, headers: [:])
        return try text(from: object, paths: [["message", "content"], ["response"]])
    }

    private static func openAICompatible(base: String, model: String, key: String?, prompt: String) async throws -> String {
        let path: String
        if base.contains("/chat/completions") { path = "" }
        else if base.hasSuffix("/v1") { path = "/chat/completions" }
        else { path = "/v1/chat/completions" }
        var headers = [String: String]()
        if let key, !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
        let body: [String: Any] = ["model": model, "messages": [["role": "user", "content": prompt]], "temperature": 0.2]
        let object = try await post(url: makeURL(base, path), body: body, headers: headers)
        return try text(from: object, paths: [["choices", 0, "message", "content"], ["choices", 0, "text"]])
    }

    private static func anthropic(base: String, model: String, key: String?, prompt: String) async throws -> String {
        guard let key, !key.isEmpty else { throw AIConversationError.missingKey("Anthropic") }
        let body: [String: Any] = ["model": model, "max_tokens": 1_024, "messages": [["role": "user", "content": prompt]]]
        let object = try await post(url: makeURL(base, "/v1/messages"), body: body, headers: ["x-api-key": key, "anthropic-version": "2023-06-01"])
        return try text(from: object, paths: [["content", 0, "text"]])
    }

    private static func gemini(base: String, model: String, key: String?, prompt: String) async throws -> String {
        guard let key, !key.isEmpty else { throw AIConversationError.missingKey("Google Gemini") }
        var components = URLComponents(url: makeURL(base, "/v1beta/models/\(model):generateContent"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        let body: [String: Any] = ["contents": [["parts": [["text": prompt]]]]]
        let object = try await post(url: components.url!, body: body, headers: [:])
        return try text(from: object, paths: [["candidates", 0, "content", "parts", 0, "text"]])
    }

    private static func cohere(base: String, model: String, key: String?, prompt: String) async throws -> String {
        guard let key, !key.isEmpty else { throw AIConversationError.missingKey("Cohere") }
        let body: [String: Any] = ["model": model, "messages": [["role": "user", "content": prompt]]]
        let object = try await post(url: makeURL(base, "/v2/chat"), body: body, headers: ["Authorization": "Bearer \(key)"])
        return try text(from: object, paths: [["message", "content", 0, "text"], ["text"]])
    }

    private static func post(url: URL, body: [String: Any], headers: [String: String]) async throws -> Any {
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIConversationError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let detail = String(data: data, encoding: .utf8) ?? "No response body"
            throw AIConversationError.http(status: http.statusCode, detail: String(detail.prefix(360)))
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func text(from object: Any, paths: [[Any]]) throws -> String {
        for path in paths {
            var current: Any? = object
            for part in path {
                if let key = part as? String { current = (current as? [String: Any])?[key] }
                else if let index = part as? Int { current = (current as? [Any])?[safe: index] }
            }
            if let text = current as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        throw AIConversationError.unreadableResponse
    }

    private static func normalized(_ endpoint: String) -> String {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
    }

    private static func makeURL(_ base: String, _ path: String) -> URL {
        if path.isEmpty { return URL(string: base)! }
        return URL(string: base + path)!
    }
}

private enum AIConversationError: LocalizedError {
    case missingEndpoint
    case missingModel(String)
    case missingKey(String)
    case invalidResponse
    case unreadableResponse
    case http(status: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint: "Enter an endpoint before sending."
        case .missingModel(let provider): "Enter a model for \(provider) before sending."
        case .missingKey(let provider): "Add a \(provider) key before sending."
        case .invalidResponse: "The provider returned an invalid response."
        case .unreadableResponse: "The provider responded, but Sched could not read text from it."
        case .http(let status, let detail): "Provider returned HTTP \(status): \(detail)"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
