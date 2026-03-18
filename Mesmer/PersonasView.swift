import SwiftUI

struct PersonasView: View {
    @Bindable var manager: PersonaManager
    @State private var expandedPersonaId: UUID?
    @State private var editingPersonaId: UUID?
    @State private var editName: String = ""
    @State private var editPrompt: String = ""
    @State private var isAddingNew = false
    @State private var newName = ""
    @State private var newPrompt = ""
    @State private var draftPersonaId: UUID?
    
    private var builtInPersonas: [Persona] {
        manager.personas.filter(\.isBuiltIn)
    }
    
    private var customPersonas: [Persona] {
        manager.personas.filter { !$0.isBuiltIn }
    }
    
    private var shouldShowCustomSection: Bool {
        !customPersonas.isEmpty || isAddingNew
    }
    
    private var draftPersona: Persona? {
        guard isAddingNew, let draftPersonaId else { return nil }
        return Persona(
            id: draftPersonaId,
            name: newName,
            systemPrompt: newPrompt,
            order: manager.personas.count,
            isEnabled: true,
            isBuiltIn: false,
            defaultPrompt: ""
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PERSONAS")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
                    .tracking(0.8)
                
                Spacer()
                
                NewPersonaButton(
                    isEnabled: manager.canAdd && !isAddingNew,
                    action: startAddingPersona
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "BUILT-IN")
                    
                    ForEach(builtInPersonas) { persona in
                        personaCard(for: persona)
                    }
                    
                    if shouldShowCustomSection {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 0.5)
                            .padding(.vertical, 8)
                        
                        SectionLabel(title: "CUSTOM")
                        
                        ForEach(customPersonas) { persona in
                            personaCard(for: persona)
                        }
                        
                        if let draftPersona {
                            personaCard(for: draftPersona, isDraft: true)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#0E0E0E"))
    }
    
    @ViewBuilder
    private func personaCard(for persona: Persona, isDraft: Bool = false) -> some View {
        PersonaCard(
            persona: persona,
            isExpanded: expandedPersonaId == persona.id,
            isEditing: editingPersonaId == persona.id,
            editName: editNameBinding(for: persona, isDraft: isDraft),
            editPrompt: editPromptBinding(for: persona, isDraft: isDraft),
            isToggleEnabledAvailable: !isDraft,
            onTap: {
                guard !(isDraft && editingPersonaId == persona.id) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedPersonaId == persona.id {
                        expandedPersonaId = nil
                        editingPersonaId = nil
                    } else {
                        expandedPersonaId = persona.id
                        editingPersonaId = nil
                    }
                }
            },
            onToggleEnabled: {
                guard !isDraft else { return }
                manager.toggleEnabled(persona)
            },
            onEdit: {
                if isDraft {
                    editName = newName
                    editPrompt = newPrompt
                } else {
                    editName = persona.name
                    editPrompt = persona.systemPrompt
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedPersonaId = persona.id
                    editingPersonaId = persona.id
                }
            },
            onSave: {
                let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedPrompt = editPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }
                
                if isDraft {
                    manager.add(name: editName, systemPrompt: editPrompt)
                    clearDraftState()
                } else {
                    var updated = persona
                    updated.name = editName
                    updated.systemPrompt = editPrompt
                    manager.update(updated)
                    editingPersonaId = nil
                }
            },
            onCancel: {
                if isDraft {
                    clearDraftState()
                } else {
                    editingPersonaId = nil
                }
            },
            onReset: {
                guard !isDraft else { return }
                manager.resetToDefault(persona)
            },
            onDelete: {
                guard !isDraft else {
                    clearDraftState()
                    return
                }
                manager.delete(persona)
                if expandedPersonaId == persona.id {
                    expandedPersonaId = nil
                }
                if editingPersonaId == persona.id {
                    editingPersonaId = nil
                }
            }
        )
    }
    
    private func editNameBinding(for persona: Persona, isDraft: Bool) -> Binding<String> {
        Binding(
            get: {
                if isDraft {
                    return editName
                }
                return editingPersonaId == persona.id ? editName : persona.name
            },
            set: { newValue in
                editName = newValue
                if isDraft {
                    newName = newValue
                }
            }
        )
    }
    
    private func editPromptBinding(for persona: Persona, isDraft: Bool) -> Binding<String> {
        Binding(
            get: {
                if isDraft {
                    return editPrompt
                }
                return editingPersonaId == persona.id ? editPrompt : persona.systemPrompt
            },
            set: { newValue in
                editPrompt = newValue
                if isDraft {
                    newPrompt = newValue
                }
            }
        )
    }
    
