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
    
    private var hostingView: NSHostingView<DictationPillContent>?
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
    
    func hidePill() {
        pillContent.isAnimating = false
        
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
}

// MARK: - Pill State

@Observable
@MainActor
final class DictationPillState {
    var isAnimating: Bool = false
}

// MARK: - Pill Content View (SwiftUI)

struct DictationPillContent: View {
    let state: DictationPillState
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 20)
            
            // Mic icon with glow
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .shadow(color: .white.opacity(0.4), radius: 6, x: 0, y: 0)
            
            Spacer().frame(width: 16)
            
            // Five waveform bars
            WaveformBars(isAnimating: state.isAnimating)
            
            Spacer()
        }
        .frame(width: 180, height: 48)
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
