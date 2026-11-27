import Foundation
import FirebaseCore
import FirebaseAppCheck
import FirebaseRemoteConfig
import GoldfishCore

enum FirebaseSetup {
    /// Configures Firebase when `GoogleService-Info.plist` is bundled. Without it (a fresh clone,
    /// CI, or screenshot mode) the app runs on the scripted fish and the built-in sample chapter.
    static func configureIfPossible(skip: Bool) -> Bool {
        guard !skip, Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return false
        }
        // App Check is enforced for Firebase AI Logic. A sideloaded build with a free Apple ID
        // cannot use App Attest, so every build uses the debug provider. Its token is shown in
        // Diagnostics and must be registered in the Firebase console. See README.
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        FirebaseApp.configure()
        return true
    }

    /// The App Check debug token this install sends, for registering in the console.
    static func debugToken() -> String? {
        guard let app = FirebaseApp.app(), let provider = AppCheckDebugProvider(app: app) else {
            return nil
        }
        return provider.currentDebugToken()
    }
}

/// Reads the Remote Config keys listed in `GoldfishSettings.remoteKeys`.
enum RemoteSettings {
    static func fetch(into settings: GoldfishSettings) async -> (settings: GoldfishSettings, changed: [String]) {
        let config = RemoteConfig.remoteConfig()
        do {
            _ = try await config.fetchAndActivate()
        } catch {
            return (settings, [])
        }
        var updated = settings
        var changed: [String] = []
        for key in GoldfishSettings.remoteKeys {
            let value = config.configValue(forKey: key)
            guard value.source == .remote, let raw = String(data: value.dataValue, encoding: .utf8) else {
                continue
            }
            let before = updated.value(forKey: key)
            updated.apply(raw, forKey: key)
            if updated.value(forKey: key) != before {
                changed.append(key)
            }
        }
        return (updated, changed)
    }
}
