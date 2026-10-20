import ApplicationServices
import Foundation
import Observation

enum ResultState: Equatable {
    case idle
    case loading
    /// The model is emitting a reasoning pass; no answer tokens yet. Distinct
    /// from .loading so a long think doesn't look like a hung request.
    case thinking
    case streaming(String)
    case done(String)
    case error(String)
}

@MainActor
@Observable
final class AppState {
    var isPanelVisible: Bool = false
    /// When non-nil, the result module scrolls inside this height and the
    /// window is at the 75% viewport cap. Nil = result sizes intrinsically.
    /// Owned by `PanelController` from layout measures — views must not write it.
    var panelResultScrollHeight: CGFloat? = nil

    var capturedText: String = ""
    /// The host app's focused AX element at capture time. Replace must target
    /// this element, not whatever is focused at replace time (our own panel
    /// holds key status by then).
    var capturedElement: AXUIElement?
    /// The selection's formatting (headings, lists, paragraph styles) when
    /// the host supplied it. Replace rebuilds the result with it.
    var capturedRich: RichSelection?
    /// Enhance or Grammar. Results are keyed by action id.
    var selectedActionID: String = EnhancementAction.enhanceID
    var results: [String: ResultState] = [:]
    /// Actions whose finished result is currently reloading (Regenerate after
    /// `.done`). The footer stays mounted while set so the window does not
    /// collapse and regrow on every refresh. Cleared the moment any terminal
    /// or idle state lands via `setResult`, and on dismiss / reset.
    var reloadingActions: Set<String> = []
    /// Text typed into the composer: the source with nothing selected, a
    /// refinement otherwise.
    var describeInstruction: String = ""
    /// Which AI environment an enhanced prompt is being written for.
    var selectedTargetID: String = TargetProfile.genericID
    /// The app the current capture came from, used to remember its target.
    var hostBundleID: String?
    var hostAppName: String?
    /// Changes on every invocation. The panel's NSHostingView is created once
    /// and reused, so SwiftUI would otherwise never rebuild the subtree —
    /// keying the root on this restores per-invocation onAppear/focus.
    private(set) var panelSessionID = UUID()
    var copiedFeedback: Bool = false
    /// Footer confirmation after Replace. Nil when idle.
    var replacedFeedback: String? = nil
    var truncationNotice: Bool = false
    /// Diff ops per completed action, computed off-main when that stream
    /// completes. A missing entry means still streaming or not computed yet.
    var diffs: [String: [DiffOp]] = [:]
    /// Grammar's rewrite style. Resets to Proofread on every open.
    var grammarStyle: GrammarStyle = .proofread
    /// Which provider produced the current error, per action. Lets the panel
    /// offer "Try with [other provider]" instead of the user opening Settings.
    var errorProviders: [String: ProviderKind] = [:]
    /// Actions whose error is a missing/unknown model, so the panel can offer
    /// Connect to model next to Retry.
    var errorNeedsModelSetup: Set<String> = []

    private var streamTasks: [String: Task<Void, Never>] = [:]

    func resultState(for actionID: String) -> ResultState {
        results[actionID] ?? .idle
    }

    func selectAction(_ actionID: String) {
        selectedActionID = actionID
    }

    func selectTarget(_ targetID: String) {
        selectedTargetID = targetID
        SettingsStore.shared.lastTargetID = targetID
        if let hostBundleID {
            SettingsStore.shared.lastTargetByApp[hostBundleID] = targetID
        }
    }

    func reset(withCapturedText text: String) {
        clearSession()
        // Only on reset, never on dismiss: regenerating during the fade-out
        // would rebuild the view hierarchy mid-animation.
        panelSessionID = UUID()
        panelResultScrollHeight = nil
        capturedText = text
        hostBundleID = nil
        hostAppName = nil
        copiedFeedback = false
    }

    func dismiss() {
        isPanelVisible = false
        clearSession()
        capturedText = ""
    }

    /// Everything that belongs to one panel open.
    private func clearSession() {
        for task in streamTasks.values { task.cancel() }
        streamTasks.removeAll()
        results.removeAll()
        reloadingActions.removeAll()
        capturedElement = nil
        capturedRich = nil
        describeInstruction = ""
        replacedFeedback = nil
        truncationNotice = false
        diffs.removeAll()
        errorProviders.removeAll()
        errorNeedsModelSetup.removeAll()
        grammarStyle = .proofread
    }

    func setResult(_ state: ResultState, for actionID: String) {
        results[actionID] = state
        switch state {
        case .done, .error, .idle:
            reloadingActions.remove(actionID)
        default:
            break
        }
    }

    /// The outcome strip (Replace, Copy, Regenerate) shows once a result is
    /// in, and stays — dimmed — while that result reloads, so Regenerate does
    /// not collapse the chrome and bounce the composer mid-refresh.
    func showsFooter(for actionID: String) -> Bool {
        if case .done = resultState(for: actionID) { return true }
        return reloadingActions.contains(actionID)
    }

    func registerStreamTask(_ task: Task<Void, Never>, for actionID: String) {
        streamTasks[actionID]?.cancel()
        streamTasks[actionID] = task
    }

    func hasStarted(_ actionID: String) -> Bool {
        results[actionID] != nil
    }

    /// Text Replace / Copy should send.
    func acceptedText(for actionID: String? = nil) -> String? {
        if case .done(let text) = resultState(for: actionID ?? selectedActionID) { return text }
        return nil
    }
}
