import AppKit
import SwiftUI

private enum ToolbarLayoutMetrics {
    static let minimumWidth: CGFloat = 290
    static let pillHeight: CGFloat = 28
    static let outerHorizontalPadding: CGFloat = 10
    static let outerVerticalPadding: CGFloat = 5
    static let dividerWidth: CGFloat = 0.5
    static let dividerHeight: CGFloat = 16
    static let rowSpacing: CGFloat = 6
    static let screenEdgePadding: CGFloat = 8
    static let selectionGap: CGFloat = 10
    static let cornerRadius: CGFloat = 19
    static let pillHorizontalPadding: CGFloat = 14
}

private struct ToolbarChipItem: Identifiable {
    let id: UUID
    let label: String
    let prompt: String
    let width: CGFloat
}

private struct ToolbarChipRow {
    let chips: [ToolbarChipItem]
    let width: CGFloat
}

private struct ToolbarLayoutResult {
    let size: NSSize
    let availableContentWidth: CGFloat
}

// MARK: - Rewrite Toolbar Window

/// Floating rewrite toolbar that appears above selected text.
/// NSPanel with .popover material, 5 action pills, custom instruction mode.
@MainActor
final class RewriteToolbarWindow: NSPanel {
    
    var onStyleSelected: ((_ personaID: UUID, _ styleName: String, _ prompt: String) -> Void)?
    var onDismiss: (() -> Void)?
    
    private let toolbarContent: ToolbarContentState
    private var hostingView: NSHostingView<RewriteToolbarContent>?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    
    init(personaManager: PersonaManager) {
        self.toolbarContent = ToolbarContentState(personaManager: personaManager)
        
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ToolbarLayoutMetrics.minimumWidth,
                height: ToolbarLayoutMetrics.pillHeight + (ToolbarLayoutMetrics.outerVerticalPadding * 2)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // We handle shadow manually
        // Use a menu-like window level so the toolbar reliably appears above browsers
        // and other app content without needing to activate LocalWhisper.
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
        
        setupContent()
        
        contentView?.wantsLayer = true
        contentView?.layer?.masksToBounds = false
    }
    
    private func setupContent() {
        toolbarContent.onAction = { [weak self] personaID, name, prompt in
            self?.onStyleSelected?(personaID, name, prompt)
        }
        
        let content = RewriteToolbarContent(state: toolbarContent)
        let hosting = NSHostingView(rootView: content)
        
        hostingView = hosting
        contentView = hosting
    }
    
    // MARK: - Show / Hide
    
