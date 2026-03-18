import AppKit
import SwiftUI
import ServiceManagement

/// App delegate that manages the menu bar icon, global event listeners,
/// and coordinates the background system-level features.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    // MARK: - Menu Bar
    
    private var statusItem: NSStatusItem!
    var onOpenWindowRequest: ((String) -> Void)?
    
    /// Strong reference to the main app window so it's never released.
    private weak var mainWindow: NSWindow?
    
    // MARK: - Managers
    
    let personaManager = PersonaManager()
    let historyManager = HistoryManager()
    let speechRecognizer = SpeechRecognizer()
    
    // MARK: - System-Level Components
    
    private var globalKeyListener: GlobalKeyListener!
    private var textSelectionObserver: TextSelectionObserver!
    private var dictationCoordinator: DictationCoordinator!
    private var rewriteCoordinator: RewriteCoordinator!
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupCoordinators()
        setupGlobalKeyListener()
        setupTextSelectionObserver()
        
        // Ensure accessibility permission is prompt-requested on launch 
        // if not already granted.
        AccessibilityService.requestAccessibilityPermission()
        
        // Hook into the main window as soon as it appears so we can intercept close.
        DispatchQueue.main.async {
            self.claimMainWindow()
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            await speechRecognizer.warmUp()
        }
    }
    
    /// Find the main app window and become its delegate so we can intercept close.
    func claimMainWindow() {
        guard mainWindow == nil else { return }
        // The main window is the first non-panel window
        if let win = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            self.mainWindow = win
            win.delegate = self
            configureWindow(win)
        }
    }
    
    // MARK: - NSWindowDelegate
    
    /// Instead of destroying the window, just hide it. This way makeKeyAndOrderFront
    /// will always work and we never lose the SwiftUI view hierarchy.
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor in
            sender.orderOut(nil)
        }
        return false
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Mesmer")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Mesmer", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let fnItem = NSMenuItem(title: "FN Dictation", action: nil, keyEquivalent: "")
        let fnEnabled = UserDefaults.standard.object(forKey: "fnDictationEnabled") as? Bool ?? true
        fnItem.state = fnEnabled ? .on : .off
        menu.addItem(fnItem)
        
        let toolbarItem = NSMenuItem(title: "Floating Toolbar", action: nil, keyEquivalent: "")
        let toolbarEnabled = UserDefaults.standard.object(forKey: "floatingToolbarEnabled") as? Bool ?? true
        toolbarItem.state = toolbarEnabled ? .on : .off
        menu.addItem(toolbarItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Mesmer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        
        // Try the stored reference first (window was hidden, not destroyed)
        if let window = mainWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) }) {
            mainWindow = window
            configureWindow(window)
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        // Fallback: window was somehow destroyed — ask SwiftUI to recreate it
        onOpenWindowRequest?("main")
    }
    
    private func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1.0) // #F2F2F7
    }
    
    // MARK: - Coordinators
    
    private func setupCoordinators() {
        dictationCoordinator = DictationCoordinator(
            speechRecognizer: speechRecognizer,
            historyManager: historyManager
        )
        
        rewriteCoordinator = RewriteCoordinator(
            historyManager: historyManager,
            personaManager: personaManager
        )
        
        Task { @MainActor in
            await speechRecognizer.warmUp()
        }
    }
    
    // MARK: - Global Key Listener
    
    private func setupGlobalKeyListener() {
        globalKeyListener = GlobalKeyListener()
        
        let fnEnabled = UserDefaults.standard.object(forKey: "fnDictationEnabled") as? Bool ?? true
        globalKeyListener.isEnabled = fnEnabled
        
        globalKeyListener.onFNDown = { [weak self] in
            await self?.dictationCoordinator.beginDictation()
        }
        
        globalKeyListener.onFNUp = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.dictationCoordinator.endDictation()
            }
        }

        globalKeyListener.onFNSpaceCombo = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.dictationCoordinator.beginAutoListenDictation()
            }
        }

        globalKeyListener.onEscapePressed = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.dictationCoordinator.cancelAutoListenDictation()
            }
        }
        
        globalKeyListener.start()
    }
    
    // MARK: - Text Selection Observer
    
    private func setupTextSelectionObserver() {
        textSelectionObserver = TextSelectionObserver()
        
        let toolbarEnabled = UserDefaults.standard.object(forKey: "floatingToolbarEnabled") as? Bool ?? true
        textSelectionObserver.isEnabled = toolbarEnabled
        rewriteCoordinator.textSelectionObserver = textSelectionObserver
        
        textSelectionObserver.onSelectionChanged = { [weak self] text, bounds in
            self?.rewriteCoordinator.showToolbar(selectedText: text, bounds: bounds)
        }
        
        textSelectionObserver.onSelectionCleared = { [weak self] in
            self?.rewriteCoordinator.hideToolbar()
        }
        
        textSelectionObserver.start()
    }
    
    // MARK: - Settings Callbacks
    
    func setFNDictationEnabled(_ enabled: Bool) {
        globalKeyListener.isEnabled = enabled
        if !enabled && dictationCoordinator.currentMode == .autoListen {
            Task { @MainActor in
                await dictationCoordinator.cancelAutoListenDictation()
            }
        }
    }
    
    func setFloatingToolbarEnabled(_ enabled: Bool) {
        textSelectionObserver.isEnabled = enabled
        if !enabled {
            rewriteCoordinator.hideToolbar()
        }
    }
    
    // MARK: - Launch at Login
    
    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "register" : "unregister") launch at login: \(error)")
        }
    }
}
