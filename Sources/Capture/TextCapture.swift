import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.rahul.enhancify", category: "capture")

enum CaptureResult {
    /// `rich` is the selection's formatting when the host put it on the
    /// pasteboard (a Cmd-C capture). Replace uses it to give each line back
    /// its heading level, list marker, and paragraph style.
    case text(String, rich: RichSelection? = nil)
    case empty
}

enum TextCapture {
    /// Reads the current text selection: first via the Accessibility API, then
    /// falling back to a simulated Cmd-C for apps that don't expose AX selection
    /// (Electron apps, some web views).
    ///
    /// `preferClipboard` flips the order for Electron / Chromium AI tools
    /// (Cursor, Claude, ChatGPT). Their AX tree updates lazily, so
    /// `kAXSelectedText` can hand back an earlier selection — Enhance then
    /// ran on old text and looked like it returned a previous result. A real
    /// Cmd-C always reflects what is selected now.
    static func captureSelection(preferClipboard: Bool = false) async -> CaptureResult {
        if preferClipboard, AXIsProcessTrusted(),
           let copied = await captureViaClipboard(), !copied.text.isEmpty {
            logger.notice("captured via clipboard (preferred for this host), length = \(copied.text.count), rich = \(copied.rich != nil)")
            return .text(copied.text, rich: copied.rich)
        }
        if let axText = focusedSelectedText(), !axText.isEmpty {
            logger.notice("captured via AX, length = \(axText.count)")
            return .text(axText)
        }
        guard AXIsProcessTrusted() else {
            logger.notice("AX capture empty and process is not trusted")
            return .empty
        }
        logger.notice("AX capture empty/unavailable, trying clipboard fallback")

        if let copied = await captureViaClipboard(), !copied.text.isEmpty {
            logger.notice("captured via clipboard fallback, length = \(copied.text.count), rich = \(copied.rich != nil)")
            return .text(copied.text, rich: copied.rich)
        }

        logger.notice("clipboard fallback also empty")
        return .empty
    }

    static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard result == .success, let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else {
            logger.notice("no focused AXUIElement, AXError = \(result.rawValue)")
            return nil
        }
        // Runtime type already confirmed via CFGetTypeID above.
        return (element as! AXUIElement)
    }

    private static let editableRoles: Set<String> = [
        "AXTextArea", "AXTextField", "AXComboBox", "AXSecureTextField"
    ]

    /// Whether the focused element is a field the user composes in (editor,
    /// chat box, comment box) as opposed to static content they are reading.
    /// Decides between Grammar (your own writing) and Enhance when the invoke
    /// lands. Unknown roles read as static; Tab switches tabs either way.
    static func isEditableElement(_ element: AXUIElement?) -> Bool {
        guard let element else { return false }
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        guard result == .success, let role = value as? String else { return false }
        return editableRoles.contains(role)
    }

    private static func focusedSelectedText() -> String? {
        guard let element = focusedElement() else { return nil }

        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard result == .success, let text = value as? String else {
            logger.notice("kAXSelectedTextAttribute unavailable, AXError = \(result.rawValue)")
            return nil
        }
        return text
    }

    private static func captureViaClipboard() async -> (text: String, rich: RichSelection?)? {
        // Wait for the user to release the hotkey's modifiers first, or the
        // simulated Cmd-C reaches the app as Ctrl-Option-Cmd-C and does nothing.
        await KeySimulator.waitForModifierRelease()

        let guardBox = ClipboardGuard()
        guardBox.save()
        defer { guardBox.restore() }

        let previousChangeCount = ClipboardGuard.currentChangeCount
        KeySimulator.simulateCommandC()

        // 300 ms: Electron apps and busy web views regularly need >150 ms to
        // service a copy command.
        let changed = await ClipboardGuard.waitForChange(from: previousChangeCount, timeoutMS: 300)
        logger.notice("clipboard changed after simulated Cmd-C = \(changed)")
        guard changed else { return nil }
        // VS Code and its forks (Cursor, Windsurf) copy the whole current
        // line when nothing is selected, and say so on the pasteboard. That
        // line is not a selection — treating it as one ran Enhance on a
        // random line of code.
        if isEmptySelectionEditorCopy(NSPasteboard.general) {
            logger.notice("clipboard holds an editor's empty-selection line copy; ignoring")
            return nil
        }
        guard let text = NSPasteboard.general.string(forType: .string) else { return nil }
        return (text, RichSelection(pasteboard: NSPasteboard.general))
    }

    static var vsCodeEditorDataType: NSPasteboard.PasteboardType { .init("vscode-editor-data") }

    static func isEmptySelectionEditorCopy(_ pasteboard: NSPasteboard) -> Bool {
        guard let json = pasteboard.string(forType: vsCodeEditorDataType) else { return false }
        return isEmptySelectionMarker(json)
    }

    /// Pure so it is testable without a pasteboard.
    static func isEmptySelectionMarker(_ editorDataJSON: String) -> Bool {
        guard let data = editorDataJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["isFromEmptySelection"] as? Bool == true
    }
}
