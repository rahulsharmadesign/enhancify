import AppKit
import KeyboardShortcuts
import os.log

private let logger = Logger(subsystem: "com.rahul.enhancify", category: "coordinator")

@MainActor
final class AppCoordinator {
    let appState = AppState()
    lazy var panelController = PanelController(appState: appState)
    lazy var engine = PanelEngine(appState: appState) { [weak self] in
        self?.dismiss()
    }
    var onboardingWindow: OnboardingWindowController?
    var dashboardWindow: DashboardWindowController?
    var openingPanelAfterGetStarted = false

    /// Where the next transcript should land. Dictation drives two different
    /// fields — the instruction, and the text being worked on — and the
    /// recogniser has no idea which, so the coordinator remembers.
    enum DictationDestination {
        case instruction
        case sourceText
    }
    var dictationDestination: DictationDestination = .instruction

    lazy var pushToTalk = PushToTalkMonitor(
        fieldHasText: { [weak self] in
            !(self?.appState.describeInstruction.isEmpty ?? true)
        },
        onPress: { [weak self] in self?.beginPushToTalk() },
        onRelease: { DictationService.shared.stop() },
        onEscape: { [weak self] in self?.dismiss() }
    )

    func start() {
        logger.notice("start() called; registering hotkey")
        engine.onStreamingStarted = { [weak self] in
            self?.panelController.streamingDidStart()
        }
        engine.onStreamingEnded = { [weak self] in
            self?.panelController.streamingDidEnd()
        }
        KeyboardShortcuts.onKeyDown(for: .invokeEnhancify) { [weak self] in
            logger.notice("hotkey fired")
            self?.handleInvokeHotkey()
        }
        KeyboardShortcuts.onKeyDown(for: .dictateToEnhancify) { [weak self] in
            logger.notice("dictate hotkey fired")
            self?.invokeDictation()
        }
        let invoke = KeyboardShortcuts.getShortcut(for: .invokeEnhancify)?.description ?? "nil"
        logger.notice("invoke shortcut bound = \(invoke, privacy: .public)")

        engine.onRequestDictationPermission = { [weak self] in
            self?.showDashboard(route: .permissions)
        }
        engine.onRequestProviderSetup = { [weak self] preferLocal in
            if preferLocal {
                // "Use a local model": the zero-install one when this Mac can
                // answer, otherwise Ollama.
                SettingsStore.shared.selectProvider(
                    AppleModelState.isConfigured ? .apple : .ollama
                )
            }
            self?.showDashboard(route: .models)
        }
        engine.onOpenSettings = { [weak self] in
            // The requested order: the panel goes away first, then Settings
            // appears. dismiss() also disarms the mic and cancels any run.
            self?.dismiss()
            self?.showDashboard(route: .general)
        }
        DictationService.shared.onText = { [weak self] text in
            self?.applyDictated(text)
        }
        // Escape while the panel is up. The dictate shortcut is global so it
        // can open the panel and start listening from any app.

        let trusted = Permissions.isAccessibilityTrusted()
        logger.notice("initial accessibility trusted = \(trusted)")
        if !SettingsStore.shared.hasCompletedGetStarted {
            showOnboarding()
        } else {
            checkPostUpdateTrust()
        }

        // No warm-up here: with launch at login that loaded a multi-GB local
        // model into memory before the user asked for anything. The hotkey
        // warms the model instead, overlapping the load with text capture.
        AppUpdateService.shared.check()
    }

    /// Fire-and-forget pre-load of the model the next invocation will most
    /// likely need; a no-op for remote providers. Warms exactly one model —
    /// warming both roles would make the server evict and swap weights.
    func warmUpProvider() {
        let provider = ProviderRegistry.activeProvider()
        let role = EnhancementAction.action(withID: appState.selectedActionID)?.role ?? .enhance
        Task.detached(priority: .utility) {
            await provider.warmUp(role: role)
        }
    }

    func handleInvokeHotkey() {
        if onboardingWindow?.isPresented == true {
            openPanelAfterGetStarted()
            return
        }
        invoke()
    }

