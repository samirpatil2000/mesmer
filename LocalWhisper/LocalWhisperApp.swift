import SwiftUI
import Speech
import AVFoundation
import FoundationModels

// MARK: - App Entry Point

@main
struct LocalWhisperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 680, height: 780)
    }
}

// MARK: - Enums

enum RewriteStyle: String, CaseIterable, Identifiable {
    case professional = "Professional"
    case casual = "Casual"
    case concise = "Concise"
    case formal = "Formal"
    
    var id: String { rawValue }
}

enum TranscriptionMode: String, CaseIterable, Identifiable {
    case realtime = "Real-time"
    case afterRecording = "After Recording"
    
    var id: String { rawValue }
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
            // Use regex for case-insensitive whole-word replacement if possible,
            // or simple replacingOccurrences. We'll use simple case-insensitive replace for speed.
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
    @Published var mode: TranscriptionMode = .realtime
    
    var corrections: CorrectionsDictionary?
    
    /// Text accumulated from previous recognition sessions within
    /// the same recording. Each time Apple's recognizer times out
    /// (~60s), we save what we have here and restart seamlessly.
    private var accumulatedTranscript: String = ""
    
    /// The partial text from the current recognition session only.
    private var currentSessionText: String = ""
    
    /// Whether the user intentionally stopped recording (vs. auto-restart).
    private var userRequestedStop: Bool = false
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    
    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
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
    
    func toggleRecording() {
        if isRecording {
            userRequestedStop = true
            stopAudioAndRecognition()
            isRecording = false
            
            // In "after recording" mode, reveal the full transcript now
            if mode == .afterRecording {
                transcript = fullTranscript
            }
        } else {
            Task {
                await startRecording()
            }
        }
    }
    
    private func startRecording() async {
        errorMessage = nil
        transcript = ""
        accumulatedTranscript = ""
        currentSessionText = ""
        userRequestedStop = false
        
        // Request speech recognition authorization
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard authStatus == .authorized else {
            errorMessage = "Speech recognition not authorized. Enable it in System Settings → Privacy & Security → Speech Recognition."
            return
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "On-device speech recognition is not available on this device."
            return
        }
        
        // Start audio engine (runs for the entire recording session)
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            return
        }
        
        // Start the first recognition session
        startRecognitionTask()
    }
    
    /// Starts (or restarts) just the recognition task — without
    /// touching the audio engine, which keeps running continuously.
    private func startRecognitionTask() {
        guard let speechRecognizer = speechRecognizer else { return }
        
        // Cancel any prior task cleanly
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Fresh request for this session
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.shouldReportPartialResults = true
        
        currentSessionText = ""
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let result = result {
                    self.currentSessionText = result.bestTranscription.formattedString
                    
                    // Push to transcript in real-time mode
                    if self.mode == .realtime {
                        self.transcript = self.fullTranscript
                    }
                    
                    // If this is a final result, commit it to accumulated
                    if result.isFinal {
                        self.commitCurrentSession()
                    }
                }
                
                if let error = error {
                    // Commit whatever we have so far from this session
                    self.commitCurrentSession()
                    
                    let nsError = error as NSError
                    let isCancellation = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216
                    
                    if !isCancellation && !self.userRequestedStop {
                        // Recognition timed out or hit a limit — auto-restart
                        self.startRecognitionTask()
                    }
                }
            }
        }
        
        // Re-install the audio tap to feed this new request
        // (the engine is still running, we just need to reconnect the tap)
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
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
    
    /// Stops the audio engine and cancels recognition. Does NOT
    /// update `isRecording` — the caller decides that.
    private func stopAudioAndRecognition() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        commitCurrentSession()
    }
}

// MARK: - Rewrite Engine

@MainActor
final class RewriteEngine: ObservableObject {
    @Published var rewrittenText: String = ""
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String? = nil
    
    var corrections: CorrectionsDictionary?
    
    func rewrite(transcript: String, style: RewriteStyle) async {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Nothing to rewrite. Record some speech first."
            return
        }
        
        isProcessing = true
        errorMessage = nil
        rewrittenText = ""
        
