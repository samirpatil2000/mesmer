import AppKit

@MainActor
final class TextSelectionObserver {

    var onSelectionChanged: ((_ selectedText: String, _ bounds: CGRect) -> Void)?
    var onSelectionCleared: (() -> Void)?
    var isEnabled = true

    private var pollTimer: Timer?
    private var mouseUpMonitor: Any?
    private var mouseDownMonitor: Any?
    private var lastSelectedText: String?
    private var mouseDownLocation: CGPoint = .zero
    private var isRunningClipboardFallback = false

    func start() {
        // Poll for native apps + clearing
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: 0.3,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.checkSelection() }
        }

        // Track mouseDown position
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] _ in
            Task { @MainActor in
                self?.mouseDownLocation = NSEvent.mouseLocation
            }
        }

        // Trigger clipboard fallback on mouseUp for Electron apps
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseUp
        ) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseUp(event: event)
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
        if let m = mouseDownMonitor {
            NSEvent.removeMonitor(m)
            mouseDownMonitor = nil
        }
        lastSelectedText = nil
        isRunningClipboardFallback = false
    }

    func clearTracking() {
        lastSelectedText = nil
    }

    // MARK: - Native app polling

    private func checkSelection() {
        guard isEnabled else { return }

        // Skip polling for Electron apps — handled by mouseUp
        if isFrontmostElectronApp() { return }

        let selectedText = AccessibilityService.getSelectedText()
        let trimmed = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let text = trimmed, !text.isEmpty {
            if text != lastSelectedText {
                lastSelectedText = text
                guard AccessibilityService.isFocusedElementEditable() else { return }
                if let bounds = AccessibilityService.getSelectionBounds() {
                    onSelectionChanged?(text, bounds)
                }
            }
        } else if lastSelectedText != nil {
            lastSelectedText = nil
            onSelectionCleared?()
        }
    }

    // MARK: - Electron app clipboard fallback

    private func handleMouseUp(event: NSEvent) {
        guard isEnabled else { return }
        guard isFrontmostElectronApp() else { return }
        guard !isRunningClipboardFallback else { return }

        // ONLY fire on actual drag (distance > 5pt) OR double/triple click
        // This prevents plain cursor-positioning clicks from triggering Cmd+C
        let upLocation = NSEvent.mouseLocation
        let dx = upLocation.x - mouseDownLocation.x
        let dy = upLocation.y - mouseDownLocation.y
        let distance = sqrt(dx * dx + dy * dy)
        let isMultiClick = event.clickCount >= 2

        guard distance > 5.0 || isMultiClick else { return }

        isRunningClipboardFallback = true

        let pasteboard = NSPasteboard.general
        let savedChangeCount = pasteboard.changeCount

        // Simulate Cmd+C
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.isRunningClipboardFallback = false

            // If clipboard didn't change, nothing was selected — bail out
            // This also handles VS Code's "copy line" edge case:
            // if user had no selection, changeCount still moves but
            // we check the guard below
            guard pasteboard.changeCount != savedChangeCount else { return }
            guard let text = pasteboard.string(forType: .string) else { return }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard trimmed != self.lastSelectedText else { return }

            self.lastSelectedText = trimmed

            let mouse = NSEvent.mouseLocation
            let bounds = CGRect(
                x: mouse.x, y: mouse.y,
                width: 1, height: 1
            )
            self.onSelectionChanged?(trimmed, bounds)
        }
    }

    // MARK: - Electron/Chromium detection

    private func isFrontmostElectronApp() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let bundle = app.bundleIdentifier ?? ""
        let knownElectronApps: Set<String> = [
            "com.google.antigravity",
            "com.microsoft.VSCode",
            "com.tinyspeck.slackmacgap",
            "com.hnc.Discord",
            "md.obsidian",
            "notion.id",
        ]
        return knownElectronApps.contains(bundle)
            || bundle.lowercased().contains("chrome")
            || bundle.lowercased().contains("chromium")
            || bundle.lowercased().contains("electron")
    }
}
