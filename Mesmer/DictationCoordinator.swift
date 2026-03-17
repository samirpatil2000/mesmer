import Foundation
import Speech
import AVFoundation

/// Coordinates the FN-key-triggered dictation flow:
/// Hold FN → mic activates + pill shows → release FN → transcribe → inject text → log history.
@MainActor
final class DictationCoordinator {
    
    let speechRecognizer: SpeechRecognizer
    let historyManager: HistoryManager
    let pillWindow: DictationPillWindow
    let toastWindow: DictationToastWindow
    
    /// The PID of the app that was focused when dictation started.
    /// Saved so we can track whether focus changed while dictating.
    private var targetAppPID: pid_t?
    private var targetAppName: String?
    private var draftHistoryID: UUID?
    
    init(speechRecognizer: SpeechRecognizer, historyManager: HistoryManager) {
        self.speechRecognizer = speechRecognizer
        self.historyManager = historyManager
        self.pillWindow = DictationPillWindow()
        self.toastWindow = DictationToastWindow()
        self.speechRecognizer.onChunkCommitted = { [weak self] accumulatedText in
            guard let self, let draftHistoryID = self.draftHistoryID else { return }
            self.historyManager.updateDictationRecord(
                id: draftHistoryID,
                text: accumulatedText,
                injectionStatus: .failed,
                wasFocusChanged: false,
                targetAppName: self.targetAppName
            )
        }
    }
    
    var isReady: Bool { speechRecognizer.isReady }
    
    /// Called when FN key is pressed down.
    func beginDictation() async {
        // Readiness Gate
        switch speechRecognizer.readiness {
        case .unknown, .unavailable:
            await speechRecognizer.warmUp()
            if !speechRecognizer.isReady {
                toastWindow.show(message: "Preparing dictation… please try again.")
                return
            }
        case .checking:
            toastWindow.show(message: "Speech model is loading…")
            return
        case .ready:
            break
        }
        
        // Save the target app BEFORE we do anything
        targetAppPID = AccessibilityService.frontmostAppPID()
        targetAppName = AccessibilityService.frontmostAppName()
        draftHistoryID = historyManager.logDictation(
            text: "",
            targetAppName: targetAppName,
            injectionStatus: .failed
        )
        
        pillWindow.showPill()
        speechRecognizer.startGlobalDictation()
    }
    
    /// Called when FN key is released.
    func endDictation() async {
        pillWindow.hidePill()
        defer {
            targetAppPID = nil
            targetAppName = nil
            draftHistoryID = nil
        }

        let transcript = await speechRecognizer.stopGlobalDictation()
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let historyID = draftHistoryID ?? historyManager.logDictation(
            text: trimmedTranscript,
            targetAppName: targetAppName,
            injectionStatus: .failed
        )
        
        historyManager.updateDictationRecord(
            id: historyID,
            text: trimmedTranscript,
            injectionStatus: .failed,
            wasFocusChanged: false,
            targetAppName: targetAppName
        )
        
        guard !trimmedTranscript.isEmpty else { return }

        let endPID = AccessibilityService.frontmostAppPID()
        let endAppName = AccessibilityService.frontmostAppName()
        let wasFocusChanged = targetAppPID != endPID
        let injectionTargetAppName = endAppName ?? targetAppName

        let injectionResult = AccessibilityService.injectText(trimmedTranscript)
        switch injectionResult {
        case .success, .uncertain:
            historyManager.updateDictationRecord(
                id: historyID,
                injectionStatus: .injected,
                wasFocusChanged: wasFocusChanged,
                targetAppName: injectionTargetAppName
            )
        case .failed(let reason):
            AccessibilityService.copyTextToClipboard(trimmedTranscript)
            historyManager.updateDictationRecord(
                id: historyID,
                injectionStatus: .clipboard_only,
                wasFocusChanged: wasFocusChanged,
                targetAppName: injectionTargetAppName
            )
            toastWindow.show(message: toastMessage(for: reason))
        }
    }

    private func toastMessage(for reason: InjectionFailureReason) -> String {
        switch reason {
        case .noFocusedEditableElement:
            return "No text field. Saved transcript."
        case .secureTextField:
            return "Secure field detected. Saved transcript."
        case .accessibilityPermissionDenied, .pasteSimulationUnavailable:
            return "Couldn't insert. Copied to clipboard."
        }
    }
}
