import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralSettingsTab: View {
    @Bindable private var settings = SettingsStore.shared

    var body: some View {
        SettingsPage(
            title: DashboardRoute.general.title,
            subtitle: DashboardRoute.general.pageSubtitle,
            icon: DashboardRoute.general.lucideIcon
        ) {
            SettingsSection(
                title: "Accent",
                subtitle: "Enhancify's tint across pills, selection, and the send disc."
            ) {
                SettingsAccentSwatches(
                    selection: Binding(
                        get: { PrimaryColor(rawValue: settings.primaryColorID) ?? .violet },
                        set: { settings.primaryColorID = $0.rawValue }
                    )
                )
            }

            SettingsSection(title: "Keyboard") {
                SettingsRow(title: "Open Enhancify", caption: "Select text in another app, then press this shortcut.") {
                    SettingsShortcutRecorder(name: .invokeEnhancify)
                }
                SettingsRow(title: "Dictate", caption: "Opens Enhancify and starts listening.") {
                    SettingsShortcutRecorder(name: .dictateToEnhancify)
                }
            }

            SettingsSection(title: "Startup") {
                SettingsRow(title: "Run Enhancify at login") {
                    SettingsSwitch(isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { enabled in
                            settings.launchAtLogin = enabled
                            applyLaunchAtLogin(enabled)
                        }
                    ), accessibilityLabel: "Run Enhancify at login")
                }
            }
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { }
    }
}