    func showToolbar(
        at selectionBounds: CGRect,
        processing: Bool = false,
        activePersonaID: UUID? = nil
    ) {
        toolbarContent.isProcessing = processing
        toolbarContent.activePersonaID = activePersonaID
        
        if processing {
            // Don't reposition during processing — just update state
            return
        }
        
        let screen = screenContainingSelection(selectionBounds) ?? NSScreen.main
        let availableWindowWidth = max(
            1,
            (screen?.visibleFrame.width ?? ToolbarLayoutMetrics.minimumWidth) -
                (ToolbarLayoutMetrics.screenEdgePadding * 2)
        )
        let layout = toolbarLayout(
            personaManager: toolbarContent.personaManager,
            availableWindowWidth: availableWindowWidth
        )
        
        toolbarContent.availableContentWidth = layout.availableContentWidth
        
        // Calculate position relative to selection
        let position = calculatePosition(
            selectionBounds: selectionBounds,
            toolbarSize: layout.size,
            on: screen
        )
        
        // Set frame — calculate everything BEFORE showing
        setContentSize(layout.size)
        setFrameOrigin(position)
        
        // Start invisible and scaled
        alphaValue = 0
        contentView?.wantsLayer = true
        contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.92, y: 0.92))
        
        orderFrontRegardless()
        
        // Animate in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 1.0
            self.contentView?.layer?.setAffineTransform(.identity)
        }
        
        installDismissMonitors()
    }
    
    func hideToolbar() {
        removeDismissMonitors()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 0
            self.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.94, y: 0.94))
        }, completionHandler: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.alphaValue == 0 {
                    self.orderOut(nil)
                    self.contentView?.layer?.setAffineTransform(.identity)
                    self.toolbarContent.reset()
                    self.onDismiss?()
                }
            }
        })
    }
    
    
    // MARK: - Position Calculation
    
    private func calculatePosition(
        selectionBounds: CGRect,
        toolbarSize: NSSize,
        on screen: NSScreen?
    ) -> NSPoint {
        let selectionRect = appKitRect(fromAccessibility: selectionBounds)
        
        guard let screen else {
            return NSPoint(
                x: selectionRect.midX - toolbarSize.width / 2,
                y: selectionRect.maxY + ToolbarLayoutMetrics.selectionGap
            )
        }
        
        let screenFrame = screen.visibleFrame
        let gap = ToolbarLayoutMetrics.selectionGap
        let pad = ToolbarLayoutMetrics.screenEdgePadding
        
        // Try positioning above the selection first
        var y = selectionRect.maxY + gap
        
        // If too close to top of screen, flip to below
        if y + toolbarSize.height > screenFrame.maxY - pad {
            y = selectionRect.minY - gap - toolbarSize.height
        }
        
        y = min(y, screenFrame.maxY - toolbarSize.height - pad)
        y = max(y, screenFrame.minY + pad)
        
        // Horizontal: center on selection
        var x = selectionRect.midX - toolbarSize.width / 2
        
        // Clamp to screen edges
        if x < screenFrame.minX + pad {
            x = screenFrame.minX + pad
        }
        if x + toolbarSize.width > screenFrame.maxX - pad {
            x = screenFrame.maxX - pad - toolbarSize.width
        }
        
        return NSPoint(x: x, y: y)
    }
    
    // MARK: - Dismiss Monitors
    
    private func installDismissMonitors() {
        removeDismissMonitors()
        
        // Click outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.isVisible else { return }
            let loc = NSEvent.mouseLocation
            if !self.frame.contains(loc) {
                Task { @MainActor in
                    self.hideToolbar()
                }
            }
        }
        
        // Escape key
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.keyCode == 53 { // Escape
                Task { @MainActor in
                    self.hideToolbar()
                }
                return nil
            }
            return event
        }
    }
    
    private func removeDismissMonitors() {
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
}

@MainActor
private func toolbarLayout(
    personaManager: PersonaManager?,
    availableWindowWidth: CGFloat
) -> ToolbarLayoutResult {
    let constrainedWindowWidth = max(1, availableWindowWidth)
    let initialContentWidth = max(
        1,
        constrainedWindowWidth - (ToolbarLayoutMetrics.outerHorizontalPadding * 2)
    )
    let initialRows = toolbarRows(
        personaManager: personaManager,
        maxContentWidth: initialContentWidth
    )
    let initialRowWidth = initialRows.map(\.width).max() ?? 0
    var resolvedWindowWidth = min(
        constrainedWindowWidth,
        max(
            ToolbarLayoutMetrics.minimumWidth,
            initialRowWidth + (ToolbarLayoutMetrics.outerHorizontalPadding * 2)
        )
    )
    var resolvedContentWidth = max(
        1,
        resolvedWindowWidth - (ToolbarLayoutMetrics.outerHorizontalPadding * 2)
    )
    let rows = toolbarRows(
        personaManager: personaManager,
        maxContentWidth: resolvedContentWidth
    )
    let maxRowWidth = rows.map(\.width).max() ?? 0
    resolvedWindowWidth = min(
        constrainedWindowWidth,
        max(
            ToolbarLayoutMetrics.minimumWidth,
            maxRowWidth + (ToolbarLayoutMetrics.outerHorizontalPadding * 2)
        )
    )
    resolvedContentWidth = max(
        1,
        resolvedWindowWidth - (ToolbarLayoutMetrics.outerHorizontalPadding * 2)
    )
    
    let rowCount = max(rows.count, 1)
    let height =
        (ToolbarLayoutMetrics.outerVerticalPadding * 2) +
        (CGFloat(rowCount) * ToolbarLayoutMetrics.pillHeight) +
        (CGFloat(max(rowCount - 1, 0)) * ToolbarLayoutMetrics.rowSpacing)
    
    return ToolbarLayoutResult(
        size: NSSize(width: resolvedWindowWidth, height: height),
        availableContentWidth: resolvedContentWidth
    )
}