    func invoke() {
        if !SettingsStore.shared.hasCompletedGetStarted {
            showOnboarding()
            return
        }

        let trusted = Permissions.isAccessibilityTrusted()
        logger.notice("invoke() accessibility trusted = \(trusted)")
        if !trusted {
            Permissions.requestAccessibilityIfNeeded()
            presentEmptySelectionNotice()
            return
        }

        // Overlap the model load with text capture (up to 150 ms) so a model
        // idled out by Ollama's keep-alive is loading while we read the
        // selection.
        warmUpProvider()

        Task {
            // Pin the host app's focused element now, before our panel takes
            // key status; Replace targets this element later.
            let targetElement = TextCapture.focusedElement()
            let host = HostApp.identify(from: targetElement)
            let isEditableField = TextCapture.isEditableElement(targetElement)
            let preferClipboard = Self.prefersClipboardCapture(host: host, element: targetElement)
            let result = await TextCapture.captureSelection(preferClipboard: preferClipboard)
            switch result {
            case .text(let text, let rich):
                logger.notice("captured text, length = \(text.count)")
                presentPanel(
                    with: text,
                    rich: rich,
                    targetElement: targetElement,
                    host: host,
                    isEditableField: isEditableField
                )
            case .empty:
                logger.notice("capture returned empty")
                presentEmptySelectionNotice()
            }
        }
    }

    func enhanceClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            // Clipboard is empty or has no text — show an intent-ready panel
            // so the user gets feedback and can type or dictate text instead
            // of seeing nothing happen. Matches the hotkey behavior when there's
            // no selection.
            presentPanel(with: "", host: HostApp.identify(from: nil), source: "clipboard", waitsForInput: true)
            return
        }
        presentPanel(with: text, host: HostApp.identify(from: nil), source: "clipboard")
    }

    /// `waitsForInput`: dictation and an empty clipboard open to hear or
    /// read an instruction first, so nothing runs until asked.
    func presentPanel(
        with rawText: String,
        rich: RichSelection? = nil,
        targetElement: AXUIElement? = nil,
        host: HostApp.Info? = nil,
        source: String? = nil,
        waitsForInput: Bool = false,
        isEditableField: Bool = false
    ) {
        let (text, wasTruncated) = truncatedIfNeeded(rawText)
        // Use the element pinned *before* capture/panel focus — focused AX after
        // show is this app, which has no selection and used to mouse-anchor drift.
        let anchor = SelectionLocator.anchorPoint(for: targetElement)
        logger.notice("presenting panel at anchor = \(anchor.debugDescription)")
        appState.reset(withCapturedText: text)
        appState.capturedElement = targetElement
        // A truncated capture no longer matches its formatting line for line.
        appState.capturedRich = wasTruncated ? nil : rich
        appState.hostBundleID = host?.bundleID
        appState.hostAppName = host?.name
        appState.selectedTargetID = TargetRegistry.resolveTargetID(
            bundleID: host?.bundleID,
            appName: host?.name,
            perApp: SettingsStore.shared.lastTargetByApp,
            lastUsed: SettingsStore.shared.lastTargetID,
            known: Set(TargetRegistry.shared.profiles.map(\.id))
        )
        appState.truncationNotice = wasTruncated
        appState.isPanelVisible = true
        engine.resetForNewInvocation()

        let hasCapture = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        appState.selectAction(
            Self.initialActionID(
                host: host,
                hasCapture: hasCapture,
                isEditableField: isEditableField,
                // Only caller-set sources are real paste flows; an unset
                // source is the hotkey, even when its selection needed the
                // Cmd-C fallback.
                source: source ?? "hotkey"
            )
        )
        panelController.show(at: anchor, appState: appState, engine: engine)
        pushToTalk.arm()
        // An unconfigured install would only fail; the panel shows setup.
        let needsSetup = !SettingsStore.shared.isConfigured(SettingsStore.shared.activeProvider)
        if hasCapture, !waitsForInput, !needsSetup {
            engine.startIfNeeded(actionID: appState.selectedActionID)
        }
    }
}
