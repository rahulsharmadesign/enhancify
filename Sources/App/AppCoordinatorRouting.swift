import ApplicationServices
import Foundation

// Invoke routing: which tab an invoke lands on, and how the selection is read.
// Pure host/selection rules with no UI, split out of AppCoordinator.

extension AppCoordinator {
    /// Tab to select when the panel opens. First match wins.
    ///
    /// - No selection, clipboard, or dictation → Enhance: whatever is typed or
    ///   spoken becomes the rough idea to turn into a prompt.
    /// - Selection inside Cursor / VS Code / Claude / ChatGPT / Kimi → Enhance.
    /// - Selection in an editable field, or anywhere in a chat/mail app →
    ///   Grammar: that is your own writing. Chat apps are matched by bundle
    ///   because Electron clients (Slack, Discord) expose a thin AX tree.
    /// - Anything else (a webpage, notes, a PDF) → Enhance.
    static func initialActionID(
        host: HostApp.Info?,
        hasCapture: Bool,
        isEditableField: Bool = false,
        source: String? = nil
    ) -> String {
        guard hasCapture, source == nil || source == "hotkey",
              let bundleID = host?.bundleID.lowercased() else {
            return EnhancementAction.enhanceID
        }
        if TargetProfile.seededID(forBundleID: bundleID, name: host?.name) != nil {
            return EnhancementAction.enhanceID
        }
        if isEditableField || isCommunicationApp(bundleID) {
            return EnhancementAction.grammarID
        }
        return EnhancementAction.enhanceID
    }

    /// Whether to read the selection with a real Cmd-C before trying the
    /// Accessibility API. Electron / Chromium AI tools keep a lazily updated
    /// AX tree, so `kAXSelectedText` there can be an earlier selection. Rich
    /// text apps and browsers only hand over headings, lists, and paragraph
    /// styles on the pasteboard, which Replace needs to keep them.
    static func prefersClipboardCapture(host: HostApp.Info?, element: AXUIElement?) -> Bool {
        let electron = element.map { TextReplace.isElectronHelper($0) } ?? false
        return prefersClipboardCapture(host: host, isElectronHelper: electron)
    }

    /// Pure half of the rule, for tests.
    nonisolated static func prefersClipboardCapture(host: HostApp.Info?, isElectronHelper: Bool) -> Bool {
        if isElectronHelper { return true }
        guard let host else { return false }
        let bundleID = host.bundleID.lowercased()
        if richTextBundleIDs.contains(where: { bundleID.hasPrefix($0) }) { return true }
        return TargetProfile.seededID(forBundleID: host.bundleID, name: host.name) != nil
    }

    /// Apps whose selections carry formatting worth keeping.
    nonisolated static let richTextBundleIDs: [String] = [
        "com.apple.notes", "com.apple.textedit", "com.apple.iwork.", "com.apple.mail",
        "com.microsoft.word", "com.microsoft.outlook", "com.microsoft.onenote",
        "notion.id", "md.obsidian",
        "com.apple.safari", "com.google.chrome", "company.thebrowser.browser",
        "com.microsoft.edgemac", "com.brave.browser", "org.mozilla.firefox"
    ]

    private static let communicationBundlePrefixes: [String] = [
        "com.apple.mail", "com.apple.mobilesms", "com.tinyspeck",
        "com.microsoft.teams", "net.whatsapp", "ru.keepcoder.telegram",
        "org.telegram", "com.hnc.discord", "com.facebook", "com.linkedin",
        "com.reddit", "com.beeper"
    ]

    /// Chat, mail, and social apps where a selection is usually someone
    /// talking to you.
    static func isCommunicationApp(_ bundleID: String) -> Bool {
        communicationBundlePrefixes.contains { bundleID.hasPrefix($0) }
    }
}