        let styleGuidance: String
        switch style {
        case .professional:
            styleGuidance = """
            STYLE: Professional
            - Use clear, confident business language
            - Structure with proper paragraphs if the content warrants it
            - Replace casual phrasing with precise, authoritative alternatives
            - Maintain a tone suitable for emails, reports, or presentations
            - Eliminate hedging language ("I think", "maybe", "kind of")
            """
        case .casual:
            styleGuidance = """
            STYLE: Casual
            - Keep a friendly, conversational but polished tone
            - Use natural contractions (don't, can't, it's)
            - Keep sentences short and punchy
            - It should sound like a smart person talking to a friend — relaxed but articulate
            - Remove filler words but keep the speaker's natural voice
            """
        case .concise:
            styleGuidance = """
            STYLE: Concise
            - Compress to the absolute minimum words needed
            - Remove every redundant word, phrase, and qualifier
            - Use bullet points if the content has multiple distinct ideas
            - Aim for maximum information density with zero fluff
            - Every sentence must earn its place
            """
        case .formal:
            styleGuidance = """
            STYLE: Formal
            - Use elevated, precise language appropriate for academic or legal contexts
            - Avoid contractions entirely
            - Use complete, well-constructed sentences with proper subordination
            - Maintain objectivity and measured tone throughout
            - Employ sophisticated vocabulary where it adds clarity, not complexity
            """
        }
        
        let prompt = """
        You are rewriting spoken-aloud text into clean written English.
        
        CRITICAL CONTEXT: The input below was captured via speech recognition. It will contain:
        - Filler words (um, uh, like, you know, so, basically, actually, right)
        - False starts and self-corrections ("I was going to — well actually I think")
        - Run-on thoughts with no punctuation
        - Repetitions and restated ideas
        - Informal or fragmented grammar
        - Thoughts that trail off or jump between topics
        \(corrections?.contextBlock() ?? "")
        STRUCTURED DATA HANDLING:
        - When the speaker dictates an email address, reconstruct it properly (e.g. "sameer s patil 7420 double 9 at gmail dot com" → use the closest match from the personal dictionary or format as an email).
        - When the speaker says a phone number, format as digits (e.g. "double 9" = 99, "triple 0" = 000).
        - When the speaker says a URL, reconstruct it (e.g. "github dot com slash something" → "github.com/something").
        
        YOUR JOB:
        1. Extract the actual meaning and intent behind the spoken words
        2. Remove ALL filler, repetition, false starts, and verbal noise
        3. Reconstruct the ideas into clean, well-punctuated, grammatically correct written English
        4. Preserve the speaker's original meaning — do not add ideas, opinions, or information that was not present
        5. If the speaker made the same point multiple ways, keep the strongest version only
        6. Apply the style guidelines below
        
        \(styleGuidance)
        
        OUTPUT RULES:
        - Return ONLY the rewritten text
        - No explanations, no labels, no preamble, no "Here is the rewritten text:"
        - Do not wrap in quotes
        - Start directly with the rewritten content
        
        SPOKEN TEXT:
        \(transcript)
        """
        
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            rewrittenText = response.content
        } catch {
            errorMessage = "Rewrite failed: \(error.localizedDescription)"
        }
        
        isProcessing = false
    }
}

// MARK: - Subviews

struct CorrectionsPopover: View {
    @ObservedObject var dictionary: CorrectionsDictionary
    @State private var newSpoken = ""
    @State private var newCorrected = ""
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Personal Corrections")
                .font(.system(size: 15, weight: .medium))
                .padding(.top, 16)
                .padding(.bottom, 8)
            
