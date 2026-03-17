import Foundation

// MARK: - Persona

struct Persona: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var systemPrompt: String
    var order: Int
    
    static let maxCount = 8
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
