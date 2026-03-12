import SwiftUI

struct SettingsView: View {
    @AppStorage("fnDictationEnabled") private var fnDictationEnabled = true
    @AppStorage("floatingToolbarEnabled") private var floatingToolbarEnabled = true
    @AppStorage("dictationLanguage") private var dictationLanguage = "en-US"
    
    var historyManager: HistoryManager
    var onFNToggleChanged: ((Bool) -> Void)?
    var onToolbarToggleChanged: ((Bool) -> Void)?
    
    @State private var showClearConfirmation = false
    
    @State private var shakeOffset: CGFloat = 0
    
    // ... supported languages ...
    private let supportedLanguages: [(code: String, name: String)] = [
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("en-AU", "English (Australia)"),
        ("en-IN", "English (India)"),
        ("es-ES", "Spanish"),
        ("fr-FR", "French"),
        ("de-DE", "German"),
        ("it-IT", "Italian"),
        ("pt-BR", "Portuguese (Brazil)"),
        ("ja-JP", "Japanese"),
        ("ko-KR", "Korean"),
        ("zh-CN", "Chinese (Simplified)"),
        ("hi-IN", "Hindi"),
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                
                // MARK: - Features Section
                
                SectionHeader(title: "FEATURES")
                    .padding(.top, 24)
                
                CardGroup {
                    SettingsRow(
                        icon: "keyboard",
                        iconColor: Color.blue,
                        title: "FN Key Dictation",
                        subtitle: "Hold the FN key anywhere to dictate"
                    ) {
                        Toggle("", isOn: $fnDictationEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: fnDictationEnabled) { _, newValue in
                                onFNToggleChanged?(newValue)
                            }
                    }
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.leading, 56)
                    
                    SettingsRow(
                        icon: "text.cursor",
                        iconColor: Color.blue,
                        title: "Floating Toolbar",
                        subtitle: "Show rewrite options on text selection"
                    ) {
                        Toggle("", isOn: $floatingToolbarEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: floatingToolbarEnabled) { _, newValue in
                                onToolbarToggleChanged?(newValue)
                            }
                    }
                }
                
                // MARK: - Language Section
                
                SectionHeader(title: "LANGUAGE")
                    .padding(.top, 24)
                
                CardGroup {
                    SettingsRow(
                        icon: "globe",
                        iconColor: Color.green,
                        title: "Dictation Language",
                        subtitle: "Language for speech recognition"
                    ) {
                        Picker("", selection: $dictationLanguage) {
                            ForEach(supportedLanguages, id: \.code) { lang in
                                Text(lang.name).tag(lang.code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }
                
                // MARK: - Accessibility Section
                
                SectionHeader(title: "PERMISSIONS")
                    .padding(.top, 24)
                
                CardGroup {
                    SettingsRow(
                        icon: "hand.raised.fill",
                        iconColor: Color.orange,
                        title: "Accessibility",
                        subtitle: AccessibilityService.isAccessibilityEnabled()
                            ? "Granted — global features active"
                            : "Required for text selection and dictation injection"
                    ) {
                        HStack(spacing: 8) {
                            if AccessibilityService.isAccessibilityEnabled() {
                                Image(systemName: "lock.open.fill")
                                    .foregroundColor(.green)
                            } else {
                                Button("Grant Access") {
                                    AccessibilityService.requestAccessibilityPermission()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.accentColor)
                                
                                Image(systemName: "lock.fill")
                                    .foregroundColor(Color(hex: "#8E8E93"))
                            }
                        }
                    }
                }
                
                // MARK: - Data Section
                
                SectionHeader(title: "DATA")
                    .padding(.top, 24)
                
                CardGroup {
                    SettingsRow(
                        icon: "trash.fill",
                        iconColor: Color.red,
                        title: "Clear All History",
                        subtitle: "\(historyManager.entries.count) entries stored locally"
                    ) {
                        Button("Clear") {
                            if historyManager.entries.isEmpty {
                                withAnimation(.spring(response: 0.1, dampingFraction: 0.2)) {
                                    shakeOffset = 5
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.spring(response: 0.1, dampingFraction: 0.2)) {
                                        shakeOffset = 0
                                    }
                                }
                            } else {
                                showClearConfirmation = true
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "#FF453A"))
                    }
                }
                .modifier(ShakeEffect(animatableData: shakeOffset))
                
                // MARK: - About
                
                VStack(spacing: 0) {
                    Text("Local Whisper · On-device · Private")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.18))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#0E0E0E"))
        .alert("Clear All History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                historyManager.clearAll()
            }
        } message: {
            Text("This will permanently delete all dictation and rewrite history. This cannot be undone.")
        }
    }
}

// MARK: - Card Group Layout

private struct CardGroup<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(hex: "#1C1C1E"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }
}

// MARK: - Shake Animation

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: -30 * sin(animatableData * .pi * 3), y: 0))
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.30))
            .textCase(.uppercase)
            .tracking(1.0)
            .padding(.horizontal, 40) // 24 + 16 inset
            .padding(.bottom, 6)
    }
}

// MARK: - Settings Row

private struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.90))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.38))
            }
            
            Spacer()
            
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
