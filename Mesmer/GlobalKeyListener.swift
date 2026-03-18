import AppKit

/// Monitors the FN (Globe) key globally for hold-to-dictate functionality.
/// Uses NSEvent global/local monitors to detect flagsChanged and keyDown events.
@MainActor
final class GlobalKeyListener {
    
    var onFNDown: (() async -> Void)?
    var onFNUp: (() -> Void)?
    var onFNSpaceCombo: (() -> Void)?
    var onEscapePressed: (() -> Void)?
    
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var isFNHeld = false
    private var fnSpaceFired = false
    var isEnabled = true
    
    func start() {
        // Global monitor catches events when our app is NOT focused
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
        
        // Local monitor catches events when our app IS focused
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }

        // Global keyDown monitor observes Space/Escape when Mesmer is unfocused.
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDown(event)
            }
        }

        // Local keyDown monitor observes the same events when Mesmer is focused.
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDown(event)
            }
            return event
        }
    }
    
    func stop() {
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        if let monitor = globalKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyDownMonitor = nil
        }
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyDownMonitor = nil
        }
        isFNHeld = false
        fnSpaceFired = false
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let fnPressed = event.modifierFlags.contains(.function)
        
        guard isEnabled else {
            if !fnPressed {
                isFNHeld = false
                fnSpaceFired = false
            }
            return
        }
        
        if fnPressed && !isFNHeld {
            // FN key just pressed down
            isFNHeld = true
            fnSpaceFired = false
            Task { @MainActor in
                await onFNDown?()
            }
        } else if !fnPressed && isFNHeld {
            // FN key just released
            isFNHeld = false
            if fnSpaceFired {
                fnSpaceFired = false
                return
            }
            onFNUp?()
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard isEnabled else { return }

        if event.keyCode == 49 && isFNHeld && !fnSpaceFired {
            fnSpaceFired = true
            onFNSpaceCombo?()
            return
        }

        if event.keyCode == 53 {
            onEscapePressed?()
        }
    }
}
