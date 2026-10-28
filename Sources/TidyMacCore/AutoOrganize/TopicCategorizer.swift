import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Groups items into short topic folders ("Tax Documents", "Travel") from their names alone.
public protocol TopicCategorizing: Sendable {
    /// Returns a topic folder name for each item name it could place. Missing names fall back to file-type folders.
    func topics(for itemNames: [String], existingTopics: [String]) async -> [String: String]
}

public enum TopicNames {
    public static let maxLength = 40

    /// Cleans a model-suggested folder name into something safe to create on disk, or nil if unusable.
    public static func sanitize(_ raw: String) -> String? {
        let disallowed = CharacterSet(charactersIn: "/:\\\0").union(.newlines).union(.controlCharacters)
        let cleaned = raw.components(separatedBy: disallowed).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !cleaned.isEmpty, cleaned.count <= maxLength else { return nil }
        return cleaned
    }
}

public enum TopicCategorizerFactory {
    /// Apple's on-device model when this Mac supports it (macOS 26+ with Apple Intelligence enabled), else nil.
    public static func onDevice() -> TopicCategorizing? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            return AppleIntelligenceCategorizer()
        }
        #endif
        return nil
    }

    public static var isOnDeviceModelAvailable: Bool {
        onDevice() != nil
    }
}

public enum TopicResponseParser {
    /// Reads the model's JSON reply (`{"Item name": "Folder", ...}`), tolerating a Markdown code fence.
    /// Only names from `allowedNames` are kept, and folder names are sanitized.
    public static func parse(_ response: String, allowedNames: Set<String>) -> [String: String] {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close {
            text = String(text[open...close])
        }
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: String] = [:]
        for (name, value) in raw {
            guard allowedNames.contains(name), let folder = (value as? String).flatMap(TopicNames.sanitize) else { continue }
            result[name] = folder
        }
        return result
    }
}

#if canImport(FoundationModels)
/// On-device topic grouping. Only item names are given to the model; file contents are never read,
/// and nothing leaves the Mac.
@available(macOS 26.0, *)
public struct AppleIntelligenceCategorizer: TopicCategorizing {
    static let batchSize = 25
    
    static let instructions = """
    You organize a person's Mac files into topic folders, like a tidy filing cabinet.
    Given file and folder names, choose a short topic folder for each one based on what the name suggests,
    for example Tax Documents, Travel, Invoices, Work Projects, Photos, Installers, Receipts, School.
    Folder names are Title Case, one to three words. Reuse an existing folder whenever one fits,
    and keep the number of distinct folders small.
    Reply with only a JSON object mapping each item name, copied exactly, to its folder name.
    """
    
    public init() {}
    
    public func topics(for itemNames: [String], existingTopics: [String]) async -> [String: String] {
        var result: [String: String] = [:]
        var knownTopics = existingTopics
        let names = Array(Set(itemNames)).sorted()
        
        for start in stride(from: 0, to: names.count, by: Self.batchSize) {
            let batch = Array(names[start..<min(start + Self.batchSize, names.count)])
            let session = LanguageModelSession(instructions: Self.instructions)
            let existing = knownTopics.isEmpty ? "none yet" : knownTopics.joined(separator: ", ")
            let prompt = "Existing folders: \(existing)\n\nItems:\n" + batch.map { "- \($0)" }.joined(separator: "\n")
            guard let response = try? await session.respond(to: prompt) else { continue }
            let assignments = TopicResponseParser.parse(response.content, allowedNames: Set(batch))
            for (name, folder) in assignments {
                result[name] = folder
                if !knownTopics.contains(folder) { knownTopics.append(folder) }
            }
        }
        return result
    }
}
#endif
