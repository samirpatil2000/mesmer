import AppKit
import SwiftUI

// MARK: - Dictation Pill Window

/// A floating dictation pill that mimics native macOS HUD design.
/// 180×48pt, frosted dark glass, mic icon + 5 organic waveform bars. Nothing else.
@MainActor
final class DictationPillWindow: NSPanel {
    
    private let pillWidth: CGFloat = 180
    private let pillHeight: CGFloat = 48
    private let bottomOffset: CGFloat = 32
    private let pillContent = DictationPillState()
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        
        // Build content
        let content = DictationPillContent(state: pillContent)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight)
        
        // Visual effect background
        let effectView = NSVisualEffectView(frame: hosting.bounds)
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = pillHeight / 2
        effectView.layer?.masksToBounds = true
        
        // Subtle inner border
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        
        // Container
        let container = NSView(frame: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight))
        container.wantsLayer = true
        container.layer?.cornerRadius = pillHeight / 2
        container.layer?.masksToBounds = true
        
        container.addSubview(effectView)
        effectView.frame = container.bounds
        effectView.autoresizingMask = [.width, .height]
        
        hosting.frame = container.bounds
        container.addSubview(hosting)
        hosting.autoresizingMask = [.width, .height]
        
        // Make hosting view transparent so the effect view shows through
        hosting.layer?.backgroundColor = .clear
        
        contentView = container
    }
    
    func showPill() {
        pillContent.isAutoListenMode = false
        pillContent.isPreparing = false
        updateBorderForAutoListen(false)
        // Position: centered horizontally, 32pt from bottom
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - pillWidth / 2
        let y = screen.frame.origin.y + bottomOffset
        setFrame(NSRect(x: x, y: y, width: pillWidth, height: pillHeight), display: true)
        
        // Start invisible and scaled down
        alphaValue = 0
        contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.7, y: 0.7))
        
        orderFrontRegardless()
        
        // Animate in: spring scale + fade
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 1.0
            self.contentView?.layer?.setAffineTransform(.identity)
        }
        
        // Start waveform
        pillContent.isAnimating = true
    }
    
    func showPreparing() {
        pillContent.isPreparing = true
        pillContent.isAnimating = false
        pillContent.isAutoListenMode = false
        updateBorderForAutoListen(false)
        
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - pillWidth / 2
        let y = screen.frame.origin.y + bottomOffset
        setFrame(NSRect(x: x, y: y, width: pillWidth, height: pillHeight), display: true)
        
        alphaValue = 0
        contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.7, y: 0.7))
        orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 1.0
            self.contentView?.layer?.setAffineTransform(.identity)
        }
    }

    func showAutoListenPill() {
        pillContent.isAutoListenMode = true
        pillContent.isPreparing = false
        pillContent.isAnimating = true
        updateBorderForAutoListen(true)

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - pillWidth / 2
        let y = screen.frame.origin.y + bottomOffset
        setFrame(NSRect(x: x, y: y, width: pillWidth, height: pillHeight), display: true)

        if isVisible {
            contentView?.layer?.setAffineTransform(.identity)
            alphaValue = 1.0
            orderFrontRegardless()
            return
        }

        alphaValue = 0
        contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.7, y: 0.7))
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 1.0
            self.contentView?.layer?.setAffineTransform(.identity)
        }
    }
    
    func hidePill() {
        pillContent.isAnimating = false
        pillContent.isPreparing = false
        pillContent.isAutoListenMode = false
        updateBorderForAutoListen(false)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 0
            self.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.85, y: 0.85))
        }, completionHandler: {
            self.orderOut(nil)
            self.contentView?.layer?.setAffineTransform(.identity)
        })
    }

    private func updateBorderForAutoListen(_ isAutoListen: Bool) {
        guard let container = contentView,
              let effectView = container.subviews.first(where: { $0 is NSVisualEffectView }) else { return }
        effectView.layer?.borderColor = isAutoListen
            ? NSColor(red: 1, green: 0.23, blue: 0.19, alpha: 0.45).cgColor
            : NSColor.white.withAlphaComponent(0.12).cgColor
    }
}

@MainActor
final class DictationToastWindow: NSPanel {

