import SwiftUI

struct HistoryView: View {
    @Bindable var manager: HistoryManager
    @State private var expandedEntryId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("HISTORY")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
                    .tracking(0.8)
                
                Spacer()
                
                Text("\(manager.entries.count) entries")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.22))
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            if manager.entries.isEmpty {
                HistoryEmptyState()
            } else {
                HistoryListView(manager: manager, expandedEntryId: $expandedEntryId)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#0E0E0E"))
    }
}

// MARK: - Subviews

private struct HistoryEmptyState: View {
    var body: some View {
        Spacer()
        VStack(spacing: 8) {
            Text("No history yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
            Text("Dictations and rewrites will appear here.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.18))
        }
        Spacer()
    }
}

private struct HistoryListView: View {
    @Bindable var manager: HistoryManager
    @Binding var expandedEntryId: UUID?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(manager.entries) { (entry: HistoryEntry) in
                    entryRow(for: entry)
                }
            }
            .padding(.bottom, 20)
        }
    }
    
    @ViewBuilder
    private func entryRow(for entry: HistoryEntry) -> some View {
        let isLast = entry.id == manager.entries.last?.id
        
        VStack(spacing: 0) {
            HistoryRow(
                entry: entry,
                isExpanded: expandedEntryId == entry.id,
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expandedEntryId == entry.id {
                            expandedEntryId = nil
                        } else {
                            expandedEntryId = entry.id
                        }
                    }
                }
            )
            
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.leading, 44)
            }
        }
    }
}


// MARK: - History Row

private struct HistoryRow: View {
    let entry: HistoryEntry
    let isExpanded: Bool
    let onToggle: () -> Void
    
    @State private var copied = false
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 0) {
                // Compact row
                HStack(spacing: 12) {
                    ActionBadge(action: entry.action)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.resultText)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(1)
                        
                        Text(entry.formattedTimestamp)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.28))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(height: 56)
                .contentShape(Rectangle())
                
                // Expanded details
                if isExpanded {
                    ExpandedDetails(entry: entry, copied: $copied)
                }
            }
            .background(isHovering ? Color.white.opacity(0.04) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            // Instant hover transition for lists
            isHovering = hover
        }
    }
}

// MARK: - Expanded Details

private struct ExpandedDetails: View {
    let entry: HistoryEntry
    @Binding var copied: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !entry.originalText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ORIGINAL")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.30))
                        .tracking(0.5)
                    Text(entry.originalText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.55))
                        .textSelection(.enabled)
                }
                .padding(.top, 4)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("RESULT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.30))
                    .tracking(0.5)
                Text(entry.resultText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.80))
                    .textSelection(.enabled)
            }
            .padding(.top, entry.originalText.isEmpty ? 4 : 0)
            
            HStack {
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.resultText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                }) {
                    Text(copied ? "Copied" : "Copy")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(copied ? .green : .white.opacity(0.30))
                }
                .buttonStyle(.plain)
            }
            
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.top, 4)
        }
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.bottom, 8)
    }
}

// MARK: - Action Badge

private struct ActionBadge: View {
    let action: HistoryAction
    
    private var icon: String {
        switch action {
        case .dictation: return "mic.fill"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .formal: return "briefcase"
        case .concise: return "arrow.down.right.and.arrow.up.left"
        case .friendly: return "face.smiling"
        case .custom: return "slider.horizontal.3"
        case .persona: return "person.fill"
        }
    }
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.35))
            .frame(width: 24, height: 24)
    }
}