@MainActor
private func toolbarRows(
    personaManager: PersonaManager?,
    maxContentWidth: CGFloat
) -> [ToolbarChipRow] {
    let chips = toolbarChipItems(
        personaManager: personaManager,
        maxChipWidth: maxContentWidth
    )
    return wrapToolbarRows(chips: chips, maxContentWidth: maxContentWidth)
}

@MainActor
private func toolbarChipItems(
    personaManager: PersonaManager?,
    maxChipWidth: CGFloat
) -> [ToolbarChipItem] {
    let personaItems = (personaManager?.personas ?? [])
        .filter { $0.isEnabled }
        .map { persona in
        ToolbarChipItem(
            id: persona.id,
            label: persona.name,
            prompt: persona.systemPrompt,
            width: measuredPillWidth(label: persona.name, maxChipWidth: maxChipWidth)
        )
    }
    return personaItems
}

private func wrapToolbarRows(
    chips: [ToolbarChipItem],
    maxContentWidth: CGFloat
) -> [ToolbarChipRow] {
    guard !chips.isEmpty else { return [] }
    
    var rows: [ToolbarChipRow] = []
    var currentRow: [ToolbarChipItem] = []
    var currentWidth: CGFloat = 0
    
    for chip in chips {
        let dividerWidth = currentRow.isEmpty ? 0 : ToolbarLayoutMetrics.dividerWidth
        let proposedWidth = currentWidth + dividerWidth + chip.width
        
        if !currentRow.isEmpty && proposedWidth > maxContentWidth {
            rows.append(ToolbarChipRow(chips: currentRow, width: currentWidth))
            currentRow = [chip]
            currentWidth = chip.width
            continue
        }
        
        if !currentRow.isEmpty {
            currentWidth += ToolbarLayoutMetrics.dividerWidth
        }
        currentRow.append(chip)
        currentWidth += chip.width
    }
    
    if !currentRow.isEmpty {
        rows.append(ToolbarChipRow(chips: currentRow, width: currentWidth))
    }
    
    return rows
}

private func measuredPillWidth(label: String, maxChipWidth: CGFloat) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: pillLabelFont()]
    let textWidth = ceil((label as NSString).size(withAttributes: attributes).width)
    let paddedWidth = textWidth + (ToolbarLayoutMetrics.pillHorizontalPadding * 2)
    return min(paddedWidth, maxChipWidth)
}

private func pillLabelFont() -> NSFont {
    let baseFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor
    return NSFont(descriptor: roundedDescriptor, size: 12.5) ?? baseFont
}

private func screenContainingSelection(_ selectionBounds: CGRect) -> NSScreen? {
    let selectionRect = appKitRect(fromAccessibility: selectionBounds)
    return NSScreen.screens.first(where: { $0.frame.intersects(selectionRect) })
        ?? NSScreen.screens.first(where: { $0.frame.contains(selectionRect.center) })
}

