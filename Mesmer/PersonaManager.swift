import Foundation

@MainActor
@Observable
final class PersonaManager {
    var personas: [Persona] = []
    
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
        guard personas.count < Persona.maxCount else { return }
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
        personas.removeAll { $0.id == persona.id }
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
        personas.count < Persona.maxCount
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            personas = try JSONDecoder().decode([Persona].self, from: data)
            personas.sort { $0.order < $1.order }
        } catch {
            print("[PersonaManager] Failed to load: \(error)")
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(personas)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[PersonaManager] Failed to save: \(error)")
        }
    }
}
