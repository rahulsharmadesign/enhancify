import Foundation
import Observation

/// Persisted app settings. Everything here lives in UserDefaults except API
/// keys, which are stored in the Keychain and only referenced by account name.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    /// Injectable so the defaults and migrations below can be tested against a
    /// scratch domain. The app only ever uses `shared`, on `.standard`.
    private let defaults: UserDefaults

    var activeProvider: ProviderKind {
        didSet { defaults.set(activeProvider.rawValue, forKey: Keys.activeProvider) }
    }

    var ollamaBaseURL: String {
        didSet { defaults.set(ollamaBaseURL, forKey: Keys.ollamaBaseURL) }
    }
    var ollamaEnhanceModel: String {
        didSet { defaults.set(ollamaEnhanceModel, forKey: Keys.ollamaEnhanceModel) }
    }
    var ollamaGrammarModel: String {
        didSet { defaults.set(ollamaGrammarModel, forKey: Keys.ollamaGrammarModel) }
    }

    var customBaseURL: String {
        didSet { defaults.set(customBaseURL, forKey: Keys.customBaseURL) }
    }
    var customEnhanceModel: String {
        didSet { defaults.set(customEnhanceModel, forKey: Keys.customEnhanceModel) }
    }
    var customGrammarModel: String {
        didSet { defaults.set(customGrammarModel, forKey: Keys.customGrammarModel) }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    // One of the twelve app-wide accent choices. Appearance itself always follows macOS.
    var primaryColorID: String {
        didSet { defaults.set(primaryColorID, forKey: PrimaryColor.storageKey) }
    }
    /// Most recently chosen prompt target, used when the host app has no
    /// remembered preference.
    var lastTargetID: String {
        didSet { defaults.set(lastTargetID, forKey: Keys.lastTargetID) }
    }
    /// Host bundle identifier to target id, so returning to an app restores
    /// the target that was used there last.
    var lastTargetByApp: [String: String] {
        didSet { defaults.set(lastTargetByApp, forKey: Keys.lastTargetByApp) }
    }

    /// First-run Get Started has been finished or dismissed after Accessibility.
    var hasCompletedGetStarted: Bool {
        didSet { defaults.set(hasCompletedGetStarted, forKey: Keys.hasCompletedGetStarted) }
    }

    /// Build number of the last run. Compared at launch so an in-app update
    /// that silently invalidated the Accessibility grant can route to
    /// Permissions with the re-grant steps instead of failing at the hotkey.
    var lastRunBuild: String? {
        didSet { defaults.set(lastRunBuild, forKey: Keys.lastRunBuild) }
    }

    private enum Keys {
        static let activeProvider = "activeProvider"
        static let ollamaBaseURL = "ollamaBaseURL"
        static let ollamaEnhanceModel = "ollamaEnhanceModel"
        static let ollamaGrammarModel = "ollamaGrammarModel"
        static let customBaseURL = "customBaseURL"
        static let customEnhanceModel = "customEnhanceModel"
        static let customGrammarModel = "customGrammarModel"
        static let launchAtLogin = "launchAtLogin"
        static let primaryColorID = "primaryColorID"
        static let lastTargetID = "lastTargetID"
        static let lastTargetByApp = "lastTargetByApp"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let hasCompletedGetStarted = "hasCompletedGetStarted"
        static let lastRunBuild = "lastRunBuild"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let hasLaunchedBefore = defaults.bool(forKey: Keys.hasLaunchedBefore)
        if !hasLaunchedBefore {
            // Zero-install default: Apple's on-device model when this Mac can
            // answer, otherwise local Ollama. Either way nothing needs a key.
            defaults.set(
                Self.firstLaunchProvider(appleOnDeviceReady: AppleModelState.isConfigured).rawValue,
                forKey: Keys.activeProvider
            )
            defaults.set(true, forKey: Keys.hasLaunchedBefore)
        }

        activeProvider = defaults.string(forKey: Keys.activeProvider)
            .flatMap(ProviderKind.init(rawValue:))
            ?? Self.firstLaunchProvider(appleOnDeviceReady: AppleModelState.isConfigured)
        ollamaBaseURL = defaults.string(forKey: Keys.ollamaBaseURL) ?? "http://localhost:11434/v1"
        ollamaEnhanceModel = defaults.string(forKey: Keys.ollamaEnhanceModel)
            ?? RecommendedOllamaModel.defaultID
        // Same model for both roles by default: two different models make
        // Ollama swap weights in and out when the user switches tabs, which
        // costs seconds; one resident model serves both instantly.
        ollamaGrammarModel = defaults.string(forKey: Keys.ollamaGrammarModel)
            ?? RecommendedOllamaModel.defaultID
        customBaseURL = defaults.string(forKey: Keys.customBaseURL) ?? ""
        var enhanceModel = defaults.string(forKey: Keys.customEnhanceModel) ?? ""
        var grammarModel = defaults.string(forKey: Keys.customGrammarModel) ?? ""
        if CompatibleAPIPreset.retiredGroqModels.contains(enhanceModel) {
            enhanceModel = CompatibleAPIPreset.groq.defaultModel
            defaults.set(enhanceModel, forKey: Keys.customEnhanceModel)
        }
        if CompatibleAPIPreset.retiredGroqModels.contains(grammarModel) {
            grammarModel = CompatibleAPIPreset.groq.defaultModel
            defaults.set(grammarModel, forKey: Keys.customGrammarModel)
        }
        customEnhanceModel = enhanceModel
        customGrammarModel = grammarModel
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        primaryColorID = defaults.string(forKey: PrimaryColor.storageKey) ?? PrimaryColor.violet.rawValue
        lastTargetID = defaults.string(forKey: Keys.lastTargetID) ?? TargetProfile.genericID
        lastTargetByApp = defaults.dictionary(forKey: Keys.lastTargetByApp) as? [String: String] ?? [:]
        hasCompletedGetStarted = defaults.bool(forKey: Keys.hasCompletedGetStarted)
        lastRunBuild = defaults.string(forKey: Keys.lastRunBuild)
    }

    /// Which provider a fresh install (or an unrecognised stored value) lands
    /// on. Apple on-device when this Mac can answer — zero install, nothing
    /// leaves the Mac — otherwise local Ollama. Pure so the mapping stays
    /// pinnable without Apple Intelligence on the test host.
    nonisolated static func firstLaunchProvider(appleOnDeviceReady: Bool) -> ProviderKind {
        appleOnDeviceReady ? .apple : .ollama
    }

    /// Whether a provider has enough settings to attempt a request.
    ///
    /// Non-empty was too weak a test: a base URL of `" "` or `hello` passed, so
    /// onboarding could complete and the first run would fail with a confusing
    /// transport error. URLs must now actually parse as http(s) with a host.
    func isConfigured(_ kind: ProviderKind) -> Bool {
        switch kind {
        case .ollama:
            return Self.isUsableBaseURL(ollamaBaseURL)
                && Self.isUsableModel(ollamaEnhanceModel)
                && Self.isUsableModel(ollamaGrammarModel)
        case .anthropic:
            return Self.isUsableKey(resolvedAnthropicAPIKey)
        case .apple:
            // No key, no URL, no download: "configured" means Apple's model
            // answers on this Mac, which is purely a system state.
            return AppleModelState.isConfigured
        case .custom:
            // Remote hosts (Groq, OpenAI, …) need a key; loopback servers often don't.
            guard Self.isUsableBaseURL(customBaseURL),
                  Self.isUsableModel(customEnhanceModel),
                  Self.isUsableModel(customGrammarModel) else { return false }
            return Self.isLoopback(customBaseURL) || Self.isUsableKey(resolvedCustomAPIKey)
        }
    }

    /// Parses as an http(s) URL with a host. Pure; not isolated to the store.
    nonisolated static func isUsableBaseURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else { return false }
        return true
    }

    nonisolated static func isUsableModel(_ raw: String) -> Bool {
        !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Rejects whitespace-only keys, which read as configured but never work.
    nonisolated static func isUsableKey(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated static func isLoopback(_ raw: String) -> Bool {
        guard let host = URLComponents(
            string: raw.trimmingCharacters(in: .whitespacesAndNewlines)
        )?.host?.lowercased() else { return false }
        // URLComponents keeps IPv6 literals bracketed (`[::1]`), so unwrap
        // before comparing. `0.0.0.0` is treated as loopback because local
        // OpenAI-compat servers bind there the same way they bind localhost.
        let unwrapped = (host.hasPrefix("[") && host.hasSuffix("]"))
            ? String(host.dropFirst().dropLast())
            : host
        return unwrapped == "localhost"
            || unwrapped == "127.0.0.1"
            || unwrapped == "::1"
            || unwrapped == "0.0.0.0"
    }

    /// Providers other than the active one that are configured and could serve
    /// as a fallback. Used by the panel's error state to offer "Try with X".
    var fallbackProviders: [ProviderKind] {
        ProviderKind.allCases.filter { $0 != activeProvider && isConfigured($0) }
    }

    /// Switches provider. Kept separate from the property so callers can be
    /// notified and pre-load the newly selected local model.
    func selectProvider(_ kind: ProviderKind) {
        guard kind != activeProvider else { return }
        activeProvider = kind
        onProviderChanged?(kind)
    }

    /// Set by the coordinator to warm the newly selected provider's model.
    var onProviderChanged: ((ProviderKind) -> Void)?

    /// The concrete model id the active provider will use for a role.
    func modelID(for role: ModelRole) -> String {
        switch activeProvider {
        case .ollama:
            return role == .enhance ? ollamaEnhanceModel : ollamaGrammarModel
        case .custom:
            return role == .enhance ? customEnhanceModel : customGrammarModel
        case .anthropic:
            return role == .enhance
                ? AnthropicProvider.Constants.enhanceModel
                : AnthropicProvider.Constants.grammarModel
        case .apple:
            return AppleOnDeviceProvider.modelID
        }
    }


    var anthropicAPIKey: String? {
        get { cachedKey(\.anthropicKeyCache, account: "anthropic") }
        set { storeKey(newValue, cache: \.anthropicKeyCache, account: "anthropic") }
    }

    var customAPIKey: String? {
        get { cachedKey(\.customKeyCache, account: "custom") }
        set { storeKey(newValue, cache: \.customKeyCache, account: "custom") }
    }

    /// Keychain first, then `ENHANCIFY_ANTHROPIC_API_KEY`. Settings fields still
    /// read `anthropicAPIKey` so an env value is not copied into Keychain.
    var resolvedAnthropicAPIKey: String? {
        ProviderAPIKey.resolved(
            stored: anthropicAPIKey,
            fallback: ProviderAPIKey.fromEnvironment(
                name: ProviderAPIKey.anthropicEnvironmentVariable
            )
        )
    }

    /// Keychain first, then `ENHANCIFY_API_KEY`.
    var resolvedCustomAPIKey: String? {
        ProviderAPIKey.resolved(
            stored: customAPIKey,
            fallback: ProviderAPIKey.fromEnvironment()
        )
    }

    private var anthropicKeyCache: KeyCache = .unloaded
    private var customKeyCache: KeyCache = .unloaded

    private enum KeyCache: Equatable {
        case unloaded
        case loaded(String?)
    }

    private func cachedKey(_ keyPath: ReferenceWritableKeyPath<SettingsStore, KeyCache>, account: String) -> String? {
        if case .loaded(let value) = self[keyPath: keyPath] { return value }
        let value = KeychainStore.shared.load(account: account)
        self[keyPath: keyPath] = .loaded(value)
        return value
    }

    private func storeKey(_ newValue: String?, cache: ReferenceWritableKeyPath<SettingsStore, KeyCache>, account: String) {
        let normalized = newValue.flatMap { $0.isEmpty ? nil : $0 }
        if case .loaded(let current) = self[keyPath: cache], current == normalized { return }
        self[keyPath: cache] = .loaded(normalized)
        if let normalized {
            _ = KeychainStore.shared.save(key: normalized, account: account)
        } else {
            _ = KeychainStore.shared.delete(account: account)
        }
    }
}
