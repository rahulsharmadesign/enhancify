import AppKit
import Foundation
import SwiftUI

/// Pure resolution of panel key presses to intents.
///
/// Kept free of SwiftUI so the decision table is unit-testable without a host
/// view. `PanelView` owns the side effects; this type only decides.
///
/// Return: typed text in the composer is sent as a refinement; with nothing
/// typed and a finished result on screen, Return replaces the selection, as
/// ⌘↩ always does. Nothing else replaces.
enum PanelKeyIntent: Equatable {
    /// Overwrite the host app's selection with the accepted result.
    case replace
    /// Send the composer instruction to the engine.
    case submit
    /// Copy the accepted result to the clipboard.
    case copy
    /// Cancel any in-flight run and dismiss.
    case cancel
    /// Select the nth tab (1-based).
    case selectTab(index: Int)
    /// Jump to a specific action tab by id (Tab: Enhance ⇄ Grammar).
    case switchAction(id: String)
    /// Reveal the collapsed composer to refine the result (⌘L).
    case showComposer
    /// Not ours — let the event travel on to the focused control.
    case pass
}

/// The subset of modifier state the panel cares about.
struct PanelKeyModifiers: Equatable {
    var command: Bool = false

    static let none = PanelKeyModifiers()
    static let command = PanelKeyModifiers(command: true)
}

extension PanelKeyModifiers {
    /// Bridges SwiftUI's `KeyPress` to the value the decision table takes, so
    /// the resolvers stay testable without constructing a `KeyPress`.
    init(press: KeyPress) {
        self.init(command: press.modifiers.contains(.command))
    }

    /// The composer's text view sees Return before SwiftUI does, so it reads
    /// the modifiers off the AppKit event.
    init(flags: NSEvent.ModifierFlags) {
        self.init(command: flags.contains(.command))
    }
}

enum PanelKeyBinding {
    /// Resolves a Return press.
    ///
    /// - Parameters:
    ///   - modifiers: modifier state at the time of the press.
    ///   - canSubmit: whether the composer holds a non-empty instruction.
    ///   - hasAcceptableResult: whether a result exists that replace could apply.
    static func resolveReturn(
        modifiers: PanelKeyModifiers,
        canSubmit: Bool,
        hasAcceptableResult: Bool
    ) -> PanelKeyIntent {
        if modifiers.command {
            // Explicit destructive intent. Still requires something to apply.
            return hasAcceptableResult ? .replace : .pass
        }
        // Typed text is a refinement, so Return sends it rather than writing
        // the current result into the host.
        if canSubmit {
            return .submit
        }
        // Nothing typed: Return applies the finished result, like ⌘↩. While
        // a result is still streaming there is nothing to apply, so it passes.
        return hasAcceptableResult ? .replace : .pass
    }

    /// Resolves a character press. Returns `.pass` for anything unclaimed.
    static func resolveCharacter(
        _ character: Character,
        modifiers: PanelKeyModifiers,
        tabCount: Int
    ) -> PanelKeyIntent {
        guard modifiers.command else { return .pass }

        if character == "c" { return .copy }
        if character == "l" { return .showComposer }

        if let digit = character.wholeNumberValue, digit >= 1, digit <= tabCount {
            return .selectTab(index: digit)
        }

        return .pass
    }

    /// Resolves Tab (and Shift-Tab): flips between the two writing modes.
    ///
    /// Enhance goes to Grammar; Grammar — or any other tab — goes to Enhance,
    /// so Tab is always one press from the main job. Non-destructive: it only
    /// changes the selected tab, which re-runs on the same selection.
    ///
    /// - Parameters:
    ///   - currentActionID: the tab that is selected now.
    ///   - availableActionIDs: tabs the panel is showing; a removed chip is
    ///     never switched to.
    static func resolveTab(
        currentActionID: String,
        availableActionIDs: Set<String>
    ) -> PanelKeyIntent {
        let target = currentActionID == EnhancementAction.enhanceID
            ? EnhancementAction.grammarID
            : EnhancementAction.enhanceID
        guard target != currentActionID, availableActionIDs.contains(target) else { return .pass }
        return .switchAction(id: target)
    }

    /// Escape always cancels; it is the one unmodified key with a side effect,
    /// and that side effect is non-destructive.
    static func resolveEscape() -> PanelKeyIntent { .cancel }
}
