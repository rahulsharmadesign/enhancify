import AppKit
import SwiftUI

// The bottom half: instruction field, send button, target and provider
// pickers, and the footer actions.

extension PanelView {
    // MARK: - Footer / composer

    var hasFinishedResult: Bool {
        if case .done = appState.resultState(for: appState.selectedActionID) { return true }
        return false
    }

    /// Outcome strip sits behind the composer and only appears once a result
    /// is in — and stays, dimmed, while that result reloads, so Regenerate
    /// does not collapse the chrome and bounce the composer mid-refresh.
    /// The slot is always `footerMinHeight`, so the strip appearing never
    /// resizes the window.
    var composerColumn: some View {
        VStack(spacing: 0) {
            footerSlot
            intentField
                .frame(maxWidth: .infinity)
                .glassModule(
                    radius: PanelMetrics.composerRadius,
                    focusRing: describeFieldFocused,
                    scrim: .well
                )
                .frame(maxWidth: .infinity)
                .clipped()
                .fixedSize(horizontal: false, vertical: true)
                // Collapsed to zero height, not removed: the text view stays
                // the panel's first responder, so Escape, ⌘↩ and Tab keep
                // working, and typing lands in it and expands it.
                .frame(height: composerCollapsed ? 0 : nil, alignment: .top)
                .clipped()
                .accessibilityHidden(composerCollapsed)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            toastFallbackOverlay
        }
        .animation(nil, value: hasFinishedResult)
        .animation(nil, value: appState.selectedActionID)
    }

    /// Keeps chrome height stable: the outcome strip once a result is in,
    /// otherwise a one-line keyboard hint.
    var footerSlot: some View {
        ZStack {
            if showsFooter {
                footer
                    .opacity(footerReloading ? 0.5 : 1)
            } else if let hint = footerHint, !toastVisible {
                hintLine(hint)
            }
        }
        .frame(height: PanelMetrics.footerMinHeight)
        .frame(maxWidth: .infinity)
    }

