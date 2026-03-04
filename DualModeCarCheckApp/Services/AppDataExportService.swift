import Foundation
import UniformTypeIdentifiers

@MainActor
class AppDataExportService {
    static let shared = AppDataExportService()

    func exportComprehensiveState() -> String {
        var sections: [String] = []

        sections.append(exportHeader())
        sections.append(exportURLState())
        sections.append(exportProxyState())
        sections.append(exportDNSState())
        sections.append(exportVPNState())
        sections.append(exportBlacklistState())
        sections.append(exportSettingsState())

        return sections.joined(separator: "\n\n")
    }

    private func exportHeader() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return """
        ========================================
        APP STATE EXPORT
        Generated: \(f.string(from: Date()))
        ========================================
        """
    }

    private func exportURLState() -> String {
        let urlService = LoginURLRotationService.shared
        var lines: [String] = ["--- JOE FORTUNE URLs ---"]
        for url in urlService.joeURLs {
            let status = url.isEnabled ? "ENABLED" : "DISABLED"
            let stats = url.totalAttempts > 0 ? " | \(url.formattedSuccessRate) success | \(url.formattedAvgResponse) avg" : ""
            lines.append("[\(status)] \(url.urlString)\(stats)")
        }
        lines.append("")
        lines.append("--- IGNITION URLs ---")
        for url in urlService.ignitionURLs {
            let status = url.isEnabled ? "ENABLED" : "DISABLED"
            let stats = url.totalAttempts > 0 ? " | \(url.formattedSuccessRate) success | \(url.formattedAvgResponse) avg" : ""
            lines.append("[\(status)] \(url.urlString)\(stats)")
        }
        return lines.joined(separator: "\n")
    }

    private func exportProxyState() -> String {
        let proxyService = ProxyRotationService.shared
        var lines: [String] = ["--- PROXIES ---"]

        lines.append("Joe Fortune (\(proxyService.savedProxies.count)):")
        for proxy in proxyService.savedProxies {
            let status = proxy.isWorking ? "OK" : (proxy.lastTested != nil ? "DEAD" : "UNTESTED")
            lines.append("  [\(status)] \(proxy.displayString)")
        }

        lines.append("Ignition (\(proxyService.ignitionProxies.count)):")
        for proxy in proxyService.ignitionProxies {
            let status = proxy.isWorking ? "OK" : (proxy.lastTested != nil ? "DEAD" : "UNTESTED")
            lines.append("  [\(status)] \(proxy.displayString)")
        }

        lines.append("PPSR (\(proxyService.ppsrProxies.count)):")
        for proxy in proxyService.ppsrProxies {
            let status = proxy.isWorking ? "OK" : (proxy.lastTested != nil ? "DEAD" : "UNTESTED")
            lines.append("  [\(status)] \(proxy.displayString)")
        }

        return lines.joined(separator: "\n")
    }

    private func exportDNSState() -> String {
        let dnsService = PPSRDoHService.shared
        var lines: [String] = ["--- DNS SERVERS ---"]
        for provider in dnsService.managedProviders {
            let status = provider.isEnabled ? "ENABLED" : "DISABLED"
            let def = provider.isDefault ? " (DEFAULT)" : ""
            lines.append("[\(status)] \(provider.name)\(def) - \(provider.url)")
        }
        return lines.joined(separator: "\n")
    }

    private func exportVPNState() -> String {
        let proxyService = ProxyRotationService.shared
        var lines: [String] = ["--- OPENVPN CONFIGS ---"]

        lines.append("Joe Fortune (\(proxyService.joeVPNConfigs.count)):")
        for vpn in proxyService.joeVPNConfigs {
            let status = vpn.isEnabled ? "ENABLED" : "DISABLED"
            lines.append("  [\(status)] \(vpn.fileName) - \(vpn.displayString)")
        }

        lines.append("Ignition (\(proxyService.ignitionVPNConfigs.count)):")
        for vpn in proxyService.ignitionVPNConfigs {
            let status = vpn.isEnabled ? "ENABLED" : "DISABLED"
            lines.append("  [\(status)] \(vpn.fileName) - \(vpn.displayString)")
        }

        lines.append("PPSR (\(proxyService.ppsrVPNConfigs.count)):")
        for vpn in proxyService.ppsrVPNConfigs {
            let status = vpn.isEnabled ? "ENABLED" : "DISABLED"
            lines.append("  [\(status)] \(vpn.fileName) - \(vpn.displayString)")
        }

        return lines.joined(separator: "\n")
    }

    private func exportBlacklistState() -> String {
        let blacklistService = BlacklistService.shared
        var lines: [String] = ["--- BLACKLIST (\(blacklistService.blacklistedEmails.count)) ---"]
        for entry in blacklistService.blacklistedEmails {
            lines.append("\(entry.email) | \(entry.reason) | \(entry.formattedDate)")
        }
        return lines.joined(separator: "\n")
    }

    private func exportSettingsState() -> String {
        let urlService = LoginURLRotationService.shared
        let proxyService = ProxyRotationService.shared
        let blacklistService = BlacklistService.shared
        var lines: [String] = ["--- SETTINGS ---"]
        lines.append("URL Rotation Mode: \(urlService.isIgnitionMode ? "Ignition" : "Joe")")
        lines.append("Joe Enabled URLs: \(urlService.joeURLs.filter(\.isEnabled).count)/\(urlService.joeURLs.count)")
        lines.append("Ignition Enabled URLs: \(urlService.ignitionURLs.filter(\.isEnabled).count)/\(urlService.ignitionURLs.count)")
        lines.append("Joe Connection: \(proxyService.joeConnectionMode.label)")
        lines.append("Ignition Connection: \(proxyService.ignitionConnectionMode.label)")
        lines.append("PPSR Connection: \(proxyService.ppsrConnectionMode.label)")
        lines.append("Auto-Exclude Blacklist: \(blacklistService.autoExcludeBlacklist)")
        lines.append("Auto-Blacklist No Acc: \(blacklistService.autoBlacklistNoAcc)")
        return lines.joined(separator: "\n")
    }

    func exportTestingHistory(credentials: [LoginCredential]) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines: [String] = ["--- TESTING HISTORY ---"]
        lines.append("Generated: \(f.string(from: Date()))")
        lines.append("Total Credentials: \(credentials.count)")
        lines.append("")

        for cred in credentials {
            lines.append("\(cred.username) | Status: \(cred.status.rawValue) | Tests: \(cred.totalTests) | Success: \(cred.successCount)")
            for result in cred.testResults {
                let icon = result.success ? "✓" : "✗"
                let detail = result.responseDetail ?? result.errorMessage ?? ""
                lines.append("  \(icon) \(f.string(from: result.timestamp)) | \(result.formattedDuration) | \(detail)")
            }
            if !cred.testResults.isEmpty { lines.append("") }
        }
        return lines.joined(separator: "\n")
    }

    func exportURLHistory() -> String {
        let urlService = LoginURLRotationService.shared
        var lines: [String] = ["--- URL PERFORMANCE HISTORY ---"]

        lines.append("\nJoe Fortune URLs:")
        for url in urlService.joeURLs.sorted(by: { $0.performanceScore > $1.performanceScore }) {
            lines.append("  \(url.urlString)")
            lines.append("    Enabled: \(url.isEnabled) | Attempts: \(url.totalAttempts) | Success: \(url.formattedSuccessRate) | Avg: \(url.formattedAvgResponse) | Fails: \(url.failCount)")
        }

        lines.append("\nIgnition URLs:")
        for url in urlService.ignitionURLs.sorted(by: { $0.performanceScore > $1.performanceScore }) {
            lines.append("  \(url.urlString)")
            lines.append("    Enabled: \(url.isEnabled) | Attempts: \(url.totalAttempts) | Success: \(url.formattedSuccessRate) | Avg: \(url.formattedAvgResponse) | Fails: \(url.failCount)")
        }

        return lines.joined(separator: "\n")
    }
}
