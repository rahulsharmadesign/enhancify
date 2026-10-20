import AppKit
import Foundation

// What the user does with a result: replace, copy, or cancel.

extension PanelEngine {
    func replace(text: String) {
        guard appState.replacedFeedback == nil else { return }
        pendingReplaceText = text
        pendingReplaceTarget = appState.capturedElement
        pendingReplaceHostBundleID = appState.hostBundleID
        pendingReplaceRich = appState.capturedRich.flatMap { RichReplacement.payload(for: text, source: $0) }
        appState.replacedFeedback = OutcomeCopy.replaceToast(hostAppName: appState.hostAppName)
        replaceToastTask?.cancel()
        replaceToastTask = Task { [weak self] in
            do {
                // Short confirmation only: the panel dismisses when the toast
                // clears, so it must not hold the write.
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            await self?.completeReplace()
        }
    }

    /// Dismiss, then paste once the panel is gone so Cmd-V cannot hit the composer.
    func completeReplace() async {
        let text = pendingReplaceText
        let target = pendingReplaceTarget
        let hostBundleID = pendingReplaceHostBundleID
        let rich = pendingReplaceRich
        pendingReplaceText = nil
        pendingReplaceTarget = nil
        pendingReplaceHostBundleID = nil
        pendingReplaceRich = nil
        replaceToastTask = nil
        appState.replacedFeedback = nil
        guard let text else { return }
        onDismiss()
        // hide() fades then orders out. Cmd-V before that lands on the
        // panel's field editor. Wait until the window is gone, then paste.
        try? await Task.sleep(for: .milliseconds(180))
        await TextReplace.replaceSelection(with: text, target: target, hostBundleID: hostBundleID, rich: rich)
    }

    func copy(text: String) {
        guard appState.replacedFeedback == nil else { return }
        guard !appState.copiedFeedback else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appState.copiedFeedback = true
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            appState.copiedFeedback = false
            onDismiss()
        }
    }

    func cancel() {
        if appState.replacedFeedback != nil {
            replaceToastTask?.cancel()
            Task { await completeReplace() }
            return
        }
        onDismiss()
    }
}

/// Footer confirmation after Replace.
enum OutcomeCopy {
    static func replaceToast(hostAppName: String?) -> String {
        let trimmed = hostAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "Replaced in \(trimmed.isEmpty ? "Mac" : trimmed)"
    }
}