            Text("Teach Local Whisper how to transcribe specific names, terms, or email addresses.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            
            Divider()
            
            if dictionary.entries.isEmpty {
                VStack {
                    Spacer()
                    Text("No corrections yet.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: 150)
            } else {
                List {
                    ForEach(dictionary.entries) { entry in
                        HStack {
                            Text(entry.spoken)
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            Text(entry.corrected)
                                .foregroundColor(.primary)
                            Spacer()
                            Button(action: {
                                if let index = dictionary.entries.firstIndex(where: { $0.id == entry.id }) {
                                    dictionary.remove(at: IndexSet(integer: index))
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.system(size: 13))
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
                .frame(height: 150)
            }
            
            Divider()
            
            HStack(spacing: 8) {
                TextField("When I say...", text: $newSpoken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                
                TextField("Replace with...", text: $newCorrected)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                
                Button("Add") {
                    dictionary.add(spoken: newSpoken, corrected: newCorrected)
                    newSpoken = ""
                    newCorrected = ""
                }
                .disabled(newSpoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newCorrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 400)
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var dictionary = CorrectionsDictionary()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var rewriteEngine = RewriteEngine()
    @State private var selectedStyle: RewriteStyle = .professional
    @State private var showOutput: Bool = false
    @State private var copied: Bool = false
    @State private var showCorrections = false
    
    private let recordingRed = Color(red: 1.0, green: 0.231, blue: 0.188) // #FF3B30
    
    var body: some View {
        VStack(spacing: 0) {
            // App title area
            HStack {
                Spacer()
                
                VStack(spacing: 2) {
                    Text("Local Whisper")
                        .font(.system(size: 28, weight: .light, design: .default))
                        .foregroundColor(.primary)
                    
                    Text("On-device. Private. Instant.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 70) // roughly balance the trailing corrections button
                
                Spacer()
                
                Button(action: { showCorrections.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed")
                        Text("Dictionary")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 32)
                .popover(isPresented: $showCorrections) {
                    CorrectionsPopover(dictionary: dictionary)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 20)
            
            // MARK: Top Zone — Transcription
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                
                if speechRecognizer.transcript.isEmpty {
                    if speechRecognizer.isRecording && speechRecognizer.mode == .afterRecording {
                        // "After Recording" mode: show listening indicator
                        VStack(spacing: 8) {
                            Text("Listening…")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(Color(nsColor: .placeholderTextColor))
                            Text("Transcript will appear when you stop recording.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color(nsColor: .placeholderTextColor).opacity(0.7))
                        }
                        .padding(16)
                    } else {
                        Text("Start speaking…")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(Color(nsColor: .placeholderTextColor))
                            .padding(16)
                    }
                }
                
                ScrollView {
                    Text(speechRecognizer.transcript)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .textSelection(.enabled)
                }
            }
            .frame(minHeight: 180, maxHeight: .infinity)
            .padding(.horizontal, 32)
            
            // MARK: Middle Zone — Mode + Style Picker
            
            VStack(spacing: 10) {
                Divider()
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                
                // Transcription mode toggle
                HStack {
                    Text("Transcription")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Picker("Mode", selection: $speechRecognizer.mode) {
                        ForEach(TranscriptionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    .disabled(speechRecognizer.isRecording)
                }
                .padding(.horizontal, 32)
                
                // Style picker
                Picker("Style", selection: $selectedStyle) {
                    ForEach(RewriteStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            }
            
            // MARK: Bottom Zone — Buttons
            
            HStack(spacing: 16) {
                // Mic button
                Button(action: {
                    speechRecognizer.toggleRecording()
                }) {
                    ZStack {
                        // Pulsing red background when recording
                        if speechRecognizer.isRecording {
                            Circle()
                                .fill(recordingRed.opacity(0.2))
                                .frame(width: 52, height: 52)
                                .modifier(PulseModifier())
                        }
                        
                        Circle()
                            .fill(speechRecognizer.isRecording ? recordingRed : Color(nsColor: .controlColor))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(speechRecognizer.isRecording ? .white : .primary)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 56, height: 56)
                
                // Rewrite button
                Button(action: {
                    Task {
                        showOutput = false
                        await rewriteEngine.rewrite(
                            transcript: speechRecognizer.transcript,
                            style: selectedStyle
                        )
                        if rewriteEngine.errorMessage == nil {
                            withAnimation(.easeIn(duration: 0.3)) {
                                showOutput = true
                            }
                        } else {
                            showOutput = true
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        if rewriteEngine.isProcessing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                        }
                        Text("Rewrite")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.05, green: 0.05, blue: 0.2)) // Deep navy
                    )
                }
                .buttonStyle(.plain)
                .disabled(rewriteEngine.isProcessing || speechRecognizer.transcript.isEmpty)
                .opacity(speechRecognizer.transcript.isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 32)
            
            // Error messages
            if let error = speechRecognizer.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(recordingRed)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
            }
            
            // MARK: Output Card
            
            if showOutput {
                VStack(alignment: .leading, spacing: 0) {
                    if let error = rewriteEngine.errorMessage {
                        Text(error)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(recordingRed)
                            .padding(16)
                    } else {
                        ZStack(alignment: .topTrailing) {
                            ScrollView {
                                Text(rewriteEngine.rewrittenText)
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .padding(.trailing, 28)
                                    .textSelection(.enabled)
                            }
                            
                            // Copy button
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(rewriteEngine.rewrittenText, forType: .string)
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copied = false
                                }
                            }) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .frame(minHeight: 80, maxHeight: 200)
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .transition(.opacity)
            }
            
            Spacer(minLength: 24)
        }
        .frame(minWidth: 500, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            speechRecognizer.corrections = dictionary
            rewriteEngine.corrections = dictionary
        }
    }
}

// MARK: - Pulse Animation Modifier

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.0 : 0.6)
            .animation(
                .easeInOut(duration: 1.0)
                .repeatForever(autoreverses: false),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}
