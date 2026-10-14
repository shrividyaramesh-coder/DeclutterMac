import Foundation

/// Provider options supported by Tidy Mac.
public enum AIProvider: String, CaseIterable, Sendable, Codable {
    case heuristic = "offline_heuristic"
    case anthropic = "anthropic"
    case openAI = "openai"
    
    public var displayName: String {
        switch self {
        case .heuristic: return "Offline Heuristic (Local)"
        case .anthropic: return "Anthropic (Claude)"
        case .openAI: return "OpenAI (GPT-4o)"
        }
    }
}

/// Provider-agnostic LLM interface.
/// SAFETY INVARIANT: Strictly accepts ONLY MetadataOnlyRequest.
/// File contents or file byte buffers CANNOT be passed to this protocol.
public protocol LLMClient: Sendable {
    var provider: AIProvider { get }
    func generatePlan(request: MetadataOnlyRequest) async throws -> CleaningPlan
}

/// Fully offline heuristic client conforming to LLMClient.
public struct HeuristicFallbackClient: LLMClient {
    public let provider: AIProvider = .heuristic
    private let parser = OfflineHeuristicParser()
    
    public init() {}
    
    public func generatePlan(request: MetadataOnlyRequest) async throws -> CleaningPlan {
        let plan = parser.parse(prompt: request.userPrompt)
        try CleaningPlanSchema.validate(plan)
        return plan
    }
}

/// Anthropic Claude Client.
public struct AnthropicClient: LLMClient {
    public let provider: AIProvider = .anthropic
    private let apiKey: String
    private let session: URLSession
    
    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }
    
    public func generatePlan(request: MetadataOnlyRequest) async throws -> CleaningPlan {
        let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let systemPrompt = """
        You are Tidy Mac's cleanup planner. Analyze the metadata and produce a JSON response adhering to this schema:
        {
          "userGoal": string,
          "summary": string,
          "steps": [
            {
              "targetFolder": string,
              "filter": {
                "categories": ["caches", "logs", "oldDownloads", "screenshots", "largeFiles", "trash", "appLeftovers"],
                "extensions": ["string"],
                "minimumAgeDays": int,
                "minimumSizeBytes": int,
                "nameContains": string
              },
              "action": "trash" | "review" | "move",
              "destinationFolder": string | null,
              "explanation": string
            }
          ]
        }
        Return ONLY valid JSON.
        """
        
        let filesSummary = request.files.prefix(50).map {
            "\($0.filename) (ext: \($0.fileExtension), size: \($0.sizeBytes), folder: \($0.relativeFolderPath))"
        }.joined(separator: "\n")
        
        let userContent = "User goal: \(request.userPrompt)\nCandidate sample files:\n\(filesSummary)"
        
        let body: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        // Parse JSON response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstText = content.first?["text"] as? String,
              let textData = firstText.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        
        let decoder = JSONDecoder()
        let plan = try decoder.decode(CleaningPlan.self, from: textData)
        try CleaningPlanSchema.validate(plan)
        return plan
    }
}

/// OpenAI Chat Completions Client.
public struct OpenAIClient: LLMClient {
    public let provider: AIProvider = .openAI
    private let apiKey: String
    private let session: URLSession
    
    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }
    
    public func generatePlan(request: MetadataOnlyRequest) async throws -> CleaningPlan {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let systemPrompt = """
        You are Tidy Mac's cleanup planner. Analyze metadata and output valid JSON conforming to the CleaningPlan schema:
        {
          "userGoal": string,
          "summary": string,
          "steps": [
            {
              "targetFolder": string,
              "filter": {
                "categories": ["caches", "logs", "oldDownloads", "screenshots", "largeFiles", "trash", "appLeftovers"],
                "extensions": ["string"],
                "minimumAgeDays": int,
                "minimumSizeBytes": int,
                "nameContains": string
              },
              "action": "trash" | "review" | "move",
              "destinationFolder": string | null,
              "explanation": string
            }
          ]
        }
        """
        
        let filesSummary = request.files.prefix(50).map {
            "\($0.filename) (ext: \($0.fileExtension), size: \($0.sizeBytes), folder: \($0.relativeFolderPath))"
        }.joined(separator: "\n")
        
        let userContent = "User goal: \(request.userPrompt)\nCandidate sample files:\n\(filesSummary)"
        
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "response_format": ["type": "json_object"]
        ]
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let contentString = message["content"] as? String,
              let contentData = contentString.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        
        let decoder = JSONDecoder()
        let plan = try decoder.decode(CleaningPlan.self, from: contentData)
        try CleaningPlanSchema.validate(plan)
        return plan
    }
}

/// Coordinator managing provider selection, keychain keys, and seamless offline heuristic fallback.
public actor AgentCoordinator {
    public static let shared = AgentCoordinator()
    
    private let keychain: KeychainService
    private let fallback = HeuristicFallbackClient()
    
    public init(keychain: KeychainService = .shared) {
        self.keychain = keychain
    }
    
    public func resolveClient(for provider: AIProvider) -> any LLMClient {
        switch provider {
        case .heuristic:
            return fallback
        case .anthropic:
            if let key = keychain.getKey(forAccount: "anthropic_api_key"), !key.isEmpty {
                return AnthropicClient(apiKey: key)
            }
            return fallback
        case .openAI:
            if let key = keychain.getKey(forAccount: "openai_api_key"), !key.isEmpty {
                return OpenAIClient(apiKey: key)
            }
            return fallback
        }
    }
    
    /// Requests a structured plan with guaranteed offline heuristic fallback if online requests fail.
    public func requestPlan(prompt: String, provider: AIProvider, sampleFiles: [FileMetadataEntry] = []) async -> CleaningPlan {
        let request = MetadataOnlyRequest(userPrompt: prompt, files: sampleFiles)
        let client = resolveClient(for: provider)
        
        do {
            return try await client.generatePlan(request: request)
        } catch {
            // Seamlessly fall back to local heuristic parser
            if let fallbackPlan = try? await fallback.generatePlan(request: request) {
                return fallbackPlan
            }
            return OfflineHeuristicParser().parse(prompt: prompt)
        }
    }
}
