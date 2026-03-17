import AppKit

/// Monitors the FN (Globe) key globally for hold-to-dictate functionality.
/// Uses NSEvent global/local monitors to detect flagsChanged events.
@MainActor
final class GlobalKeyListener {
    
    var onFNDown: (() async -> Void)?
    var onFNUp: (() -> Void)?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isFNHeld = false
    var isEnabled = true
    
    func start() {
        // Global monitor catches events when our app is NOT focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
        
        // Local monitor catches events when our app IS focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }
    }
    
    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isFNHeld = false
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        guard isEnabled else { return }
        
        let fnPressed = event.modifierFlags.contains(.function)
        
        if fnPressed && !isFNHeld {
            // FN key just pressed down
            isFNHeld = true
            Task { @MainActor in
                await onFNDown?()
            }
        } else if !fnPressed && isFNHeld {
            // FN key just released
            isFNHeld = false
            onFNUp?()
        }
    }
}
