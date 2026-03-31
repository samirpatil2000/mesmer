import AppKit
import ApplicationServices

enum InjectionFailureReason: Equatable {
    case accessibilityPermissionDenied
    case noFocusedEditableElement
    case secureTextField
    case pasteSimulationUnavailable
}

enum InjectionResult: Equatable {
    case success
    case failed(InjectionFailureReason)
    case uncertain
}

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

    static func copyTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    // MARK: - Focused Element
    
    /// Returns the focused element for the frontmost app, falling back to the system-wide
    /// focused element when the app-scoped query fails or resolves to a non-editable element.
    private static func focusedElement() -> AXUIElement? {
        let primaryElement = frontmostAppFocusedElement()
        if let primaryElement, isElementEditable(primaryElement) {
            return primaryElement
        }

        if let fallbackElement = systemWideFocusedElement() {
            return fallbackElement
        }

        return primaryElement
    }

    /// Returns the focused element for the frontmost app's process.
    private static func frontmostAppFocusedElement() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        return focusedElement(forPID: frontApp.processIdentifier)
    }

    /// Returns the focused element from the system-wide accessibility tree.
    private static func systemWideFocusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success else { return nil }
        guard let focusedElement else { return nil }
        return (focusedElement as! AXUIElement)
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

    static func frontmostAppName() -> String? {
        return NSWorkspace.shared.frontmostApplication?.localizedName
    }
    
    /// Checks if the currently focused element is an editable text field.
    /// Returns true for text fields and text areas that are not read-only.
    static func isFocusedElementEditable() -> Bool {
        guard isAccessibilityEnabled() else { return false }

        if let frontmostElement = frontmostAppFocusedElement(), isElementEditable(frontmostElement) {
            return true
        }

        guard let fallbackElement = systemWideFocusedElement() else { return false }
        return isElementEditable(fallbackElement)
    }
    
    // MARK: - Read Selected Text
    
    /// Gets the currently selected text from the frontmost app's focused text field.
    static func getSelectedText() -> String? {
        guard isAccessibilityEnabled() else { return nil }
        guard let element = focusedElement() else { return nil }
        
        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success else {
            return nil
        }
        
        return selectedText as? String
    }
    
    /// Attempts to get selected text using AXSelectedTextRange + AXValue.
    /// Works in apps like VS Code where AXSelectedText returns nil.
    /// Returns nil if either attribute is unavailable.
    static func getSelectedTextViaRange() -> String? {
        guard isAccessibilityEnabled() else { return nil }
        guard let element = focusedElement() else { return nil }

        // Get selected range
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success, let rangeValue else { return nil }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range),
              range.length > 0 else { return nil }

        // Get full text value
        var textValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        ) == .success,
        let fullText = textValue as? String else { return nil }

        // Extract selected substring
        let nsString = fullText as NSString
        guard range.location >= 0,
              range.location + range.length <= nsString.length else { return nil }

        return nsString.substring(
            with: NSRange(location: range.location, length: range.length)
        )
    }
    
    // MARK: - Get Selection Position
    
    /// Gets the screen position of the current text selection for toolbar positioning.
    static func getSelectionBounds() -> CGRect? {
        guard isAccessibilityEnabled() else { return nil }
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
    
    /// Injects text at the current cursor position in the frontmost app.
    /// Uses clipboard-paste (Cmd+V) after a best-effort secure-field check.
    /// The optional target PID is preserved for compatibility but not used to choose the destination.
    static func injectText(_ text: String, targetPID: pid_t? = nil) -> InjectionResult {
        guard isAccessibilityEnabled() else {
            return .failed(.accessibilityPermissionDenied)
        }

        // Preserve the signature for callers, but paste into whatever is focused now.
        _ = targetPID

        if let element = focusedElement(), isSecureTextField(element) {
            return .failed(.secureTextField)
        }

        return injectViaClipboard(text) ? .uncertain : .failed(.pasteSimulationUnavailable)
    }
    
    /// Injects text by temporarily setting the clipboard and simulating Cmd+V.
    /// Runs paste simulation on a background thread with synchronous delays for precise timing.
    @discardableResult
    private static func injectViaClipboard(_ text: String) -> Bool {
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
        guard pasteboard.setString(text, forType: .string) else {
            return false
        }
        
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

        return true
    }

    private static func isElementEditable(_ element: AXUIElement) -> Bool {
        let editableRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            "AXTextField",
            "AXTextArea",
            "AXComboBox",
            "AXSearchField"
        ]

        if let role = attributeValue(kAXRoleAttribute as CFString, on: element), editableRoles.contains(role) {
            return true
        }

        var isSettable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isSettable)
        return settableResult == .success && isSettable.boolValue
    }

    private static func isSecureTextField(_ element: AXUIElement) -> Bool {
        let secureRole = "AXSecureTextField"
        let role = attributeValue(kAXRoleAttribute as CFString, on: element)
        let subrole = attributeValue(kAXSubroleAttribute as CFString, on: element)
        return role == secureRole || subrole == secureRole
    }

    private static func attributeValue(_ attribute: CFString, on element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
