import Foundation
import UniformTypeIdentifiers

nonisolated struct ExportableConfig: Codable, Sendable {
    var version: String = "1.0"
    var exportedAt: String = ""
    var joeURLs: [ExportURL] = []
    var ignitionURLs: [ExportURL] = []
    var joeProxies: [ExportProxy] = []
    var ignitionProxies: [ExportProxy] = []
    var ppsrProxies: [ExportProxy] = []
    var joeVPNConfigs: [ExportVPN] = []
    var ignitionVPNConfigs: [ExportVPN] = []
    var ppsrVPNConfigs: [ExportVPN] = []
    var joeWGConfigs: [ExportWG] = []
    var ignitionWGConfigs: [ExportWG] = []
    var ppsrWGConfigs: [ExportWG] = []
    var dnsServers: [ExportDNS] = []
    var blacklist: [ExportBlacklist] = []
    var connectionModes: ExportConnectionModes = ExportConnectionModes()
    var settings: ExportSettings = ExportSettings()

    nonisolated struct ExportURL: Codable, Sendable {
        let url: String
        let enabled: Bool
    }

    nonisolated struct ExportProxy: Codable, Sendable {
        let host: String
        let port: Int
        let username: String?
        let password: String?
    }

    nonisolated struct ExportVPN: Codable, Sendable {
        let fileName: String
        let remoteHost: String
        let remotePort: Int
        let proto: String
        let rawContent: String
        let enabled: Bool
    }

    nonisolated struct ExportWG: Codable, Sendable {
        let fileName: String
        let rawContent: String
        let enabled: Bool
    }

    nonisolated struct ExportDNS: Codable, Sendable {
        let name: String
        let url: String
        let enabled: Bool
    }

    nonisolated struct ExportBlacklist: Codable, Sendable {
        let email: String
        let reason: String
    }

    nonisolated struct ExportConnectionModes: Codable, Sendable {
        var joe: String = "DNS"
        var ignition: String = "DNS"
        var ppsr: String = "DNS"
    }

    nonisolated struct ExportSettings: Codable, Sendable {
        var autoExcludeBlacklist: Bool = true
        var autoBlacklistNoAcc: Bool = false
    }
}

@MainActor
class AppDataExportService {
    static let shared = AppDataExportService()

