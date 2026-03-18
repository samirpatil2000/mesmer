import Foundation
import FoundationModels

/// Coordinates the floating rewrite toolbar flow:
/// Detect selection → show toolbar → user picks style → rewrite → replace text → log history.
@MainActor
final class RewriteCoordinator {
    
    let historyManager: HistoryManager
    let personaManager: PersonaManager
    let toolbarWindow: RewriteToolbarWindow
    
    private var currentSelectedText: String?
    private var currentSelectionBounds: CGRect?
    private var isProcessing = false
    
    init(historyManager: HistoryManager, personaManager: PersonaManager) {
        self.historyManager = historyManager
        self.personaManager = personaManager
        self.toolbarWindow = RewriteToolbarWindow(personaManager: personaManager)
        
        toolbarWindow.onStyleSelected = { [weak self] personaID, name, prompt in
            guard let self else { return }
            Task { @MainActor in
                await self.performRewrite(personaID: personaID, styleName: name, prompt: prompt)
            }
        }
        
        toolbarWindow.onDismiss = { [weak self] in
            self?.currentSelectedText = nil
            self?.currentSelectionBounds = nil
        }
    }
    
    /// Called when text selection is detected.
    func showToolbar(selectedText: String, bounds: CGRect) {
        guard !isProcessing else { return }
        currentSelectedText = selectedText
        currentSelectionBounds = bounds
        toolbarWindow.showToolbar(at: bounds)
    }
    
    /// Called when selection is cleared.
    func hideToolbar() {
        guard !isProcessing else { return }
        toolbarWindow.hideToolbar()
        currentSelectedText = nil
        currentSelectionBounds = nil
    }
    
    /// Performs the rewrite operation.
    private func performRewrite(personaID: UUID, styleName: String, prompt: String) async {
        guard let selectedText = currentSelectedText, !selectedText.isEmpty else { return }
        guard !isProcessing else { return }
        
        isProcessing = true
        
        // Show loading state — pulse the active pill
        if let bounds = currentSelectionBounds {
            toolbarWindow.showToolbar(at: bounds, processing: true, activePersonaID: personaID)
        }
        
        let fullPrompt = """
        You are a writing assistant embedded in macOS. The user has selected the following text and chosen a rewrite style. Rewrite it according to the style. Return only the rewritten text. No explanations. No preamble. No quotation marks around the result.
        
        Style: \(prompt)
        
        Selected text:
        \(selectedText)
        """
        
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: fullPrompt)
            let result = response.content
            
            // Replace the selected text in-place via clipboard paste
            AccessibilityService.replaceSelectedText(result)
            
            // Log to history
            let action = personaManager.historyAction(for: personaID)
            
            historyManager.log(
                originalText: selectedText,
                action: action,
                styleName: styleName,
                resultText: result
            )
        } catch {
            print("[RewriteCoordinator] Rewrite failed: \(error)")
        }
        
        isProcessing = false
        toolbarWindow.hideToolbar()
        currentSelectedText = nil
        currentSelectionBounds = nil
    }
}
