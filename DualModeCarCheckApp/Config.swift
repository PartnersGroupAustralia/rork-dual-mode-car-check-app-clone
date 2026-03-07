// Config.swift - Auto-generated at build time
// Environment variables from Project Settings are injected here
//
// Usage: Config.YOUR_ENV_NAME
// Example: If you set MY_API_KEY in Environment Variables,
//          use Config.MY_API_KEY in your code

import Foundation

enum Config {
    // NordVPN access keys - should be set via Environment Variables in Project Settings
    // To configure: Xcode → Target → Build Settings → User-Defined → add NORD_ACCESS_KEY_NICK / NORD_ACCESS_KEY_POLI
    static let nordAccessKeyNick: String = {
        if let key = ProcessInfo.processInfo.environment["NORD_ACCESS_KEY_NICK"], !key.isEmpty {
            return key
        }
        return ""
    }()

    static let nordAccessKeyPoli: String = {
        if let key = ProcessInfo.processInfo.environment["NORD_ACCESS_KEY_POLI"], !key.isEmpty {
            return key
        }
        return ""
    }()

    static let nordFallbackAccessKey: String = {
        if let key = ProcessInfo.processInfo.environment["NORD_FALLBACK_ACCESS_KEY"], !key.isEmpty {
            return key
        }
        return ""
    }()
}