    func exportJSON() -> String {
        let urlService = LoginURLRotationService.shared
        let proxyService = ProxyRotationService.shared
        let dnsService = PPSRDoHService.shared
        let blacklistService = BlacklistService.shared

        var config = ExportableConfig()

        config.exportedAt = DateFormatters.exportTimestamp.string(from: Date())

        config.joeURLs = urlService.joeURLs.map { .init(url: $0.urlString, enabled: $0.isEnabled) }
        config.ignitionURLs = urlService.ignitionURLs.map { .init(url: $0.urlString, enabled: $0.isEnabled) }

        config.joeProxies = proxyService.savedProxies.map { .init(host: $0.host, port: $0.port, username: $0.username, password: $0.password) }
        config.ignitionProxies = proxyService.ignitionProxies.map { .init(host: $0.host, port: $0.port, username: $0.username, password: $0.password) }
        config.ppsrProxies = proxyService.ppsrProxies.map { .init(host: $0.host, port: $0.port, username: $0.username, password: $0.password) }

        config.joeVPNConfigs = proxyService.joeVPNConfigs.map { .init(fileName: $0.fileName, remoteHost: $0.remoteHost, remotePort: $0.remotePort, proto: $0.proto, rawContent: $0.rawContent, enabled: $0.isEnabled) }
        config.ignitionVPNConfigs = proxyService.ignitionVPNConfigs.map { .init(fileName: $0.fileName, remoteHost: $0.remoteHost, remotePort: $0.remotePort, proto: $0.proto, rawContent: $0.rawContent, enabled: $0.isEnabled) }
        config.ppsrVPNConfigs = proxyService.ppsrVPNConfigs.map { .init(fileName: $0.fileName, remoteHost: $0.remoteHost, remotePort: $0.remotePort, proto: $0.proto, rawContent: $0.rawContent, enabled: $0.isEnabled) }

        config.joeWGConfigs = proxyService.joeWGConfigs.map { .init(fileName: $0.fileName, rawContent: $0.rawContent, enabled: $0.isEnabled) }
        config.ignitionWGConfigs = proxyService.ignitionWGConfigs.map { .init(fileName: $0.fileName, rawContent: $0.rawContent, enabled: $0.isEnabled) }
        config.ppsrWGConfigs = proxyService.ppsrWGConfigs.map { .init(fileName: $0.fileName, rawContent: $0.rawContent, enabled: $0.isEnabled) }

        config.dnsServers = dnsService.managedProviders.map { .init(name: $0.name, url: $0.url, enabled: $0.isEnabled) }
        config.blacklist = blacklistService.blacklistedEmails.map { .init(email: $0.email, reason: $0.reason) }

        config.connectionModes = .init(
            joe: proxyService.joeConnectionMode.rawValue,
            ignition: proxyService.ignitionConnectionMode.rawValue,
            ppsr: proxyService.ppsrConnectionMode.rawValue
        )

        config.settings = .init(
            autoExcludeBlacklist: blacklistService.autoExcludeBlacklist,
            autoBlacklistNoAcc: blacklistService.autoBlacklistNoAcc
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config), let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    struct ImportResult {
        var urlsImported: Int = 0
        var proxiesImported: Int = 0
        var vpnImported: Int = 0
        var wgImported: Int = 0
        var dnsImported: Int = 0
        var blacklistImported: Int = 0
        var errors: [String] = []

        var summary: String {
            var parts: [String] = []
            if urlsImported > 0 { parts.append("\(urlsImported) URLs") }
            if proxiesImported > 0 { parts.append("\(proxiesImported) proxies") }
            if vpnImported > 0 { parts.append("\(vpnImported) VPN configs") }
            if wgImported > 0 { parts.append("\(wgImported) WireGuard configs") }
            if dnsImported > 0 { parts.append("\(dnsImported) DNS servers") }
            if blacklistImported > 0 { parts.append("\(blacklistImported) blacklist entries") }
            if parts.isEmpty { return "Nothing imported" }
            return "Imported: " + parts.joined(separator: ", ")
        }
    }

    func importJSON(_ jsonString: String) -> ImportResult {
        var result = ImportResult()

        guard let data = jsonString.data(using: .utf8) else {
            result.errors.append("Invalid text data")
            return result
        }

        let config: ExportableConfig
        do {
            config = try JSONDecoder().decode(ExportableConfig.self, from: data)
        } catch {
            result.errors.append("JSON parse error: \(error.localizedDescription)")
            return result
        }

        let urlService = LoginURLRotationService.shared
        let proxyService = ProxyRotationService.shared
        let dnsService = PPSRDoHService.shared
        let blacklistService = BlacklistService.shared

        for exportURL in config.joeURLs {
            if urlService.addURL(exportURL.url, forIgnition: false) {
                result.urlsImported += 1
                if !exportURL.enabled {
                    if let found = urlService.joeURLs.first(where: { $0.urlString == exportURL.url }) {
                        urlService.toggleURL(id: found.id, enabled: false)
                    }
                }
            }
        }
        for exportURL in config.ignitionURLs {
            if urlService.addURL(exportURL.url, forIgnition: true) {
                result.urlsImported += 1
                if !exportURL.enabled {
                    if let found = urlService.ignitionURLs.first(where: { $0.urlString == exportURL.url }) {
                        urlService.toggleURL(id: found.id, enabled: false)
                    }
                }
            }
        }

        for ep in config.joeProxies {
            let line = formatProxyLine(ep)
            let report = proxyService.bulkImportSOCKS5(line, for: .joe)
            result.proxiesImported += report.added
        }
        for ep in config.ignitionProxies {
            let line = formatProxyLine(ep)
            let report = proxyService.bulkImportSOCKS5(line, for: .ignition)
            result.proxiesImported += report.added
        }
        for ep in config.ppsrProxies {
            let line = formatProxyLine(ep)
            let report = proxyService.bulkImportSOCKS5(line, for: .ppsr)
            result.proxiesImported += report.added
        }

        for ev in config.joeVPNConfigs {
            if let vpn = OpenVPNConfig.parse(fileName: ev.fileName, content: ev.rawContent) {
                proxyService.importVPNConfig(vpn, for: .joe)
                if !ev.enabled { proxyService.toggleVPNConfig(vpn, target: .joe, enabled: false) }
                result.vpnImported += 1
            }
        }
        for ev in config.ignitionVPNConfigs {
            if let vpn = OpenVPNConfig.parse(fileName: ev.fileName, content: ev.rawContent) {
                proxyService.importVPNConfig(vpn, for: .ignition)
                if !ev.enabled { proxyService.toggleVPNConfig(vpn, target: .ignition, enabled: false) }
                result.vpnImported += 1
            }
        }
        for ev in config.ppsrVPNConfigs {
            if let vpn = OpenVPNConfig.parse(fileName: ev.fileName, content: ev.rawContent) {
                proxyService.importVPNConfig(vpn, for: .ppsr)
                if !ev.enabled { proxyService.toggleVPNConfig(vpn, target: .ppsr, enabled: false) }
                result.vpnImported += 1
            }
        }

        for ew in config.joeWGConfigs {
            if let wg = WireGuardConfig.parse(fileName: ew.fileName, content: ew.rawContent) {
                proxyService.importWGConfig(wg, for: .joe)
                if !ew.enabled { proxyService.toggleWGConfig(wg, target: .joe, enabled: false) }
                result.wgImported += 1
            }
        }
        for ew in config.ignitionWGConfigs {
            if let wg = WireGuardConfig.parse(fileName: ew.fileName, content: ew.rawContent) {
                proxyService.importWGConfig(wg, for: .ignition)
                if !ew.enabled { proxyService.toggleWGConfig(wg, target: .ignition, enabled: false) }
                result.wgImported += 1
            }
        }
        for ew in config.ppsrWGConfigs {
            if let wg = WireGuardConfig.parse(fileName: ew.fileName, content: ew.rawContent) {
                proxyService.importWGConfig(wg, for: .ppsr)
                if !ew.enabled { proxyService.toggleWGConfig(wg, target: .ppsr, enabled: false) }
                result.wgImported += 1
            }
        }

        for ed in config.dnsServers {
            if dnsService.addProvider(name: ed.name, url: ed.url) {
                if !ed.enabled {
                    if let found = dnsService.managedProviders.first(where: { $0.url == ed.url }) {
                        dnsService.toggleProvider(id: found.id, enabled: false)
                    }
                }
                result.dnsImported += 1
            }
        }

        for eb in config.blacklist {
            if !blacklistService.isBlacklisted(eb.email) {
                blacklistService.addToBlacklist(eb.email, reason: eb.reason)
                result.blacklistImported += 1
            }
        }

        if let joeMode = ConnectionMode(rawValue: config.connectionModes.joe) {
            proxyService.setConnectionMode(joeMode, for: .joe)
        }
        if let ignMode = ConnectionMode(rawValue: config.connectionModes.ignition) {
            proxyService.setConnectionMode(ignMode, for: .ignition)
        }
        if let ppsrMode = ConnectionMode(rawValue: config.connectionModes.ppsr) {
            proxyService.setConnectionMode(ppsrMode, for: .ppsr)
        }

        blacklistService.autoExcludeBlacklist = config.settings.autoExcludeBlacklist
        blacklistService.autoBlacklistNoAcc = config.settings.autoBlacklistNoAcc

        return result
    }

    private func formatProxyLine(_ ep: ExportableConfig.ExportProxy) -> String {
        if let u = ep.username, let p = ep.password {
            return "socks5://\(u):\(p)@\(ep.host):\(ep.port)"
        }
        return "socks5://\(ep.host):\(ep.port)"
    }

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
        return """
        ========================================
        APP STATE EXPORT
        Generated: \(DateFormatters.exportTimestamp.string(from: Date()))
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

        lines.append("")
        lines.append("--- WIREGUARD CONFIGS ---")

        lines.append("Joe Fortune (\(proxyService.joeWGConfigs.count)):")
        for wg in proxyService.joeWGConfigs {
            let status = wg.isEnabled ? "ENABLED" : "DISABLED"
            lines.append("  [\(status)] \(wg.fileName) - \(wg.displayString)")
        }

        lines.append("Ignition (\(proxyService.ignitionWGConfigs.count)):")
        for wg in proxyService.ignitionWGConfigs {
            let status = wg.isEnabled ? "ENABLED" : "DISABLED"
            lines.append("  [\(status)] \(wg.fileName) - \(wg.displayString)")
        }

        lines.append("PPSR (\(proxyService.ppsrWGConfigs.count)):")
        for wg in proxyService.ppsrWGConfigs {
            let status = wg.isEnabled ? "ENABLED" : "DISABLED"
            lines.append("  [\(status)] \(wg.fileName) - \(wg.displayString)")
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
        var lines: [String] = ["--- TESTING HISTORY ---"]
        lines.append("Generated: \(DateFormatters.exportTimestamp.string(from: Date()))")
        lines.append("Total Credentials: \(credentials.count)")
        lines.append("")

        for cred in credentials {
            lines.append("\(cred.username) | Status: \(cred.status.rawValue) | Tests: \(cred.totalTests) | Success: \(cred.successCount)")
            for result in cred.testResults {
                let icon = result.success ? "✓" : "✗"
                let detail = result.responseDetail ?? result.errorMessage ?? ""
                lines.append("  \(icon) \(DateFormatters.exportTimestamp.string(from: result.timestamp)) | \(result.formattedDuration) | \(detail)")
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
