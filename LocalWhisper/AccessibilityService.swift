import AppKit
import ApplicationServices

/// System-level accessibility helpers for reading/writing text in any app.
/// Requires Accessibility permission in System Settings → Privacy & Security.
enum AccessibilityService {
    
    // MARK: - Permission Check
    
    static func isAccessibilityEnabled() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions(
            [key: false] as CFDictionary
        )
    }
    
    static func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions(
            [key: true] as CFDictionary
        )
    }
    
    // MARK: - Focused Element (via frontmost app)
    
    /// Returns the AXUIElement for the focused text element in the frontmost application.
    /// Uses NSWorkspace to get the frontmost app PID — more reliable than AX system-wide query.
    private static func focusedElement() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        return focusedElement(forPID: pid)
    }
    
    /// Returns the focused element for a specific app by PID.
    static func focusedElement(forPID pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success else { return nil }
        return (focusedElement as! AXUIElement)
    }
    
    /// Returns the PID of the current frontmost application.
    static func frontmostAppPID() -> pid_t? {
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
    
    // MARK: - Read Selected Text
    
    /// Gets the currently selected text from the frontmost app's focused text field.
    static func getSelectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        
        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success else {
            return nil
        }
        
        return selectedText as? String
    }
    
    // MARK: - Get Selection Position
    
    /// Gets the screen position of the current text selection for toolbar positioning.
    static func getSelectionBounds() -> CGRect? {
        guard let element = focusedElement() else { return nil }
        
        // Try to get selected text range
        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            return nil
        }
        
        // Get bounds for the selected text range
        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange!,
            &boundsValue
        ) == .success else {
            return nil
        }
        
        var bounds = CGRect.zero
        if AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds) {
            return bounds
        }
        return nil
    }
    
    // MARK: - Replace Selected Text
    
    /// Replaces the currently selected text in the frontmost app's focused text field.
    /// Uses clipboard-paste as the universal method — AX attribute setting is unreliable across apps.
    static func replaceSelectedText(_ newText: String) {
        // The text is already selected, so pasting will replace it
        injectViaClipboard(newText)
    }
    
    // MARK: - Inject Text
    
    /// Injects text at the cursor position in the target app.
    /// Uses clipboard-paste (Cmd+V) — works universally in every app.
    static func injectText(_ text: String, targetPID: pid_t? = nil) {
        injectViaClipboard(text)
    }
    
    /// Injects text by temporarily setting the clipboard and simulating Cmd+V.
    /// Runs paste simulation on a background thread with synchronous delays for precise timing.
    private static func injectViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        
        // Save current clipboard contents
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (NSPasteboard.PasteboardType, Data)? in
            // Save all types for each item
            for type in item.types {
                if let data = item.data(forType: type) {
                    return (type, data)
                }
            }
            return nil
        }
        
        // Set our text on the clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Run paste simulation on background thread with synchronous timing
        DispatchQueue.global(qos: .userInteractive).async {
            // Wait for clipboard to fully update
            usleep(100_000) // 100ms
            
            // Simulate Cmd+V with nil event source (clean slate, no stale modifiers from FN key)
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true) // 9 = 'v'
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cgSessionEventTap)
            
            usleep(50_000) // 50ms between key down and up
            
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.post(tap: .cgSessionEventTap)
            
            // Wait for the paste to complete before restoring clipboard
            usleep(500_000) // 500ms
            
            // Restore original clipboard on main thread
            DispatchQueue.main.async {
                pasteboard.clearContents()
                if let saved = savedItems, !saved.isEmpty {
                    for (type, data) in saved {
                        pasteboard.setData(data, forType: type)
                    }
                }
            }
        }
    }
}
