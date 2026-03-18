import Foundation

@MainActor
@Observable
final class HistoryManager {
    var entries: [HistoryEntry] = []
    
    private let fileURL: URL
    private let maxEntries = 500
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Mesmer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }
    
    // MARK: - Operations
    
    func log(originalText: String, action: HistoryAction, styleName: String, resultText: String) {
        let entry = HistoryEntry(
            timestamp: Date(),
            originalText: originalText,
            action: action,
            styleName: styleName,
            resultText: resultText
        )
        entries.insert(entry, at: 0) // newest first
        
        // Cap at maxEntries
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    @discardableResult
    func logDictation(
        text: String,
        targetAppName: String?,
        injectionStatus: InjectionStatus = .failed,
        wasFocusChanged: Bool = false
    ) -> UUID {
        let timestamp = Date()
        let entry = HistoryEntry(
            timestamp: timestamp,
            originalText: "",
            action: .dictation,
            styleName: "Dictation",
            resultText: text,
            dictationRecord: DictationRecord(
                text: text,
                timestamp: timestamp,
                injectionStatus: injectionStatus,
                targetAppName: targetAppName,
                wasFocusChanged: wasFocusChanged
            )
        )
        entries.insert(entry, at: 0)

        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
        return entry.id
    }

    func updateDictationRecord(
        id: UUID,
        text: String? = nil,
        injectionStatus: InjectionStatus,
        wasFocusChanged: Bool,
        targetAppName: String? = nil
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }

        var record = entries[index].dictationRecord ?? DictationRecord(
            text: entries[index].resultText,
            timestamp: entries[index].timestamp,
            injectionStatus: .failed,
            targetAppName: nil,
            wasFocusChanged: false
        )

        if let text {
            entries[index].resultText = text
            record.text = text
        }
        record.injectionStatus = injectionStatus
        record.wasFocusChanged = wasFocusChanged
        if let targetAppName {
            record.targetAppName = targetAppName
        }

        entries[index].dictationRecord = record
        save()
    }
    
    func clearAll() {
        entries.removeAll()
        save()
    }
    
    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([HistoryEntry].self, from: data)
        } catch {
            print("[HistoryManager] Failed to load: \(error)")
        }
    }
    
    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[HistoryManager] Failed to save: \(error)")
        }
    }
}