    /// "Replaced in …" never resizes the chrome. With the strip showing, the
    /// text sits inline while the icon row hides for the 0.8s confirmation
    /// (the panel dismisses when the toast clears); otherwise it floats over
    /// the composer, ignoring clicks.
    @ViewBuilder
    var toastFallbackOverlay: some View {
        Group {
            if toastVisible && !showsFooter {
                    toastText
                    .padding(.horizontal, EnhancifySpace.sm)
                    .padding(.vertical, EnhancifySpace.xxs)
                    .enhancifyOverlayCapsule()
                    .padding(.bottom, EnhancifySpace.xl)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: toastVisible)
    }

    @ViewBuilder
    var toastText: some View {
        if let replaced = appState.replacedFeedback {
            Text(replaced)
                .font(EnhancifyType.footnote)
                .foregroundStyle(EnhancifyColor.textSecondary)
                .lineLimit(1)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    var toastVisible: Bool {
        appState.replacedFeedback != nil
    }

    var showsFooter: Bool {
        appState.showsFooter(for: appState.selectedActionID)
    }

    /// A finished result currently reloading. Footer actions self-guard
    /// (copy/replace need `.done` text; `retry` refuses a live run), so
    /// dimming is the only treatment the strip needs.
    var footerReloading: Bool {
        showsFooter && !hasFinishedResult
    }

    var footer: some View {
        HStack(spacing: EnhancifySpace.xs) {
            footerPrimaryAction

            if !toastVisible {
                footerActions
            }

            Spacer(minLength: 0)

            if toastVisible {
                toastText
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, PanelMetrics.moduleInset)
        .frame(height: PanelMetrics.footerMinHeight, alignment: .center)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.15), value: toastVisible)
    }

    /// Write-back first and left-aligned. Clicks travel through
    /// `PanelHitCapsule`: window-drag swallows plain buttons here.
    var footerPrimaryAction: some View {
            PanelHitCapsule(
                help: primaryFooterHoverHelp,
                accessibilityLabel: primaryFooterTitle,
                showsHelpPill: true,
                // Leading element of the footer row: a centered pill hangs
                // past the panel's left inset and the hosting view crops it.
                helpAnchor: .leading
            ) {
                performReplace()
            } label: {
                ZStack {
                    EnhancifyGlassButton(
                        title: primaryFooterTitle,
                        secondary: true,
                        size: .compact,
                        leadingIcon: "replace"
                    ) {}
                    .opacity(appState.replacedFeedback != nil ? 0 : 1)
                    EnhancifyLoader.compact()
                        .frame(width: EnhancifyMetrics.roundButtonSm, height: EnhancifyMetrics.roundButtonSm)
                        .opacity(appState.replacedFeedback != nil ? 1 : 0)
                }
                .animation(.easeOut(duration: 0.15), value: appState.replacedFeedback != nil)
            }
    }

    /// Icon-only outcome row: Copy, Regenerate, and Refine while the
    /// composer is hidden. Clicks travel through `PanelHitCapsule`:
    /// window-drag swallows plain buttons here.
    @ViewBuilder
    var footerActions: some View {
        let actionID = appState.selectedActionID
        PanelHitCapsule(
            help: appState.copiedFeedback ? "Copied" : "Copy response",
            accessibilityLabel: appState.copiedFeedback ? "Copied" : "Copy",
            showsHelpPill: true
        ) {
            performCopy()
        } label: {
            OutcomeIconButton(
                icon: appState.copiedFeedback ? "check" : "copy",
                help: appState.copiedFeedback ? "Copied" : "Copy response",
                tint: appState.copiedFeedback ? EnhancifyColor.positive : nil
            ) {}
            .animation(.easeOut(duration: 0.15), value: appState.copiedFeedback)
        }
        PanelHitCapsule(
            help: "Regenerate",
            accessibilityLabel: "Regenerate",
            showsHelpPill: true
        ) {
            engine.retry(actionID: actionID)
        } label: {
            OutcomeIconButton(icon: "rotate-cw", help: "Regenerate") {}
        }
        if composerCollapsed {
            PanelHitCapsule(
                help: "Refine (⌘L, or just type)",
                accessibilityLabel: "Refine",
                showsHelpPill: true
            ) {
                composerExpanded = true
            } label: {
                OutcomeIconButton(icon: "message-square", help: "Refine (⌘L, or just type)") {}
            }
        }
    }

    var intentField: some View {
        VStack(alignment: .leading, spacing: EnhancifySpace.sm) {
            HStack(alignment: .top, spacing: EnhancifySpace.xs) {
                EnhancifyIcon(name: "sparkles", size: 16)
                .foregroundStyle(EnhancifyColor.textSecondary)
                ZStack(alignment: .topLeading) {
                    if appState.describeInstruction.isEmpty {
                        Text(composerPlaceholder)
                            .font(EnhancifyType.body)
                            .foregroundStyle(EnhancifyColor.textSecondary)
                            .lineLimit(1)
                    }
                    ComposerTextField(
                        text: $appState.describeInstruction,
                        isFocused: describeFieldFocused,
                        onSubmit: { handleComposerReturn() },
                        onTab: {
                            if case .handled = perform(resolveTabIntent()) { return true }
                            return false
                        },
                        onFocusChange: { describeFieldFocused = $0 }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .clipped()
                }
            }
            HStack(spacing: PanelMetrics.moduleInset) {
                if targetPickerVisible {
                    targetMenu
                } else {
                    providerMenu
                }
                // Mic and send ride the trailing edge; the target (Enhance)
                // or provider (Grammar) pill owns the leading edge.
                Spacer(minLength: 0)
                DictationButton(onNeedsPermission: { engine.requestDictationPermission() })
                sendButton
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, PanelMetrics.moduleInset)
        .padding(.top, PanelMetrics.moduleInset)
        .padding(.bottom, EnhancifySpace.xs)
        .frame(minHeight: PanelMetrics.composerMinHeight, alignment: .center)
        .frame(maxWidth: .infinity)
    }

    var composerPlaceholder: String {
        let hasCapture = !appState.capturedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return EnhancementAction.composerPlaceholder(
            actionID: appState.selectedActionID,
            hasCapture: hasCapture,
            targetName: targetRegistry.profile(withID: appState.selectedTargetID)?.name
        )
    }

    var canSubmitDescribe: Bool {
        return !appState.describeInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submitDescribe() {
        engine.runDescribe(instruction: appState.describeInstruction)
    }

    var targetPickerVisible: Bool {
        Prompts.targetApplies(actionID: appState.selectedActionID)
    }

    func selectTarget(_ targetID: String) {
        guard targetID != appState.selectedTargetID else { return }
        appState.selectTarget(targetID)
        let actionID = appState.selectedActionID
        appState.results.removeValue(forKey: actionID)
        engine.startIfNeeded(actionID: actionID)
    }

    func performReplace() {
        guard let text = appState.acceptedText() else { return }
        engine.replace(text: text)
    }

    func performCopy() {
        guard let text = appState.acceptedText() else { return }
        engine.copy(text: text)
    }
}
