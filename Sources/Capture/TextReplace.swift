import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.rahul.enhancify", category: "capture")

enum TextReplace {
    /// Replaces the selection with `text`: first via the Accessibility API on
    /// `target` (the element captured at invoke time — the panel holds key
    /// status at replace time so re-querying focus would find the wrong
    /// element), falling back to a simulated Cmd-V. The user's clipboard is
    /// preserved either way.
    ///
    /// `hostBundleID` is the app Enhancify was invoked over. It is the only way
    /// back to the right window when there is no captured element — the
    /// composer-as-source case, where the user typed text instead of
    /// selecting it. Without it the clipboard fallback had nothing to
    /// activate, Cmd-V landed on whatever happened to be key, and Replace
    /// looked like a dead button.
    ///
    /// MainActor-bound with the rest of the replace path: the AX element it
    /// carries is MainActor-held state, and every caller already runs there.
    @MainActor
    static func replaceSelection(
        with text: String,
        target: AXUIElement?,
        hostBundleID: String? = nil,
        rich: RichReplacement.Payload? = nil
    ) async {
        // Writing kAXSelectedText inserts plain text: formatting is dropped and
        // browser editors collapse line breaks into one line. Formatted or
        // multi-line results paste instead, where the host reads the richest
        // type it understands.
        guard rich == nil, !text.contains("\n") else {
            logger.notice("multi-line or formatted result; pasting")
            await replaceViaClipboard(with: text, target: target, hostBundleID: hostBundleID, rich: rich)
            return
        }
        if let target, !isElectronHelper(target), replaceViaAccessibility(with: text, element: target) {
            logger.notice("replaced via AX on captured target")
            return
        }
        if let current = TextCapture.focusedElement(),
           !isOwnWindow(current),
           !isElectronHelper(current),
           replaceViaAccessibility(with: text, element: current) {
            logger.notice("replaced via AX on focused element")
            return
        }
        logger.notice("AX replace skipped or unverified; falling back to clipboard")
        await replaceViaClipboard(with: text, target: target, hostBundleID: hostBundleID)
    }

    /// Enhancify's own windows must never be treated as the write-back target. The
    /// panel stays key while a result is on screen, so the focused-element
    /// probe can find the panel's composer and read its text as "the failed
    /// selection" — replacing into the field the user just typed in.
    @MainActor
    private static func isOwnWindow(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return false }
        return pid == ProcessInfo.processInfo.processIdentifier
    }

    /// Electron (Cursor, Claude, ChatGPT) reports `kAXSelectedText` as settable
    /// and SetAttribute as success without changing the document. Trusting that
    /// skips the Cmd-V fallback, so Replace dismisses and the text stays put.
    @MainActor
    static func isElectronHelper(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier else { return false }
        return HostApp.Info(bundleID: bundleID, name: app.localizedName).isHelper
    }

    /// Whether an AX write actually changed the selection. `SetAttribute`
    /// returning success is not enough — some hosts no-op.
    static func didMutateSelection(before: String?, after: String?, replacement: String) -> Bool {
        if before == replacement { return true }
        if after == replacement { return true }
        if let before, after == before { return false }
        return after != before
    }

    @MainActor
    private static func replaceViaAccessibility(with text: String, element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        guard settableResult == .success, settable.boolValue else { return false }

        let before = selectedText(of: element)
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard result == .success else { return false }
        let after = selectedText(of: element)
        let mutated = didMutateSelection(before: before, after: after, replacement: text)
        if !mutated {
            logger.notice("AX SetAttribute succeeded but selection did not change")
        }
        return mutated
    }

    @MainActor
    private static func selectedText(of element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    @MainActor
    private static func replaceViaClipboard(
        with text: String,
        target: AXUIElement?,
        hostBundleID: String? = nil,
        rich: RichReplacement.Payload? = nil
    ) async {
        if let host = hostApplication(owning: target, bundleID: hostBundleID) {
            await bringToFront(host)
        }
        await KeySimulator.waitForModifierRelease()

        let guardBox = ClipboardGuard()
        guardBox.save()

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // Plain-text fields read `.string`; rich editors prefer RTF or HTML.
        if let rtf = rich?.rtf { NSPasteboard.general.setData(rtf, forType: .rtf) }
        if let html = rich?.html { NSPasteboard.general.setString(html, forType: .html) }
        // nspasteboard.org convention: clipboard-history apps skip transient
        // items, so the temporary paste is not recorded.
        NSPasteboard.general.setData(Data(), forType: ClipboardGuard.transientType)

        KeySimulator.simulateCommandV()

        // Electron and busy web views can take well over a key-repeat to
        // service the paste. Restoring too soon yanks the replacement off the
        // pasteboard before the host reads it; restoring late costs nothing.
        try? await Task.sleep(for: .milliseconds(clipboardRestoreDelayMS))
        guardBox.restore()
    }

    static let clipboardRestoreDelayMS = 800

    /// The app a simulated Cmd-V has to reach.
    ///
    /// The AX element is the precise route, but it is nil whenever the text
    /// came from the composer rather than a host selection, and in Electron
    /// apps it belongs to a helper process (Cursor Helper, Slack Helper) that
    /// cannot be activated — Cmd-V then went nowhere and Replace looked dead.
    /// `bundleID`, the app Enhancify was invoked over, covers both.
    @MainActor
    private static func hostApplication(owning element: AXUIElement?, bundleID: String?) -> NSRunningApplication? {
        var candidates: [NSRunningApplication] = []
        if let element {
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success,
               let running = NSRunningApplication(processIdentifier: pid) {
                candidates.append(running)
            }
        }
        if let bundleID {
            candidates += NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        }
        return candidates.first { app in
            app.bundleIdentifier != Bundle.main.bundleIdentifier
                && app.activationPolicy == .regular
                && !app.isTerminated
        }
    }

    /// Activates `app` and waits until it is frontmost, so Cmd-V lands in its
    /// focused field rather than in the panel that is still fading out.
    /// Activation is asynchronous, and since macOS 14 it is cooperative: the
    /// current app yields first or the request can be ignored.
    @MainActor
    private static func bringToFront(_ app: NSRunningApplication) async {
        if !app.isActive {
            NSApp.yieldActivation(to: app)
            app.activate()
        }
        let deadline = ContinuousClock.now + .milliseconds(600)
        while !app.isActive, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        // The window server hands keyboard focus back a beat after activation.
        try? await Task.sleep(for: .milliseconds(80))
        if !app.isActive {
            logger.notice("host did not become active before paste")
        }
    }
}
