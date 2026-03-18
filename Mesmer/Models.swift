import Foundation

// MARK: - Persona

struct Persona: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var systemPrompt: String
    var order: Int
    var isEnabled: Bool = true
    var isBuiltIn: Bool = false
    var defaultPrompt: String = ""
    
    static let maxCount = 8
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case systemPrompt
        case order
        case isEnabled
        case isBuiltIn
        case defaultPrompt
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        systemPrompt: String,
        order: Int,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        defaultPrompt: String = ""
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.order = order
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.defaultPrompt = defaultPrompt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        order = try container.decode(Int.self, forKey: .order)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        defaultPrompt = try container.decodeIfPresent(String.self, forKey: .defaultPrompt) ?? ""
    }
}

// MARK: - History Entry

enum HistoryAction: String, Codable {
    case dictation = "Dictation"
    case rewrite = "Rewrite"
    case formal = "Formal"
    case concise = "Concise"
    case friendly = "Friendly"
    case custom = "Custom"
    case persona = "Persona"
}

enum InjectionStatus: String, Codable {
    case injected
    case fallback
    case clipboard_only
    case failed
}

struct DictationRecord: Codable {
    var text: String
    var timestamp: Date
    var injectionStatus: InjectionStatus
    var targetAppName: String?
    var wasFocusChanged: Bool
}

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var timestamp: Date
    var originalText: String
    var action: HistoryAction
    var styleName: String  // e.g. "Formal", "My CEO Voice", or custom instruction
    var resultText: String
    var dictationRecord: DictationRecord? = nil
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