    private func startAddingPersona() {
        guard manager.canAdd, !isAddingNew else { return }
        let draftID = UUID()
        isAddingNew = true
        draftPersonaId = draftID
        newName = ""
        newPrompt = ""
        editName = ""
        editPrompt = ""
        
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedPersonaId = draftID
            editingPersonaId = draftID
        }
    }
    
    private func clearDraftState() {
        if let draftPersonaId, expandedPersonaId == draftPersonaId {
            expandedPersonaId = nil
        }
        if let draftPersonaId, editingPersonaId == draftPersonaId {
            editingPersonaId = nil
        }
        draftPersonaId = nil
        isAddingNew = false
        newName = ""
        newPrompt = ""
        editName = ""
        editPrompt = ""
    }
}

// MARK: - Section Label

private struct SectionLabel: View {
    let title: String
    
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.30))
            .tracking(1.0)
            .padding(.bottom, 2)
    }
}

// MARK: - New Persona Button

private struct NewPersonaButton: View {
    let isEnabled: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(isEnabled ? (isHovering ? 1.0 : 0.7) : 0.28))
                .frame(width: 28, height: 28)
                .background(
                    Color.white.opacity(isEnabled ? (isHovering ? 0.14 : 0.08) : 0.04)
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
    let isExpanded: Bool
    let isEditing: Bool
    @Binding var editName: String
    @Binding var editPrompt: String
    let isToggleEnabledAvailable: Bool
    let onTap: () -> Void
    let onToggleEnabled: () -> Void
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onReset: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    private var trimmedPrompt: String {
        persona.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var trimmedDefaultPrompt: String {
        persona.defaultPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var cardBackground: Color {
        if isExpanded {
            return Color(hex: "#1C1C1E")
        }
        return isHovering ? Color(hex: "#2C2C2E") : Color(hex: "#1C1C1E")
    }
    
    private var headerBackground: Color {
        if isExpanded && isHovering {
            return Color(hex: "#2C2C2E")
        }
        return .clear
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(16)
                .background(headerBackground)
            
            if isExpanded {
                Group {
                    if isEditing {
                        InlinePersonaEditor(
                            name: $editName,
                            prompt: $editPrompt,
                            onSave: onSave,
                            onCancel: onCancel
                        )
                    } else {
                        expandedContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
    
    private var headerRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(persona.isEnabled ? Color.green.opacity(0.85) : Color.white.opacity(0.15))
                .frame(width: 7, height: 7)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                
                Text(displayPrompt)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.40))
                    .lineLimit(2)
            }
            
            Spacer(minLength: 12)
            
            ToolbarVisibilityPill(
                isEnabled: persona.isEnabled,
                isButtonEnabled: isToggleEnabledAvailable,
                action: onToggleEnabled
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PROMPT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.40))
                    .tracking(0.5)
                
                Text(persona.systemPrompt)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            }
            
            HStack(spacing: 12) {
                Spacer()
                
                ActionButton(
                    title: "Edit",
                    icon: "pencil",
                    color: .white,
                    action: onEdit
                )
                
                if persona.isBuiltIn && trimmedPrompt != trimmedDefaultPrompt {
                    ActionButton(
                        title: "Reset",
                        icon: "arrow.uturn.backward",
                        color: Color.orange,
                        action: onReset
                    )
                }
                
                if !persona.isBuiltIn {
                    ActionButton(
                        title: "Delete",
                        icon: "trash",
                        color: Color.red,
                        action: onDelete
                    )
                }
            }
        }
    }
    
    private var displayName: String {
        if isEditing {
            return editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Persona" : editName
        }
        return persona.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Persona" : persona.name
    }
    
    private var displayPrompt: String {
        if isEditing {
            return editPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Describe how this persona rewrites text..."
                : editPrompt
        }
        return persona.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Describe how this persona rewrites text..."
            : persona.systemPrompt
    }
}

private struct ToolbarVisibilityPill: View {
    let isEnabled: Bool
    let isButtonEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(isEnabled ? "In toolbar" : "Hidden")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isEnabled ? Color.green.opacity(0.95) : Color.white.opacity(0.45))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(isEnabled ? Color.green.opacity(0.16) : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isButtonEnabled)
        .opacity(isButtonEnabled ? 1.0 : 0.6)
    }
}

private struct InlinePersonaEditor: View {
    @Binding var name: String
    @Binding var prompt: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var focusedField: Field?
    
    private enum Field {
        case name
        case prompt
    }
    
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
                .focused($focusedField, equals: .name)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Describe how this persona rewrites text...")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.22))
                        .padding(.top, 10)
                        .padding(.leading, 14)
                }
                
                TextEditor(text: $prompt)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(minHeight: 80)
                    .focused($focusedField, equals: .prompt)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            HStack(spacing: 12) {
                Spacer()
                
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                Button(action: onSave) {
                    Text("Save")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(canSave ? Color.blue : Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .name
            }
        }
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(color.opacity(isHovering ? 1.0 : 0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(isHovering ? 0.2 : 0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
