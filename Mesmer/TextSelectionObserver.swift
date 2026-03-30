import AppKit

/// Observes text selection changes in the frontmost application using polling.
/// When text is selected, calls the callback with the selected text and its screen position.
@MainActor
final class TextSelectionObserver {
    
    var onSelectionChanged: ((_ selectedText: String, _ bounds: CGRect) -> Void)?
    var onSelectionCleared: (() -> Void)?
    
    var isEnabled = true
    private var pollTimer: Timer?
    private var lastSelectedText: String?
    private var isRunningClipboardFallback = false
    private var mouseUpMonitor: Any?
    
    func start() {
        // Poll every 300ms — fast enough to feel responsive, light enough to be invisible
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSelection()
            }
        }
        
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseUp()
            }
        }
    }
    
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        lastSelectedText = nil
        
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
        isRunningClipboardFallback = false
    }
    
    private func checkSelection() {
        guard isEnabled else { return }
        
        let selectedText = AccessibilityService.getSelectedText()
        let trimmed = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isChromeFamilyApp = isFrontmostChromeFamilyApp()
        
        if let text = trimmed, !text.isEmpty {
            // Text is selected — only notify if it changed and the element is editable
            if text != lastSelectedText {
                lastSelectedText = text
                
                if !isChromeFamilyApp {
                    // Only show toolbar for editable text fields outside Chrome-family apps.
                    guard AccessibilityService.isFocusedElementEditable() else { return }
                }
                
                if let bounds = AccessibilityService.getSelectionBounds() {
                    onSelectionChanged?(text, bounds)
                }
            }
        } else if lastSelectedText != nil {
            // For Electron/Chromium apps AXSelectedText is always nil
            // so we never clear via polling — clearing is handled by 
            // the next mouseUp which will find no clipboard change
            if isFrontmostChromeFamilyApp() { return }
            lastSelectedText = nil
            onSelectionCleared?()
        }
    }

    private func handleMouseUp() {
        guard isEnabled else { return }
        guard isFrontmostChromeFamilyApp() else { return }
        guard !isRunningClipboardFallback else { return }

        isRunningClipboardFallback = true

        let pasteboard = NSPasteboard.general
        let savedChangeCount = pasteboard.changeCount

        // Save existing clipboard contents
        let savedContents: [(NSPasteboard.PasteboardType, Data)] = pasteboard
            .pasteboardItems?
            .compactMap { item in
                for type in item.types {
                    if let data = item.data(forType: type) {
                        return (type, data)
                    }
                }
                return nil
            } ?? []

        // Simulate Cmd+C
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)

        // Wait for clipboard to update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }

            defer {
                // Always restore original clipboard
                pasteboard.clearContents()
                for (type, data) in savedContents {
                    pasteboard.setData(data, forType: type)
                }
                self.isRunningClipboardFallback = false
            }

            // Nothing was copied — no selection
            guard pasteboard.changeCount != savedChangeCount else { return }
            guard let text = pasteboard.string(forType: .string) else { return }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard trimmed != self.lastSelectedText else { return }

            self.lastSelectedText = trimmed

            // Use mouse position as bounds since AX bounds don't work in these apps
            let mouse = NSEvent.mouseLocation
            let bounds = CGRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
            self.onSelectionChanged?(trimmed, bounds)
        }
    }
    
    /// Force re-check (e.g. after a rewrite completes and we expect selection to be gone)
    func clearTracking() {
        lastSelectedText = nil
    }

    private func isFrontmostChromeFamilyApp() -> Bool {
        guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        let knownElectronApps: Set<String> = [
            "com.google.antigravity",
            "com.microsoft.VSCode",
            "com.tinyspeck.slackmacgap",
        ]
        let normalized = bundleIdentifier.lowercased()
        return normalized.contains("chrome")
            || normalized.contains("chromium")
            || knownElectronApps.contains(bundleIdentifier)
    }
}
