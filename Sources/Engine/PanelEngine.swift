import AppKit
import Foundation
import os.log

let engineLogger = Logger(subsystem: "com.rahul.enhancify", category: "engine")

/// Orchestrates capture -> LLM streaming -> replace/copy for the floating panel.
/// UI-agnostic: PanelView drives it, AppState holds the state it produces.
@MainActor
final class PanelEngine {
    static let maxCapturedLength = 8000

    let appState: AppState
    let onDismiss: () -> Void
    /// Notified when no stream is in flight, so the panel may shrink to fit.
    var onStreamingEnded: (() -> Void)?
    /// Notified when a stream begins, so the panel only grows until it ends.
    var onStreamingStarted: (() -> Void)?

    /// Set by the coordinator to open the dashboard's Permissions screen when
    /// dictation is denied or unavailable.
    var onRequestDictationPermission: (() -> Void)?

    func requestDictationPermission() {
        onRequestDictationPermission?()
    }

    /// Opens Settings → Models. `preferLocal` switches to the zero-install
    /// local provider first (Apple on-device when ready, else Ollama).
    var onRequestProviderSetup: ((Bool) -> Void)?

    func requestProviderSetup(preferLocal: Bool) {
        onRequestProviderSetup?(preferLocal)
    }

    /// Opens Settings → General. The panel is dismissed first, so the widget
    /// never sits under the settings window.
    var onOpenSettings: (() -> Void)?

    func openSettings() {
        onOpenSettings?()
    }

    /// Grammar style row: re-run Grammar on the same text in the new style.
    /// With nothing captured yet the style just waits for typed text.
    func applyGrammarStyle(_ style: GrammarStyle) {
        guard style != appState.grammarStyle else { return }
        appState.grammarStyle = style
        guard !appState.capturedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        start(actionID: EnhancementAction.grammarID)
    }

    let powerActivity = PowerActivity()
    /// Regeneration count per action within the current invocation.
    var attempts: [String: Int] = [:]
    /// Silent quality re-runs (parse / paraphrase / unchanged). Capped at one
    /// per action per user-initiated start so a stubborn model cannot loop.
    var qualityRetries: [String: Int] = [:]

    /// Monotonic for the life of the process, never reset: a token that came
    /// round again could let a task cancelled in a previous invocation write
    /// into the current one.
    var generationCounter = 0
    /// The generation whose writes are still wanted, per action.
    var liveGeneration: [String: Int] = [:]
    /// Replace toast then paste. Cancelled if a new invocation starts before
    /// the write runs. Escape during the toast finishes the write immediately.
    var replaceToastTask: Task<Void, Never>?
    var pendingReplaceText: String?
    var pendingReplaceTarget: AXUIElement?
    /// The app the panel was invoked over, carried to the clipboard fallback
    /// so Replace can reactivate it when there is no captured AX element.
    var pendingReplaceHostBundleID: String?
    /// The result rebuilt with the selection's headings and lists, when the
    /// host supplied them and the result still lines up with the source.
    var pendingReplaceRich: RichReplacement.Payload?

    /// Called when a new panel session begins, so attempt numbering restarts.
    func resetForNewInvocation() {
        attempts.removeAll()
        qualityRetries.removeAll()
        // Nothing from the previous session is live any more. Clearing rather
        // than reassigning matters: an in-flight task holds a token that now
        // matches no entry, so it can no longer publish.
        liveGeneration.removeAll()
        replaceToastTask?.cancel()
        replaceToastTask = nil
        pendingReplaceText = nil
        pendingReplaceTarget = nil
        pendingReplaceHostBundleID = nil
        pendingReplaceRich = nil
    }

    func beginGeneration(for actionID: String) -> Int {
        generationCounter += 1
        liveGeneration[actionID] = generationCounter
        return generationCounter
    }

    func isLive(_ generation: Int, for actionID: String) -> Bool {
        liveGeneration[actionID] == generation
    }

    func canQualityRetry(for actionID: String) -> Bool {
        (qualityRetries[actionID] ?? 0) < 1
    }

    func markQualityRetry(for actionID: String) {
        qualityRetries[actionID, default: 0] += 1
    }

    /// Writes result state only while this generation is still the live one.
    ///
    /// A superseded stream ends with nothing accumulated, which is
    /// indistinguishable from a genuinely empty model response — without this
    /// guard it paints "empty response" over the run that replaced it.
    func publish(_ state: ResultState, for actionID: String, generation: Int) {
        guard isLive(generation, for: actionID) else { return }
        appState.setResult(state, for: actionID)
    }

    init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
    }

    func startIfNeeded(actionID: String) {
        guard !appState.hasStarted(actionID) else { return }
        start(actionID: actionID)
    }

    /// Regenerate after a successful result means "give me a different take":
    /// the previous output is passed so the model must diverge from it. Retry
    /// after an error is a plain re-attempt.
    ///
    /// While a stream is in flight the footer stays mounted (dimmed), and a
    /// tap there must not restart the run under itself.
    func retry(actionID: String) {
        switch appState.resultState(for: actionID) {
        case .loading, .thinking, .streaming:
            return
        case .done(let previous):
            appState.reloadingActions.insert(actionID)
            start(actionID: actionID, previousResult: previous)
        default:
            start(actionID: actionID)
        }
    }

    /// Return in the composer. With nothing selected, the typed text is the
    /// source document; with a selection, it refines the result.
    ///
    /// Both the text field's onSubmit and the panel's Return handler call
    /// this, so a keystroke can arrive twice; the in-flight guard stops the
    /// second call from cancelling the first stream.
    func runDescribe(instruction: String) {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let actionID = appState.selectedActionID
        switch appState.resultState(for: actionID) {
        case .loading, .thinking, .streaming:
            return
        default:
            break
        }
        let typedIsSource = appState.capturedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if typedIsSource {
            appState.capturedText = trimmed
        }
        // An empty instruction, not nil: nil falls back to the composer text,
        // which still holds the source until the deferred clear below.
        start(actionID: actionID, instruction: typedIsSource ? "" : trimmed)
        // The source is consumed: clear the field so it is ready for a
        // refinement. A refinement stays put for tweaking. Deferred to the
        // next runloop: this runs inside the composer's Return handler, and
        // writing the bound text mid-`insertNewline` races `textDidChange`
        // and resurrects the cleared string.
        if typedIsSource {
            Task { @MainActor [weak appState] in
                appState?.describeInstruction = ""
            }
        }
    }

    /// Coalesce UI publishes. Local models can emit 100+ chunks per second;
    /// re-laying-out the panel for each one heats the Mac for no visible gain.
    static let streamPublishInterval: Duration = .milliseconds(100)
}
