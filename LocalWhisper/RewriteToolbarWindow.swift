import AppKit
import SwiftUI

// MARK: - Rewrite Toolbar Window

/// Floating rewrite toolbar that appears above selected text.
/// NSPanel with .popover material, 5 action pills, custom instruction mode.
@MainActor
final class RewriteToolbarWindow: NSPanel {
    
    var onStyleSelected: ((_ styleName: String, _ prompt: String) -> Void)?
    var onDismiss: (() -> Void)?
    
    private let toolbarHeight: CGFloat = 38
    private let toolbarContent: ToolbarContentState
    private var hostingView: NSHostingView<RewriteToolbarContent>?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    
    init() {
        self.toolbarContent = ToolbarContentState()
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 38),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // We handle shadow manually
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        
        setupContent()
    }
    
    private func setupContent() {
        toolbarContent.onAction = { [weak self] name, prompt in
            self?.onStyleSelected?(name, prompt)
        }
        
        let content = RewriteToolbarContent(state: toolbarContent)
        let hosting = NSHostingView(rootView: content)
        
        hostingView = hosting
        contentView = hosting
    }
    
    // MARK: - Show / Hide
    
    func showToolbar(at selectionBounds: CGRect, processing: Bool = false, activeStyle: String? = nil) {
        toolbarContent.isProcessing = processing
        toolbarContent.activeStyleName = activeStyle
        
        if processing {
            // Don't reposition during processing — just update state
            return
        }
        
        // Calculate intrinsic size — 4 pills fit in ~290pt
        let toolbarSize = NSSize(width: 290, height: toolbarHeight)
        
        // Calculate position relative to selection
        let position = calculatePosition(selectionBounds: selectionBounds, toolbarSize: toolbarSize)
        
        // Set frame — calculate everything BEFORE showing
        setContentSize(toolbarSize)
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
        }, completionHandler: {
            self.orderOut(nil)
            self.contentView?.layer?.setAffineTransform(.identity)
            self.toolbarContent.reset()
            self.onDismiss?()
        })
    }
    
    
    // MARK: - Position Calculation
    
    private func calculatePosition(selectionBounds: CGRect, toolbarSize: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: selectionBounds.midX - toolbarSize.width / 2,
                           y: selectionBounds.maxY + 10)
        }
        
        let screenFrame = screen.frame
        let gap: CGFloat = 10
        
        // macOS screen coordinates: origin at bottom-left, Y increases upward
        // AX bounds: origin at top-left, Y increases downward
        // Convert AX bounds to screen coordinates
        let selectionTop = screenFrame.height - selectionBounds.origin.y
        let selectionBottom = screenFrame.height - (selectionBounds.origin.y + selectionBounds.height)
        
        // Try positioning above the selection first
        var y = selectionTop + gap
        
        // If too close to top of screen, flip to below
        if y + toolbarSize.height > screenFrame.maxY - 10 {
            y = selectionBottom - gap - toolbarSize.height
        }
        
        // Horizontal: center on selection
        var x = selectionBounds.midX - toolbarSize.width / 2
        
        // Clamp to screen edges
        let pad: CGFloat = 8
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
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
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

// MARK: - Toolbar State

@Observable
@MainActor
final class ToolbarContentState {
    var isProcessing: Bool = false
    var activeStyleName: String? = nil
    var onAction: ((_ name: String, _ prompt: String) -> Void)?
    
    func reset() {
        isProcessing = false
        activeStyleName = nil
    }
}

// MARK: - Toolbar Content (SwiftUI)

struct RewriteToolbarContent: View {
    @Bindable var state: ToolbarContentState
    
    var body: some View {
        ZStack {
            // Background: frosted glass
            VisualEffectBackground()
            
            // Shadow layer
            RoundedRectangle(cornerRadius: 19)
                .fill(Color.clear)
                .shadow(color: Color.black.opacity(0.30), radius: 16, x: 0, y: -4)
            
            // Border overlay
            RoundedRectangle(cornerRadius: 19)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            
            // Content
            PillsRow(state: state)
        }
        .frame(height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 19))
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
        view.layer?.cornerRadius = 19
        view.layer?.masksToBounds = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Pills Row

struct PillsRow: View {
    let state: ToolbarContentState
    
    private let styles: [(String, String)] = [
        ("Rewrite", "Rewrite this text to be clearer and more polished while preserving the meaning."),
        ("Formal", "Rewrite this text in a formal, professional tone."),
        ("Concise", "Rewrite this text to be shorter and more concise while keeping the core meaning."),
        ("Friendly", "Rewrite this text in a warm, friendly, conversational tone."),
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 10)
            
            ForEach(Array(styles.enumerated()), id: \.offset) { index, style in
                if index > 0 {
                    PillDivider()
                }
                
                PillButton(
                    label: style.0,
                    isPulsing: state.isProcessing && state.activeStyleName == style.0
                ) {
                    state.onAction?(style.0, style.1)
                }
            }
            
            Spacer().frame(width: 10)
        }
    }
}

// MARK: - Pill Button

struct PillButton: View {
    let label: String
    let isPulsing: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var pulseOpacity: Double = 0.88
    
    var body: some View {
        Text(label)
            .fixedSize()
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundColor(labelColor)
            .padding(.horizontal, 14)
            .frame(height: 28)
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
            .frame(width: 0.5, height: 16)
    }
}


