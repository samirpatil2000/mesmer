import SwiftUI
import Speech
import AVFoundation
import FoundationModels

// MARK: - App Entry Point

@main
struct LocalWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) var openWindow
    
    var body: some Scene {
        WindowGroup(id: "main") {
            MainAppView(
                personaManager: appDelegate.personaManager,
                historyManager: appDelegate.historyManager,
                onFNToggleChanged: { [weak appDelegate] enabled in
                    appDelegate?.setFNDictationEnabled(enabled)
                },
                onToolbarToggleChanged: { [weak appDelegate] enabled in
                    appDelegate?.setFloatingToolbarEnabled(enabled)
                }
            )
            .onAppear {
                appDelegate.onOpenWindowRequest = { id in
                    openWindow(id: id)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 600, height: 680)
    }
}

// MARK: - Main App View (Three-Tab Layout)

struct MainAppView: View {
    let personaManager: PersonaManager
    let historyManager: HistoryManager
    var onFNToggleChanged: ((Bool) -> Void)?
    var onToolbarToggleChanged: ((Bool) -> Void)?
    
    @State private var selectedTab: AppTab = .personas
    @State private var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var bannerDismissed: Bool = false
    @Namespace private var animation
    
    enum AppTab: String, CaseIterable {
        case personas = "Personas"
        case history = "History"
        case settings = "Settings"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Accessibility Banner
            if !isAccessibilityGranted && !bannerDismissed {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility access required for text injection.")
                            .font(.system(size: 13, weight: .medium))
                        Text("Restart the app after granting access.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Grant Access") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 13, weight: .semibold))
                    
                    Button(action: { bannerDismissed = true }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.yellow.opacity(0.15))
                .overlay(
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 0.5),
                    alignment: .bottom
                )
            }
            
            // Tab bar
            HStack(spacing: 32) {
                Spacer()
                ForEach(AppTab.allCases, id: \.self) { tab in
                    TabButton(
                        title: tab.rawValue,
                        icon: tabIcon(tab),
                        isSelected: selectedTab == tab,
                        namespace: animation
                    ) {
                        // Use a faster spring for snappier native feel
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    }
                }
                Spacer()
            }
            .frame(height: 60)
            .padding(.top, 8)
            
            // Tab content
            Group {
                switch selectedTab {
                case .personas:
                    PersonasView(manager: personaManager)
                case .history:
                    HistoryView(manager: historyManager)
                case .settings:
                    SettingsView(
                        historyManager: historyManager,
                        onFNToggleChanged: onFNToggleChanged,
                        onToolbarToggleChanged: onToolbarToggleChanged
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Color(hex: "#0E0E0E"))
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            let granted = AXIsProcessTrusted()
            if granted != isAccessibilityGranted {
                isAccessibilityGranted = granted
            }
        }
    }
    
    private func tabIcon(_ tab: AppTab) -> String {
        switch tab {
        case .personas: return "person.2"
        case .history: return "clock"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 24, height: 2)
                        .matchedGeometryEffect(id: "TAB_INDICATOR", in: namespace)
                } else {
                    Color.clear.frame(height: 2)
                }
            }
            .frame(width: 60)
            .foregroundColor(.white.opacity(isSelected ? 0.9 : 0.3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Corrections Dictionary

struct CorrectionEntry: Codable, Identifiable {
    var id = UUID()
    var spoken: String
    var corrected: String
}

@MainActor
final class CorrectionsDictionary: ObservableObject {
    @Published var entries: [CorrectionEntry] = [] {
        didSet {
            save()
        }
    }
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "LocalWhisper.Corrections"),
           let decoded = try? JSONDecoder().decode([CorrectionEntry].self, from: data) {
            self.entries = decoded
        }
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: "LocalWhisper.Corrections")
        }
    }
    
    func add(spoken: String, corrected: String) {
        let trimmedSpoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCorrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSpoken.isEmpty, !trimmedCorrected.isEmpty else { return }
        entries.append(CorrectionEntry(spoken: trimmedSpoken, corrected: trimmedCorrected))
    }
    
    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }
    
    /// Layer 1: Instant find-and-replace on transcript (case-insensitive)
    func apply(to text: String) -> String {
        var result = text
        for entry in entries {
            result = result.replacingOccurrences(
                of: "(?i)\\b\(NSRegularExpression.escapedPattern(for: entry.spoken))\\b",
                with: entry.corrected,
                options: .regularExpression
            )
        }
        return result
    }
    
    /// Layer 2: Formatted context block for the AI Prompt
    func contextBlock() -> String {
        guard !entries.isEmpty else { return "" }
        var block = "\nPERSONAL DICTIONARY (always apply these corrections):\n"
        for entry in entries {
            block += "- \"\(entry.spoken)\" → \"\(entry.corrected)\"\n"
        }
        return block
    }
}