private func appKitRect(fromAccessibility rect: CGRect) -> CGRect {
    let desktopMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
    return CGRect(
        x: rect.origin.x,
        y: desktopMaxY - rect.maxY,
        width: rect.width,
        height: rect.height
    )
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

// MARK: - Toolbar State

@Observable
@MainActor
final class ToolbarContentState {
    var isProcessing: Bool = false
    var activePersonaID: UUID? = nil
    var availableContentWidth: CGFloat =
        ToolbarLayoutMetrics.minimumWidth - (ToolbarLayoutMetrics.outerHorizontalPadding * 2)
    var onAction: ((_ personaID: UUID, _ name: String, _ prompt: String) -> Void)?
    
    // Hold reference to personas
    var personaManager: PersonaManager?
    
    init(personaManager: PersonaManager? = nil) {
        self.personaManager = personaManager
    }
    
    func reset() {
        isProcessing = false
        activePersonaID = nil
    }
}

// MARK: - Toolbar Content (SwiftUI)

struct RewriteToolbarContent: View {
    @Bindable var state: ToolbarContentState
    
    var body: some View {
        ZStack {
            // Fallback solid background just in case material fails to render
            Color(white: 0.12, opacity: 0.95)
            
            // Background: frosted glass
            VisualEffectBackground()
            
            // Shadow layer
            RoundedRectangle(cornerRadius: ToolbarLayoutMetrics.cornerRadius)
                .fill(Color.clear)
                .shadow(color: Color.black.opacity(0.30), radius: 16, x: 0, y: -4)
            
            // Border overlay
            RoundedRectangle(cornerRadius: ToolbarLayoutMetrics.cornerRadius)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            
            // Content
            PillsRow(state: state)
                .padding(.horizontal, ToolbarLayoutMetrics.outerHorizontalPadding)
                .padding(.vertical, ToolbarLayoutMetrics.outerVerticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: ToolbarLayoutMetrics.cornerRadius))
        .preferredColorScheme(.dark)
    }
}

// MARK: - Visual Effect Background (NSViewRepresentable)

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.state = .active
        view.blendingMode = .behindWindow
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.cornerRadius = ToolbarLayoutMetrics.cornerRadius
        view.layer?.masksToBounds = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Pills Row

struct PillsRow: View {
    let state: ToolbarContentState
    
    var body: some View {
        let rows = toolbarRows(
            personaManager: state.personaManager,
            maxContentWidth: state.availableContentWidth
        )
        
        VStack(spacing: ToolbarLayoutMetrics.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.chips.enumerated()), id: \.element.id) { index, chip in
                        if index > 0 {
                            PillDivider()
                        }
                        
                        PillButton(
                            label: chip.label,
                            totalWidth: chip.width,
                            isPulsing: state.isProcessing && state.activePersonaID == chip.id
                        ) {
                            state.onAction?(chip.id, chip.label, chip.prompt)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Pill Button

struct PillButton: View {
    let label: String
    let totalWidth: CGFloat?
    let isPulsing: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var pulseOpacity: Double = 0.88
    
    var body: some View {
        Group {
            if let totalWidth {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(labelColor)
                    .frame(
                        width: max(
                            0,
                            totalWidth - (ToolbarLayoutMetrics.pillHorizontalPadding * 2)
                        ),
                        alignment: .center
                    )
                    .padding(.horizontal, ToolbarLayoutMetrics.pillHorizontalPadding)
            } else {
                Text(label)
                    .fixedSize()
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundColor(labelColor)
                    .padding(.horizontal, ToolbarLayoutMetrics.pillHorizontalPadding)
            }
        }
        .frame(height: ToolbarLayoutMetrics.pillHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            // Flash effect
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isPressed = false
            }
            action()
        }
        .onChange(of: isPulsing) { _, pulsing in
            if pulsing {
                startPulse()
            }
        }
    }
    
    private var labelColor: Color {
        if isPulsing {
            return .white.opacity(pulseOpacity)
        }
        return isHovered ? .white : .white.opacity(0.88)
    }
    
    private var backgroundColor: Color {
        if isPressed {
            return .white.opacity(0.20)
        }
        return isHovered ? .white.opacity(0.10) : .clear
    }
    
    private func startPulse() {
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            pulseOpacity = 0.50
        }
    }
}

// MARK: - Pill Divider

struct PillDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(
                width: ToolbarLayoutMetrics.dividerWidth,
                height: ToolbarLayoutMetrics.dividerHeight
            )
    }
}
