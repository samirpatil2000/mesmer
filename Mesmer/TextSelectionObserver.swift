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
    private var consecutiveEditableFailures: Int = 0
    
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
        consecutiveEditableFailures = 0
    }
    
    private func checkSelection() {
        guard isEnabled else { return }
        
        guard let fetchResult = AccessibilityService.getSelectedTextAndBounds() else {
            // Selection was cleared or unavailable
            if lastSelectedText != nil {
                lastSelectedText = nil
                onSelectionCleared?()
            }
            return
        }
        
        let text = fetchResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bounds = fetchResult.bounds
        let isChromeFamilyApp = isFrontmostChromeFamilyApp()
        
        if !text.isEmpty {
            // Text is selected — only notify if it changed and the element is editable
            if text != lastSelectedText {
                if !isChromeFamilyApp {
                    // Only show toolbar for editable text fields outside Chrome-family apps.
                    if !AccessibilityService.isFocusedElementEditable() {
                        consecutiveEditableFailures += 1
                        if consecutiveEditableFailures >= 2 {
                            return // Block toolbar after 2 consecutive failures
                        } else {
                            // Allow one transient failure, but don't show the toolbar yet.
                            // We will check again on the next poll.
                            return
                        }
                    } else {
                        consecutiveEditableFailures = 0
                    }
                }
                
                lastSelectedText = text
                onSelectionChanged?(text, bounds)
            }
        } else if lastSelectedText != nil {
            // Selection was cleared (text is empty but was previously non-empty)
            lastSelectedText = nil
            onSelectionCleared?()
        }
    }
    
    /// Force re-check (e.g. after a rewrite completes and we expect selection to be gone)
    func clearTracking() {
        lastSelectedText = nil
        consecutiveEditableFailures = 0
    }

    private func isFrontmostChromeFamilyApp() -> Bool {
        guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }

        let normalized = bundleIdentifier.lowercased()
        return normalized.contains("chrome") || normalized.contains("chromium")
    }
}
