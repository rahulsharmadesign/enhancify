import AppKit
import KeyboardShortcuts
import SwiftUI

// Voice entry points, dictation, and the onboarding and dashboard windows.

extension AppCoordinator {
    /// After an in-app update the ad-hoc signature changes identity and the
    /// Accessibility grant silently stops applying. When the build changed
    /// since the last run and trust is gone, land on Permissions with the
    /// re-grant steps instead of failing silently at the next hotkey. Fires
    /// at most once per build: the current build is always recorded.
    func checkPostUpdateTrust() {
        let settings = SettingsStore.shared
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        defer { settings.lastRunBuild = build }
        guard Self.needsPostUpdateNudge(
            lastRunBuild: settings.lastRunBuild,
            currentBuild: build,
            isTrusted: Permissions.isAccessibilityTrusted()
        ) else { return }
        showDashboard(route: .permissions)
    }

    /// Pure decision table for the post-update nudge. A missing build on
    /// either side (first run, unreadable plist) never nudges — onboarding or
    /// the invoke path owns those cases.
    nonisolated static func needsPostUpdateNudge(
        lastRunBuild: String?,
        currentBuild: String?,
        isTrusted: Bool
    ) -> Bool {
        guard !isTrusted,
              let last = lastRunBuild, !last.isEmpty,
              let current = currentBuild, !current.isEmpty
        else { return false }
        return last != current
    }

    func invokeDictation() {
        if DictationService.shared.isRecording {
            DictationService.shared.stop()
            return
        }

        if !SettingsStore.shared.hasCompletedGetStarted {
            showOnboarding()
            return
        }
        if !Permissions.isAccessibilityTrusted() {
            Permissions.requestAccessibilityIfNeeded()
            presentEmptySelectionNotice()
            return
        }

        if appState.isPanelVisible {
            beginDictation()
            return
        }

        Task {
            let targetElement = TextCapture.focusedElement()
            let host = HostApp.identify(from: targetElement)
            let result = await TextCapture.captureSelection()
            var text = ""
            var rich: RichSelection?
            if case .text(let captured, let formatting) = result {
                text = captured
                rich = formatting
            }
            presentPanel(
                with: text,
                rich: rich,
                targetElement: targetElement,
                host: host,
                waitsForInput: true
            )
            beginDictation()
        }
    }

    /// Opens the panel and starts dictating.
    func dictateNewText() {
        invokeDictation()
    }

    /// No selection: open an intent-ready panel so the user can type or dictate
    /// instead of seeing a two-second error dismiss.
    func presentEmptySelectionNotice() {
        let targetElement = TextCapture.focusedElement()
        let host = HostApp.identify(from: targetElement)
        presentPanel(
            with: "",
            targetElement: targetElement,
            host: host,
            waitsForInput: true
        )
    }

    func truncatedIfNeeded(_ text: String) -> (String, Bool) {
        guard text.count > PanelEngine.maxCapturedLength else { return (text, false) }
        let truncated = String(text.prefix(PanelEngine.maxCapturedLength))
        return (truncated, true)
    }

    /// Routes a transcript to whichever field the dictation was started for.
    func applyDictated(_ text: String) {
        switch dictationDestination {
        case .instruction:
            appState.describeInstruction = text
        case .sourceText:
            appState.capturedText = text
        }
    }

    /// Start listening into the composer.
    func beginDictation() {
        dictationDestination = .instruction
        let service = DictationService.shared
        switch DictationService.intentForMicPress(
            isRecording: service.isRecording,
            availability: service.availability
        ) {
        case .stop:
            service.stop()
        case .requestPermissionThenStart:
            Task { await promptThenStartVoice() }
        case .start:
            startVoiceOrReport()
        case .openSettings:
            showDashboard(route: .permissions)
            startVoiceOrReport()
        }
    }

    private func promptThenStartVoice() async {
        await DictationService.shared.requestPermissions()
        startVoiceOrReport()
        if DictationService.shared.availability.isReady { return }
        if DictationService.intentForMicPress(
            isRecording: false,
            availability: DictationService.shared.availability
        ) == .openSettings {
            showDashboard(route: .permissions)
        }
    }

    private func startVoiceOrReport() {
        guard !DictationService.shared.start() else { return }
        if let reason = DictationService.shared.availability.message {
            appState.setResult(.error(reason), for: appState.selectedActionID)
        }
    }

    /// Toggle listening from the panel mic.
    func beginPushToTalk() {
        beginDictation()
    }

    func dismiss() {
        // Never leave the microphone live, or the key intercepted, because a
        // panel went away.
        pushToTalk.disarm()
        DictationService.shared.cancel()
        dictationDestination = .instruction
        panelController.hide()
        appState.dismiss()
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindowController { [weak self] in
                self?.openPanelAfterGetStarted()
            }
        }
        onboardingWindow?.show()
    }

    /// Closes Get Started and shows the panel. Used by the Start button
    /// and by the live shortcut while that window is key.
    func openPanelAfterGetStarted() {
        guard !openingPanelAfterGetStarted else { return }
        openingPanelAfterGetStarted = true
        onboardingWindow?.finish()
        presentPanel(with: "", waitsForInput: true)
        DispatchQueue.main.async { [weak self] in
            self?.openingPanelAfterGetStarted = false
        }
    }

    /// Opens the dashboard, creating it on first use so an install that never
    /// opens it pays nothing for it.
    func showDashboard(route: DashboardRoute? = nil) {
        if dashboardWindow == nil {
            dashboardWindow = DashboardWindowController()
        }
        dashboardWindow?.show(route: route)
    }
}