// MARK: - Speech Recognizer

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String? = nil
    
    var corrections: CorrectionsDictionary?
    
    /// Text accumulated from previous recognition sessions within
    /// the same recording. Each time Apple's recognizer times out
    /// (~60s), we save what we have here and restart seamlessly.
    private var accumulatedTranscript: String = ""
    
    /// The partial text from the current recognition session only.
    private var currentSessionText: String = ""
    
    /// Whether the user intentionally stopped recording (vs. auto-restart).
    private var userRequestedStop: Bool = false
    
    /// Continuation used to await the final recognition result when stopping global dictation.
    private var stopContinuation: CheckedContinuation<Void, Never>?
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    
    private var rolloverTimer: Timer?
    private var watchdogTimer: Timer?
    
    init() {
        let locale = UserDefaults.standard.string(forKey: "dictationLanguage") ?? "en-US"
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
        speechRecognizer?.supportsOnDeviceRecognition = true
    }
    
    /// The full transcript is accumulated + current session, with corrections applied.
    private var fullTranscript: String {
        let combined: String
        if accumulatedTranscript.isEmpty {
            combined = currentSessionText
        } else if currentSessionText.isEmpty {
            combined = accumulatedTranscript
        } else {
            combined = accumulatedTranscript + " " + currentSessionText
        }
        return corrections?.apply(to: combined) ?? combined
    }
    
    // MARK: - Global Dictation (Push-to-Talk)
    
    /// Start dictation for global FN key use (no UI transcript updates).
    func startGlobalDictation() {
        Task {
            await startRecordingInternal(updateTranscriptLive: false)
        }
    }
    
    /// Stop global dictation and return the final transcript.
    /// Waits for the speech recognizer to deliver its final result before returning.
    func stopGlobalDictation() async -> String {
        userRequestedStop = true
        
        // Stop the audio engine and signal end-of-audio, but DON'T cancel the task yet.
        // Let the recognizer finish processing the buffered audio.
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        
        // Wait for the recognition task to deliver its final result.
        // The callback in startRecognitionTask will resume this continuation.
        await withCheckedContinuation { continuation in
            self.stopContinuation = continuation
            
            // Safety timeout — if the recognizer doesn't respond in 2 seconds, proceed anyway.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let cont = self.stopContinuation {
                    self.stopContinuation = nil
                    self.commitCurrentSession()
                    cont.resume()
                }
            }
        }
        
        // Clean up
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        return fullTranscript
    }
    
    // MARK: - Standard Recording
    
    func toggleRecording() {
        if isRecording {
            userRequestedStop = true
            stopAudioAndRecognition()
            isRecording = false
            transcript = fullTranscript
        } else {
            Task {
                await startRecordingInternal(updateTranscriptLive: true)
            }
        }
    }
    
    private func startRecordingInternal(updateTranscriptLive: Bool) async {
        // Guard against double-start
        if isRecording {
            return
        }
        
        // Fully clean up any prior session first
        forceCleanup()
        
        errorMessage = nil
        transcript = ""
        accumulatedTranscript = ""
        currentSessionText = ""
        userRequestedStop = false
        
        // Fast path for authorization to avoid async bounce when already authorized
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            let authStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            
            guard authStatus == .authorized else {
                errorMessage = "Speech recognition not authorized. Enable it in System Settings → Privacy & Security → Speech Recognition."
                return
            }
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "On-device speech recognition is not available on this device."
            return
        }
        
        // Setup audio pipeline:
        // 1. Remove old taps and PREPARE engine so hardware is initialized
        // 2. Install the tap via startRecognitionTask
        // 3. START engine so its very first audio buffers are caught by the tap
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0) // Remove any stale tap from a crashed previous session
        audioEngine.prepare()
        
        // Now set up the recognition request + tap atomically.
        startRecognitionTask(updateTranscriptLive: updateTranscriptLive)
        
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            forceCleanup() // Ensure tap is removed if start fails
            return
        }
    }
    
    /// Starts (or restarts) the recognition task.
    /// This is the ONLY place where the audio tap is installed — never install taps elsewhere.
    /// The request is created first, then the tap, so no audio buffers are lost.
    private func startRecognitionTask(updateTranscriptLive: Bool) {
        guard let speechRecognizer = speechRecognizer else { return }
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // 1. Create the recognition request FIRST
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.shouldReportPartialResults = true
        
        currentSessionText = ""
        
        // 2. Start the recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let result = result {
                    // We got speech! Cancel the watchdog timer
                    self.watchdogTimer?.invalidate()
                    
                    self.currentSessionText = result.bestTranscription.formattedString
                    
                    if updateTranscriptLive {
                        self.transcript = self.fullTranscript
                    }
                    
                    if result.isFinal {
                        self.commitCurrentSession()
                        if let cont = self.stopContinuation {
                            self.stopContinuation = nil
                            cont.resume()
                        }
                    }
                }
                
                if let error = error {
                    self.commitCurrentSession()
                    
                    if let cont = self.stopContinuation {
                        self.stopContinuation = nil
                        cont.resume()
                        return
                    }
                    
                    let nsError = error as NSError
                    let isCancellation = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216
                    
                    if !isCancellation && !self.userRequestedStop {
                        self.startRecognitionTask(updateTranscriptLive: updateTranscriptLive)
                    }
                }
            }
        }
        
        // 3. Install the audio tap AFTER the request exists (so buffers go to a live request)
        //    Always remove first to prevent nullptr == Tap() Core Audio crash.
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // 4. Schedule the 45s rollover timer to bypass the ~60s Apple limit
        rolloverTimer?.invalidate()
        rolloverTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performRollover(updateTranscriptLive: updateTranscriptLive)
            }
        }
        
        // 5. Schedule a 3s watchdog timer. If we haven't seen *any* text by then,
        // the SFSpeechRecognizer has likely deadlocked after inactivity. Reboot it.
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRecording, self.currentSessionText.isEmpty else { return }
                print("[SpeechRecognizer] Watchdog fired: No speech detected in 3.5s. Rebooting recognizer...")
                self.performRollover(updateTranscriptLive: updateTranscriptLive)
            }
        }
    }
    
    /// Bypasses the ~60s recognizer limit by cleanly ending the current session 
    /// and immediately starting a new one without stopping the audio engine.
    private func performRollover(updateTranscriptLive: Bool) {
        guard isRecording else { return }
        rolloverTimer?.invalidate()
        watchdogTimer?.invalidate()
        
        let oldRequest = recognitionRequest
        let oldTask = recognitionTask
        
        // Finalize the current text chunks
        commitCurrentSession()
        
        // End the audio on the old request so it flushes
        oldRequest?.endAudio()
        
        // Immediately start a new task catching the stream
        startRecognitionTask(updateTranscriptLive: updateTranscriptLive)
        
        // Give the old task 1 second to parse the flushed audio, then cancel
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            oldTask?.cancel()
        }
    }
    
    /// Saves current session text into the accumulated transcript.
    private func commitCurrentSession() {
        if !currentSessionText.isEmpty {
            if accumulatedTranscript.isEmpty {
                accumulatedTranscript = currentSessionText
            } else {
                accumulatedTranscript += " " + currentSessionText
            }
            currentSessionText = ""
        }
    }
    
    /// Stops the audio engine and cancels recognition.
    private func stopAudioAndRecognition() {
        forceCleanup()
        commitCurrentSession()
    }
    
    /// Hard cleanup of all audio and recognition resources.
    private func forceCleanup() {
        rolloverTimer?.invalidate()
        rolloverTimer = nil
        
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset() // Critical for waking up CoreAudio after sleep/inactivity
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

// MARK: - Rewrite Engine

@MainActor
final class RewriteEngine: ObservableObject {
    @Published var rewrittenText: String = ""
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String? = nil
    
    var corrections: CorrectionsDictionary?
    
    func rewrite(text: String, prompt: String) async -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        isProcessing = true
        errorMessage = nil
        
        let fullPrompt = """
        You are rewriting the following text according to the user's instruction.
        \(corrections?.contextBlock() ?? "")
        INSTRUCTION: \(prompt)
        
        OUTPUT RULES:
        - Return ONLY the rewritten text
        - No explanations, no labels, no preamble
        - Do not wrap in quotes
        - Start directly with the rewritten content
        
        TEXT:
        \(text)
        """
        
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: fullPrompt)
            let result = response.content
            rewrittenText = result
            isProcessing = false
            return result
        } catch {
            errorMessage = "Rewrite failed: \(error.localizedDescription)"
            isProcessing = false
            return nil
        }
    }
}
