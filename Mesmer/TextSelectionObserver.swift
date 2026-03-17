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
    
    func start() {
        // Poll every 300ms — fast enough to feel responsive, light enough to be invisible
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSelection()
            }
        }
    }
    
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        lastSelectedText = nil
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
            // Selection was cleared
            lastSelectedText = nil
            onSelectionCleared?()
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

        let normalized = bundleIdentifier.lowercased()
        return normalized.contains("chrome") || normalized.contains("chromium")
    }
}
