import Foundation

@MainActor
@Observable
final class PersonaManager {
    var personas: [Persona] = []
    
    private static let rewriteID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private static let formalID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
    private static let conciseID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003")!
    private static let friendlyID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000004")!
    
    private static let builtInDefinitions: [Persona] = [
        Persona(
            id: rewriteID,
            name: "Rewrite",
            systemPrompt: "Rewrite this text to be clearer and more polished while preserving the meaning.",
            order: 0,
            isEnabled: true,
            isBuiltIn: true,
            defaultPrompt: "Rewrite this text to be clearer and more polished while preserving the meaning."
        ),
        Persona(
            id: formalID,
            name: "Formal",
            systemPrompt: "Rewrite this text in a formal, professional tone.",
            order: 1,
            isEnabled: true,
            isBuiltIn: true,
            defaultPrompt: "Rewrite this text in a formal, professional tone."
        ),
        Persona(
            id: conciseID,
            name: "Concise",
            systemPrompt: "Rewrite this text to be shorter and more concise while keeping the core meaning.",
            order: 2,
            isEnabled: true,
            isBuiltIn: true,
            defaultPrompt: "Rewrite this text to be shorter and more concise while keeping the core meaning."
        ),
        Persona(
            id: friendlyID,
            name: "Friendly",
            systemPrompt: "Rewrite this text in a warm, friendly, conversational tone.",
            order: 3,
            isEnabled: true,
            isBuiltIn: true,
            defaultPrompt: "Rewrite this text in a warm, friendly, conversational tone."
        ),
    ]
    private static let builtInIDs = Set(builtInDefinitions.map(\.id))
    
    private let fileURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Mesmer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("personas.json")
        load()
    }
    
    // MARK: - CRUD
    
    func add(name: String, systemPrompt: String) {
        guard customPersonaCount < Persona.maxCount else { return }
        let newOrder = (personas.map(\.order).max() ?? -1) + 1
        let persona = Persona(name: name, systemPrompt: systemPrompt, order: newOrder)
        personas.append(persona)
        save()
    }
    
    func update(_ persona: Persona) {
        guard let index = personas.firstIndex(where: { $0.id == persona.id }) else { return }
        personas[index] = persona
        save()
    }
    
    func delete(_ persona: Persona) {
        guard !persona.isBuiltIn else { return }
        personas.removeAll { $0.id == persona.id }
        save()
    }
    
    func toggleEnabled(_ persona: Persona) {
        guard let index = personas.firstIndex(where: { $0.id == persona.id }) else { return }
        personas[index].isEnabled.toggle()
        save()
    }
    
    func resetToDefault(_ persona: Persona) {
        guard let index = personas.firstIndex(where: { $0.id == persona.id }) else { return }
        personas[index].systemPrompt = personas[index].defaultPrompt
        save()
    }
    
    func move(from source: IndexSet, to destination: Int) {
        personas.move(fromOffsets: source, toOffset: destination)
        for (i, _) in personas.enumerated() {
            personas[i].order = i
        }
        save()
    }
    
    var canAdd: Bool {
        customPersonaCount < Persona.maxCount
    }
    
    func historyAction(for personaID: UUID) -> HistoryAction {
        switch personaID {
        case Self.rewriteID:
            return .rewrite
        case Self.formalID:
            return .formal
        case Self.conciseID:
            return .concise
        case Self.friendlyID:
            return .friendly
        default:
            return .persona
        }
    }
    
    // MARK: - Persistence
    
    private func load() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                personas = try JSONDecoder().decode([Persona].self, from: data)
            } catch {
                print("[PersonaManager] Failed to load: \(error)")
            }
        }
        
        seedBuiltIns()
        normalizeOrder()
    }
    
    func save() {
        do {
            normalizeOrder()
            let data = try JSONEncoder().encode(personas)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[PersonaManager] Failed to save: \(error)")
        }
    }
    
    private var customPersonaCount: Int {
        personas.filter { !$0.isBuiltIn }.count
    }
    
    private func seedBuiltIns() {
        for definition in Self.builtInDefinitions where !personas.contains(where: { $0.id == definition.id }) {
            personas.append(definition)
        }
    }
    
    private func normalizeOrder() {
        let existingByID = Dictionary(uniqueKeysWithValues: personas.map { ($0.id, $0) })
        let builtIns = Self.builtInDefinitions.enumerated().map { index, definition in
            var persona = existingByID[definition.id] ?? definition
            persona.id = definition.id
            persona.order = index
            persona.isBuiltIn = true
            if persona.defaultPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                persona.defaultPrompt = definition.defaultPrompt
            }
            return persona
        }
        
        let customs = personas
            .filter { !Self.builtInIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.order < rhs.order
            }
            .enumerated()
            .map { index, persona in
                var updated = persona
                updated.isBuiltIn = false
                updated.defaultPrompt = ""
                updated.order = builtIns.count + index
                return updated
            }
        
        personas = builtIns + customs
    }
}
