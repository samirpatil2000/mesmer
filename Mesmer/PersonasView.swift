import SwiftUI

struct PersonasView: View {
    @Bindable var manager: PersonaManager
    @State private var isAddingNew = false
    @State private var editingPersona: Persona?
    @State private var newName = ""
    @State private var newPrompt = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PERSONAS")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
                    .tracking(0.8)
                
                Spacer()
                
                if manager.canAdd {
                    NewPersonaButton {
                        newName = ""
                        newPrompt = ""
                        isAddingNew = true
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            if manager.personas.isEmpty && !isAddingNew {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.15))
                    
                    VStack(spacing: 4) {
                        Text("No Personas Yet")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.25))
                        Text("Tap + to create your first")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.18))
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(manager.personas) { persona in
                            PersonaCard(
                                persona: persona,
                                onEdit: { editingPersona = persona },
                                onDelete: { manager.delete(persona) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#0E0E0E"))
        .sheet(isPresented: $isAddingNew) {
            PersonaEditor(
                name: $newName,
                prompt: $newPrompt,
                onSave: {
                    manager.add(name: newName, systemPrompt: newPrompt)
                    isAddingNew = false
                },
                onCancel: { isAddingNew = false }
            )
        }
        .sheet(item: $editingPersona) { persona in
            PersonaEditor(
                name: Binding(
                    get: { persona.name },
                    set: { editingPersona?.name = $0 }
                ),
                prompt: Binding(
                    get: { persona.systemPrompt },
                    set: { editingPersona?.systemPrompt = $0 }
                ),
                onSave: {
                    if let p = editingPersona {
                        manager.update(p)
                    }
                    editingPersona = nil
                },
                onCancel: { editingPersona = nil }
            )
        }
    }
}

// MARK: - New Persona Button

private struct NewPersonaButton: View {
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(isHovering ? 1.0 : 0.7))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(isHovering ? 0.14 : 0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Persona Card

private struct PersonaCard: View {
    let persona: Persona
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(persona.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                
                Text(persona.systemPrompt)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.40))
                    .lineLimit(2)
            }
            
            Spacer()
            
            Image(systemName: "pencil")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(isHovering ? 0.5 : 0.0))
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .padding(16)
        .background(isHovering ? Color(hex: "#2C2C2E") : Color(hex: "#1C1C1E"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            // Instant transition for hover background per spec, using withAnimation for the pencil
            isHovering = hovering
        }
        .onTapGesture {
            onEdit()
        }
        .contextMenu {
            Button("Delete") {
                onDelete()
            }
        }
    }
}

// MARK: - Persona Editor

private struct PersonaEditor: View {
    @Binding var name: String
    @Binding var prompt: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @State private var isAppearing = false
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.bottom, 8)
                    .overlay(
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5),
                        alignment: .bottom
                    )
                
                ZStack(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("Describe how this persona rewrites text…")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.22))
                            .padding(.top, 4)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $prompt)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.92))
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }
                .overlay(
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5),
                    alignment: .bottom
                )
            }
            .padding(20)
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.40))
                .padding(.trailing, 16)
                
                Button(action: onSave) {
                    Text("Save")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 72, height: 36)
                        .background(
                            (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                             prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ?
                            Color.white.opacity(0.3) : Color.white
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 360)
        .background(Color(hex: "#1C1C1E"))
        .scaleEffect(isAppearing ? 1.0 : 0.95)
        .opacity(isAppearing ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isAppearing = true
            }
        }
    }
}