    private let toastWidth: CGFloat = 320
    private let toastHeight: CGFloat = 60
    private let bottomOffset: CGFloat = 92

    private let toastState = DictationToastState()
    private var dismissWorkItem: DispatchWorkItem?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        let content = DictationToastContent(state: toastState)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight)

        let effectView = NSVisualEffectView(frame: hosting.bounds)
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = toastHeight / 2
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let container = NSView(frame: NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight))
        container.wantsLayer = true
        container.layer?.cornerRadius = toastHeight / 2
        container.layer?.masksToBounds = true

        container.addSubview(effectView)
        effectView.frame = container.bounds
        effectView.autoresizingMask = [.width, .height]

        hosting.frame = container.bounds
        container.addSubview(hosting)
        hosting.autoresizingMask = [.width, .height]

        contentView = container
    }

    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }

    func show(message: String) {
        dismissWorkItem?.cancel()
        toastState.message = message

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - toastWidth / 2
        let y = screen.frame.origin.y + bottomOffset
        setFrame(NSRect(x: x, y: y, width: toastWidth, height: toastHeight), display: true)

        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 1.0
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideToast()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func hideToast() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

// MARK: - Pill State

@Observable
@MainActor
final class DictationPillState {
    var isAnimating: Bool = false
    var isPreparing: Bool = false
    var isAutoListenMode: Bool = false
}

@Observable
@MainActor
final class DictationToastState {
    var message: String = ""
}

// MARK: - Pill Content View (SwiftUI)

struct DictationPillContent: View {
    let state: DictationPillState
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 20)
            
            if state.isPreparing {
                // Formatting for Preparing state
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer().frame(width: 14)
                
                Text("Preparing...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                // Mic icon with glow
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.4), radius: 6, x: 0, y: 0)
                
                Spacer().frame(width: 16)
                
                // Five waveform bars
                WaveformBars(isAnimating: state.isAnimating)
            }
            
            Spacer()

            if state.isAutoListenMode {
                AutoListenDot()
                    .padding(.trailing, 14)
            }
        }
        .frame(width: 180, height: 48)
        .background(
            state.isAutoListenMode
                ? Color(red: 1, green: 0.23, blue: 0.19, opacity: 0.08)
                : Color.clear
        )
    }
}

private struct AutoListenDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color(red: 1, green: 0.23, blue: 0.19))
            .frame(width: 8, height: 8)
            .scaleEffect(pulsing ? 1.3 : 1.0)
            .opacity(pulsing ? 0.6 : 1.0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    pulsing = true
                }
            }
    }
}

struct DictationToastContent: View {
    let state: DictationToastState

    var body: some View {
        Text(state.message)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.92))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(width: 320, height: 60)
            .padding(.horizontal, 18)
    }
}

// MARK: - Waveform Bars

struct WaveformBars: View {
    let isAnimating: Bool
    
    // Unique timing for each bar — organic, not robotic
    private let barDurations: [Double] = [0.38, 0.45, 0.35, 0.50, 0.42]
    private let barMaxHeights: [CGFloat] = [14, 20, 16, 18, 12]
    private let barMinHeight: CGFloat = 4
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 3
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<5, id: \.self) { index in
                WaveformBar(
                    isAnimating: isAnimating,
                    minHeight: barMinHeight,
                    maxHeight: barMaxHeights[index],
                    duration: barDurations[index],
                    delay: Double(index) * 0.06
                )
            }
        }
    }
}

struct WaveformBar: View {
    let isAnimating: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let duration: Double
    let delay: Double
    
    @State private var animateToMax: Bool = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white)
            .frame(width: 3, height: animateToMax ? maxHeight : minHeight)
            .onChange(of: isAnimating) { _, active in
                if active {
                    startAnimation()
                } else {
                    stopAnimation()
                }
            }
            .onAppear {
                if isAnimating {
                    startAnimation()
                }
            }
    }
    
    private func startAnimation() {
        // Small stagger before starting
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(
                .spring(response: duration, dampingFraction: 0.5)
                .repeatForever(autoreverses: true)
            ) {
                animateToMax = true
            }
        }
    }
    
    private func stopAnimation() {
        withAnimation(.easeOut(duration: 0.15)) {
            animateToMax = false
        }
    }
}
