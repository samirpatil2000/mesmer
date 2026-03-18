import SwiftUI
import Speech
import AVFoundation
import FoundationModels

// MARK: - App Entry Point

@main
struct MesmerApp: App {
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
                },
                onStartupToggleChanged: { [weak appDelegate] enabled in
                    appDelegate?.setLaunchAtLoginEnabled(enabled)
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
    var onStartupToggleChanged: ((Bool) -> Void)?
    
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
                        onToolbarToggleChanged: onToolbarToggleChanged,
                        onStartupToggleChanged: onStartupToggleChanged
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
        case .settings: return "gearshape.fill"
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
        if let data = UserDefaults.standard.data(forKey: "Mesmer.Corrections"),
           let decoded = try? JSONDecoder().decode([CorrectionEntry].self, from: data) {
            self.entries = decoded
        }
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: "Mesmer.Corrections")
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
    enum ReadinessState: Equatable {
        case unknown
        case checking
        case ready
        case unavailable(String)
    }

    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String? = nil
    @Published var readiness: ReadinessState = .unknown
    
    var isReady: Bool {
        if case .ready = readiness { return true }
        return false
    }
    
    var corrections: CorrectionsDictionary?
    var onChunkCommitted: ((String) -> Void)?
    
    private var accumulatedTranscript: String = ""
    private var userRequestedStop: Bool = false
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var audioEngine = AVAudioEngine()
    private let audioFanout = AudioRequestFanout()
    private var sessions: [UUID: RecognitionSession] = [:]
    private var sessionOrder: [UUID] = []
    private var activeSessionID: UUID?
    private var startTask: Task<Void, Never>?
    private var inactivityTask: Task<Void, Never>?
    private var updateTranscriptLive: Bool = false
    private var pendingStop: PendingStop?
    private var isWarmingUp = false
    private var nextSessionSequence: Int = 0
    private var nextSequenceToCommit: Int = 0
    private var completedChunkTexts: [Int: String] = [:]
    
    private static let chunkOverlap: Duration = .seconds(2)
    private static let overlapLead: Duration = .seconds(13)
    
    private final class RecognitionSession {
        let id = UUID()
        let sequence: Int
        let request: SFSpeechAudioBufferRecognitionRequest
        var carriedText: String = ""
        var task: SFSpeechRecognitionTask?
        var latestText: String = ""
        var didEndAudio = false
        var didComplete = false
        var lifecycleTask: Task<Void, Never>?
        var watchdogTask: Task<Void, Never>?
        var lastResultAt: Date?
        
        init(sequence: Int, request: SFSpeechAudioBufferRecognitionRequest) {
            self.sequence = sequence
            self.request = request
        }
    }
    
    private final class PendingStop {
        let continuation: CheckedContinuation<Void, Never>
        var remainingSessionIDs: Set<UUID>
        
        init(continuation: CheckedContinuation<Void, Never>, remainingSessionIDs: Set<UUID>) {
            self.continuation = continuation
            self.remainingSessionIDs = remainingSessionIDs
        }
    }
    
    private final class AudioRequestFanout {
        private let queue = DispatchQueue(label: "Mesmer.SpeechRecognizer.AudioRequestFanout")
        private var requests: [UUID: SFSpeechAudioBufferRecognitionRequest] = [:]
        
        func add(_ request: SFSpeechAudioBufferRecognitionRequest, for id: UUID) {
            queue.sync {
                requests[id] = request
            }
        }
        
        func append(_ buffer: AVAudioPCMBuffer) {
            queue.sync {
                for request in requests.values {
                    request.append(buffer)
                }
            }
        }
        
        func endAudio(for id: UUID) {
            queue.sync {
                guard let request = requests.removeValue(forKey: id) else { return }
                request.endAudio()
            }
        }
        
        func removeAll() {
            queue.sync {
                let activeRequests = Array(requests.values)
                requests.removeAll()
                for request in activeRequests {
                    request.endAudio()
                }
            }
        }
    }
    
    init() {
        let locale = UserDefaults.standard.string(forKey: "dictationLanguage") ?? "en-US"
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
        speechRecognizer?.supportsOnDeviceRecognition = true
    }
    
    private var fullTranscript: String {
        let currentSessionText = liveSessionText
        let combined: String
        if accumulatedTranscript.isEmpty {
            combined = currentSessionText
        } else if currentSessionText.isEmpty {
            combined = accumulatedTranscript
        } else {
            combined = mergedTranscript(accumulatedTranscript, currentSessionText)
        }
        return corrections?.apply(to: combined) ?? combined
    }
    
    private var liveSessionText: String {
        for id in sessionOrder.reversed() {
            guard let session = sessions[id], !session.didComplete else { continue }
            let sessionText = sessionCombinedText(session)
            if !sessionText.isEmpty {
                return sessionText
            }
        }
        return ""
    }
    
    // MARK: - Global Dictation (Push-to-Talk)
    
    func startGlobalDictation() {
        beginRecording(updateTranscriptLive: false)
    }
    
    func stopGlobalDictation() async -> String {
        userRequestedStop = true
        
        if let startTask {
            await startTask.value
        }
        
        guard isRecording else {
            return corrections?.apply(to: accumulatedTranscript) ?? accumulatedTranscript
        }

        let outstandingSessionIDs = Set(
            sessionOrder.filter { id in
                guard let session = sessions[id] else { return false }
                return !session.didComplete
            }
        )
        
        for id in outstandingSessionIDs {
            finalizeSession(id)
        }
        
        if !outstandingSessionIDs.isEmpty {
            await withCheckedContinuation { continuation in
                let remainingSessionIDs = Set(
                    outstandingSessionIDs.filter { id in
                        !(sessions[id]?.didComplete ?? true)
                    }
                )
                
                if remainingSessionIDs.isEmpty {
                    continuation.resume()
                    return
                }
                
                let timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled, let self = self else { return }
                    for id in remainingSessionIDs {
                        if let session = self.sessions[id], !session.didComplete {
                            session.task?.cancel()
                            self.completeSession(id, finalText: nil)
                        }
                    }
                }
                
                pendingStop = PendingStop(
                    continuation: continuation,
                    remainingSessionIDs: remainingSessionIDs
                )
                
                // We don't cancel timeoutTask here because we actually want it to run until pendingStop resolves it!
                // Wait, if pendingStop resolves normally, resolvePendingStop can cancel it, BUT pendingStop doesn't hold the timeoutTask!
                // It's perfectly fine if timeoutTask fires after completion, because !session.didComplete will be false.
            }
        }
        
        finishStopping()
        isRecording = false
        return fullTranscript
    }
    
    // MARK: - Standard Recording
    
    func toggleRecording() {
        if isRecording || startTask != nil {
            userRequestedStop = true
            Task {
                let finalTranscript = await self.stopGlobalDictation()
                self.transcript = finalTranscript
            }
        } else {
            beginRecording(updateTranscriptLive: true)
        }
    }
    
    private func beginRecording(updateTranscriptLive: Bool) {
        guard !isRecording, startTask == nil else { return }
        userRequestedStop = false
        
        startTask = Task { [weak self] in
            guard let self else { return }
            await self.startRecordingInternal(updateTranscriptLive: updateTranscriptLive)
            self.startTask = nil
        }
    }
    
    private func startRecordingInternal(updateTranscriptLive: Bool) async {
        guard isReady else {
            errorMessage = "Speech model is not ready."
            return
        }
        
        // Guard against double-start
        if isRecording {
            return
        }
        
        forceCleanup()
        
        errorMessage = nil
        transcript = ""
        accumulatedTranscript = ""
        nextSessionSequence = 0
        nextSequenceToCommit = 0
        completedChunkTexts.removeAll()
        self.updateTranscriptLive = updateTranscriptLive
        
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
        
        guard !userRequestedStop else {
            forceCleanup()
            return
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "On-device speech recognition is not available on this device."
            return
        }
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        audioEngine.prepare()
        
        startRecognitionSession(using: speechRecognizer)
        installAudioTap(on: inputNode)
        
        do {
            try audioEngine.start()
            isRecording = true
            resetInactivityTimer()
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            forceCleanup()
            return
        }
    }
    
    private func startRecognitionSession(using speechRecognizer: SFSpeechRecognizer) {
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.addsPunctuation = true
        recognitionRequest.shouldReportPartialResults = true
        
        let session = RecognitionSession(
            sequence: nextSessionSequence,
            request: recognitionRequest
        )
        nextSessionSequence += 1
        sessions[session.id] = session
        sessionOrder.append(session.id)
        activeSessionID = session.id
        audioFanout.add(recognitionRequest, for: session.id)
        
        session.task = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionCallback(
                    for: session.id,
                    result: result,
                    error: error
                )
            }
        }
        
        scheduleSessionLifecycle(for: session.id)
        refreshLiveTranscriptIfNeeded()
    }
    
    private func installAudioTap(on inputNode: AVAudioInputNode) {
        inputNode.removeTap(onBus: 0)
        let outputFormat = inputNode.outputFormat(forBus: 0)
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        let tapFormat = preferredTapFormat(outputFormat: outputFormat, hardwareFormat: hardwareFormat)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [audioFanout] buffer, _ in
            audioFanout.append(buffer)
        }
    }
    
    private func scheduleSessionLifecycle(for sessionID: UUID) {
        sessions[sessionID]?.lifecycleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.overlapLead)
                self?.startSuccessorIfNeeded(after: sessionID)
                try await Task.sleep(for: Self.chunkOverlap)
                self?.finalizeSession(sessionID)
            } catch {
                return
            }
        }
    }
    
    private func startSuccessorIfNeeded(after sessionID: UUID) {
        guard isRecording, !userRequestedStop else { return }
        guard activeSessionID == sessionID else { return }
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else { return }
        startRecognitionSession(using: speechRecognizer)
    }
    
    private func finalizeSession(_ sessionID: UUID) {
        guard let session = sessions[sessionID], !session.didEndAudio else { return }
        session.didEndAudio = true
        audioFanout.endAudio(for: sessionID)
        
        session.watchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self = self else { return }
            if let activeSession = self.sessions[sessionID], !activeSession.didComplete {
                print("[SpeechRecognizer] Session \(sessionID) timed out. Forcing completion.")
                activeSession.task?.cancel()
                self.completeSession(sessionID, finalText: nil)
            }
        }
    }
    
    private func handleRecognitionCallback(
        for sessionID: UUID,
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        guard let session = sessions[sessionID], !session.didComplete else { return }
        
        if let result {
            let newText = normalizedTranscriptText(result.bestTranscription.formattedString)
            
            // Always call preserve BEFORE updating latestText and BEFORE any early
            // returns — this ensures a silence-reset (empty newText) still saves
            // whatever the session had previously recognized into carriedText.
            preserveUtteranceBoundaryIfNeeded(for: session, newText: newText)
            
            // Only update live state if the recognizer actually returned content.
            // An empty result means it reset after silence — don't overwrite latestText.
            if !newText.isEmpty {
                session.latestText = newText
                session.lastResultAt = Date()
                refreshLiveTranscriptIfNeeded()
                resetInactivityTimer()
            }
            
            if result.isFinal {
                let hasFinalContent = !newText.isEmpty
                if !userRequestedStop {
                    startSuccessorIfNeeded(after: sessionID)
                }
                completeSession(
                    sessionID,
                    finalText: hasFinalContent ? result.bestTranscription.formattedString : nil
                )
                return
            }
        }
        
        if let error {
            let nsError = error as NSError
            let isCancellation = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216
            if !isCancellation {
                print("[SpeechRecognizer] Session failed: \(error.localizedDescription)")
            }
            completeSession(sessionID, finalText: nil)
        }
    }
    
    private func completeSession(_ sessionID: UUID, finalText: String?) {
        guard let session = sessions[sessionID], !session.didComplete else { return }
        
        session.didComplete = true
        session.lifecycleTask?.cancel()
        session.watchdogTask?.cancel()
        session.task = nil
        audioFanout.endAudio(for: sessionID)
        
        let committedText = resolvedCommittedText(for: session, finalText: finalText)
        if committedText.isEmpty {
            print("[SpeechRecognizer] Session produced no final text; skipping chunk.")
        }
        completedChunkTexts[session.sequence] = committedText
        flushCompletedChunksInOrder()
        
        sessions.removeValue(forKey: sessionID)
        sessionOrder.removeAll { $0 == sessionID }
        activeSessionID = sessionOrder.reversed().first { id in
            guard let session = sessions[id] else { return false }
            return !session.didComplete
        }
        
        if !userRequestedStop {
            startReplacementSessionIfNeeded()
            resetInactivityTimer()
        }
        
        refreshLiveTranscriptIfNeeded()
        resolvePendingStop(for: sessionID)
    }
    
    private func resolvedCommittedText(
        for session: RecognitionSession,
        finalText: String?
    ) -> String {
        let trimmedFinalText = normalizedTranscriptText(finalText ?? "")
        if !trimmedFinalText.isEmpty {
            return mergedTranscript(session.carriedText, trimmedFinalText)
        }
        
        let trimmedPartialText = normalizedTranscriptText(session.latestText)
        if !trimmedPartialText.isEmpty {
            print("[SpeechRecognizer] Session ended without a final result; committing latest partial text.")
            return mergedTranscript(session.carriedText, trimmedPartialText)
        }
        
        return normalizedTranscriptText(session.carriedText)
    }
    
    private func startReplacementSessionIfNeeded() {
        guard isRecording, !userRequestedStop else { return }
        guard activeSessionID == nil else { return }
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else { return }
        startRecognitionSession(using: speechRecognizer)
    }
    
    private func commitChunk(_ chunkText: String) {
        accumulatedTranscript = mergedTranscript(accumulatedTranscript, chunkText)
        onChunkCommitted?(accumulatedTranscript)
    }
    
    private func flushCompletedChunksInOrder() {
        while let chunkText = completedChunkTexts.removeValue(forKey: nextSequenceToCommit) {
            commitChunk(chunkText)
            nextSequenceToCommit += 1
        }
    }
    
    private func resolvePendingStop(for sessionID: UUID) {
        guard let pendingStop else { return }
        pendingStop.remainingSessionIDs.remove(sessionID)
        guard pendingStop.remainingSessionIDs.isEmpty else { return }
        self.pendingStop = nil
        pendingStop.continuation.resume()
    }
    
    private func refreshLiveTranscriptIfNeeded() {
        guard updateTranscriptLive else { return }
        transcript = fullTranscript
    }
    
    private func preserveUtteranceBoundaryIfNeeded(
        for session: RecognitionSession,
        newText: String
    ) {
        let previousText = normalizedTranscriptText(session.latestText)
        guard !previousText.isEmpty else { return }
        
        // If the recognizer returned empty text (reset after silence), always carry
        // forward whatever we had — this is the primary cause of post-pause wipe-out.
        if newText.isEmpty {
            session.carriedText = mergedTranscript(session.carriedText, previousText)
            return
        }
        
        guard shouldCarryForward(
            previousText: previousText,
            newText: newText,
            lastResultAt: session.lastResultAt
        ) else { return }
        
        session.carriedText = mergedTranscript(session.carriedText, previousText)
    }
    
    private func shouldCarryForward(
        previousText: String,
        newText: String,
        lastResultAt: Date?
    ) -> Bool {
        if previousText == newText || newText.hasPrefix(previousText) || previousText.hasPrefix(newText) {
            return false
        }
        
        if overlapWordCount(between: previousText, and: newText) > 0 {
            return false
        }
        
        let previousWordCount = wordTokens(in: previousText).count
        guard previousWordCount >= 3 else { return false }
        
        guard let lastResultAt else { return false }
        return Date().timeIntervalSince(lastResultAt) >= 1.0
    }
    
    private func sessionCombinedText(_ session: RecognitionSession) -> String {
        mergedTranscript(session.carriedText, session.latestText)
    }
    
    private func mergedTranscript(_ base: String, _ addition: String) -> String {
        let normalizedBase = normalizedTranscriptText(base)
        let normalizedAddition = normalizedTranscriptText(addition)
        
        guard !normalizedBase.isEmpty else { return normalizedAddition }
        guard !normalizedAddition.isEmpty else { return normalizedBase }
        if normalizedBase == normalizedAddition {
            return normalizedBase
        }
        if normalizedAddition.hasPrefix(normalizedBase) {
            return normalizedAddition
        }
        if normalizedBase.hasPrefix(normalizedAddition) {
            return normalizedBase
        }
        
        let baseWords = wordTokens(in: normalizedBase)
        let additionWords = wordTokens(in: normalizedAddition)
        let maxOverlap = min(baseWords.count, additionWords.count, 12)
        
        if maxOverlap > 0 {
            for overlap in stride(from: maxOverlap, through: 1, by: -1) {
                let baseSlice = Array(baseWords.suffix(overlap))
                let additionSlice = Array(additionWords.prefix(overlap))
                if baseSlice.map(\.comparisonKey) == additionSlice.map(\.comparisonKey) {
                    let suffixWords = additionWords.dropFirst(overlap).map(\.original)
                    let suffixText = suffixWords.joined(separator: " ")
                    return suffixText.isEmpty ? normalizedBase : normalizedBase + " " + suffixText
                }
            }
        }
        
        return normalizedBase + " " + normalizedAddition
    }
    
    private func normalizedTranscriptText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func overlapWordCount(between lhs: String, and rhs: String) -> Int {
        let lhsWords = wordTokens(in: lhs)
        let rhsWords = wordTokens(in: rhs)
        let maxOverlap = min(lhsWords.count, rhsWords.count, 12)
        guard maxOverlap > 0 else { return 0 }
        
        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            let lhsSlice = Array(lhsWords.suffix(overlap))
            let rhsSlice = Array(rhsWords.prefix(overlap))
            if lhsSlice.map(\.comparisonKey) == rhsSlice.map(\.comparisonKey) {
                return overlap
            }
        }
        
        return 0
    }
    
    private func wordTokens(in text: String) -> [(original: String, comparisonKey: String)] {
        normalizedTranscriptText(text)
            .split(separator: " ")
            .map { word in
                let original = String(word)
                let comparisonKey = original
                    .lowercased()
                    .trimmingCharacters(in: .punctuationCharacters)
                return (original, comparisonKey)
            }
    }
    
    private func preferredTapFormat(
        outputFormat: AVAudioFormat,
        hardwareFormat: AVAudioFormat
    ) -> AVAudioFormat? {
        if outputFormat.sampleRate > 0,
           outputFormat.channelCount > 0,
           outputFormat.sampleRate == hardwareFormat.sampleRate {
            return outputFormat
        }
        
        if hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 {
            return hardwareFormat
        }
        
        return nil
    }
    
    private func finishStopping() {
        inactivityTask?.cancel()
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFanout.removeAll()
        pendingStop = nil
        activeSessionID = nil
        sessions.removeAll()
        sessionOrder.removeAll()
        nextSessionSequence = 0
        nextSequenceToCommit = 0
        completedChunkTexts.removeAll()
        updateTranscriptLive = false
        audioEngine = AVAudioEngine()
    }
    
    private func forceCleanup() {
        inactivityTask?.cancel()
        readiness = .unknown
        for session in sessions.values {
            session.lifecycleTask?.cancel()
            session.watchdogTask?.cancel()
            session.task?.cancel()
        }
        pendingStop = nil
        activeSessionID = nil
        sessions.removeAll()
        sessionOrder.removeAll()
        nextSessionSequence = 0
        nextSequenceToCommit = 0
        completedChunkTexts.removeAll()
        updateTranscriptLive = false
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFanout.removeAll()
        audioEngine = AVAudioEngine()
    }
    
    private func resetInactivityTimer() {
        inactivityTask?.cancel()
        guard isRecording, !userRequestedStop else { return }
        
        inactivityTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(28))
                guard let self = self, self.isRecording, !self.userRequestedStop else { return }
                
                if let activeID = self.activeSessionID {
                    self.finalizeSession(activeID)
                }
            } catch {
                // Cancelled
            }
        }
    }
    
    func warmUp() async {
        if case .ready = readiness { return }
        if case .unavailable = readiness { return }
        
        guard !isWarmingUp else { return }
        isWarmingUp = true
        defer { isWarmingUp = false }
        
        readiness = .checking
        
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard authStatus == .authorized else {
            readiness = .unavailable("Microphone/Speech authorization denied.")
            return
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            readiness = .unavailable("On-device speech recognition is not available.")
            return
        }
        
        // Dry-run probe to force model load
        let probeRequest = SFSpeechAudioBufferRecognitionRequest()
        probeRequest.requiresOnDeviceRecognition = true
        probeRequest.addsPunctuation = true
        let probeTask = speechRecognizer.recognitionTask(with: probeRequest) { _, _ in }
        probeRequest.endAudio()
        probeTask.cancel()
        
        readiness = .ready
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
