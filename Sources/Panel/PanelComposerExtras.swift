import SwiftUI

// Composer collapse, the footer hint, and the footer's icon button.

extension PanelView {
    /// The composer hides while there is a selection to work on: the result
    /// and its actions are the whole panel. It comes back when there is
    /// nothing selected (it is the input then), when you type or dictate, or
    /// on ⌘L / Refine.
    var composerCollapsed: Bool {
        hasCapturedText
            && appState.describeInstruction.isEmpty
            && !composerExpanded
            && !DictationService.shared.isRecording
    }

    /// One quiet line in the otherwise empty footer band, so the keyboard
    /// moves stay discoverable without a headline in the middle of the panel.
    var footerHint: String? {
        let other = appState.selectedActionID == EnhancementAction.grammarID ? "Enhance" : "Grammar"
        if composerCollapsed {
            return appState.acceptedText() != nil
                ? "Return replaces · Type to refine · Tab: \(other)"
                : "Type to refine · Tab switches to \(other)"
        }
        if idleIsCompact && showsIdlePlaceholderOnly {
            return "Return runs · Tab switches to \(other)"
        }
        return nil
    }

    func hintLine(_ text: String) -> some View {
        Text(text)
            .font(EnhancifyType.captionMedium)
            .foregroundStyle(EnhancifyColor.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, PanelMetrics.moduleInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }
}

/// Icon-only outcome control: copy, regenerate, refine. Plain glyph on the
/// slab — a glass disc here is a second lens.
struct OutcomeIconButton: View {
    let icon: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        EnhancifyIconButton(
            icon: icon,
            size: EnhancifyMetrics.iconSize,
            frameSize: EnhancifyMetrics.roundButtonSm,
            tint: tint ?? EnhancifyColor.textSecondary,
            help: help,
            action: action
        )
    }
}
