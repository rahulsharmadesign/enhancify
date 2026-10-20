import AppKit
import SwiftUI

// Footer and composer policy: the write-back action, busy state, and send.

extension PanelView {

    var primaryFooterTitle: String { "Replace" }

    /// Short hover pill for the primary footer action.
    var primaryFooterHoverHelp: String { "Replace selection (Return)" }

    var isPromptBusy: Bool {
        switch appState.resultState(for: appState.selectedActionID) {
        case .loading, .thinking, .streaming: return true
        default: return false
        }
    }

    var sendButton: some View {
        PanelHitCapsule(
            help: isPromptBusy ? "Working…" : "Run this intent",
            accessibilityLabel: isPromptBusy ? "Working…" : "Send"
        ) {
            submitIfReady()
        } label: {
            EnhancifyFilledCircleButton(
                icon: "arrow-up",
                enabled: canSubmitDescribe && !isPromptBusy,
                help: isPromptBusy ? "Working…" : "Run this intent"
            ) {}
        }
        .accessibilityHint("Send the instruction to Enhancify")
    }

    /// Return in the composer. The text view holds the keyboard even while
    /// the composer is collapsed, so this is where Return lands with a result
    /// on screen: it has to apply the same rules as the panel, or an empty
    /// composer swallows the key and Replace never happens.
    func handleComposerReturn() {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        perform(
            PanelKeyBinding.resolveReturn(
                modifiers: PanelKeyModifiers(flags: flags),
                canSubmit: canSubmitDescribe,
                hasAcceptableResult: appState.acceptedText() != nil
            )
        )
    }

    func submitIfReady() {
        guard canSubmitDescribe, !isPromptBusy else { return }
        submitDescribe()
    }
}

extension ProviderKind {
    var composerTitle: String {
        switch self {
        case .ollama: return "Ollama"
        case .anthropic: return "Anthropic"
        case .custom: return "API"
        case .apple: return "Apple"
        }
    }

    var composerIcon: String {
        switch self {
        case .ollama: return "cpu"
        case .anthropic: return "sparkle"
        case .custom: return "cloud"
        case .apple: return "memory"
        }
    }
}
