import Foundation
import Observation

nonisolated enum ConnectionMode: String, CaseIterable, Sendable {
    case dns = "DNS"
    case proxy = "Proxy"
    case openvpn = "OpenVPN"
    case wireguard = "WireGuard"

    var icon: String {
        switch self {
        case .dns: "lock.shield.fill"
        case .proxy: "network"
        case .openvpn: "shield.lefthalf.filled"
        case .wireguard: "lock.trianglebadge.exclamationmark.fill"
        }
    }

    var label: String {
        switch self {
        case .dns: "DNS-over-HTTPS"
        case .proxy: "SOCKS5 Proxy"
        case .openvpn: "OpenVPN"
        case .wireguard: "WireGuard"
        }
    }
}

@Observable
@MainActor
class ProxyRotationService {
    static let shared = ProxyRotationService()

    nonisolated enum ProxyTarget: String, Sendable {
        case joe
        case ignition
        case ppsr
    }

    var savedProxies: [ProxyConfig] = []
    var ignitionProxies: [ProxyConfig] = []
    var ppsrProxies: [ProxyConfig] = []

    var joeVPNConfigs: [OpenVPNConfig] = []
    var ignitionVPNConfigs: [OpenVPNConfig] = []
    var ppsrVPNConfigs: [OpenVPNConfig] = []

    var joeWGConfigs: [WireGuardConfig] = []
    var ignitionWGConfigs: [WireGuardConfig] = []
    var ppsrWGConfigs: [WireGuardConfig] = []
    var currentProxyIndex: Int = 0
    var currentIgnitionProxyIndex: Int = 0
    var currentPPSRProxyIndex: Int = 0
    var rotateAfterDisabled: Bool = true
    var lastImportReport: ImportReport?

    var joeConnectionMode: ConnectionMode = .dns
    var ignitionConnectionMode: ConnectionMode = .dns
    var ppsrConnectionMode: ConnectionMode = .dns

    struct ImportReport {
        let added: Int
        let duplicates: Int
        let failed: [String]
        var total: Int { added + duplicates + failed.count }
    }

    private let persistKey = "saved_socks5_proxies_v2"
    private let ignitionPersistKey = "saved_socks5_proxies_ignition_v1"
    private let ppsrPersistKey = "saved_socks5_proxies_ppsr_v1"
    private let connectionModePersistKey = "connection_modes_v1"

    private let joeVPNPersistKey = "openvpn_configs_joe_v1"
    private let ignitionVPNPersistKey = "openvpn_configs_ignition_v1"
    private let ppsrVPNPersistKey = "openvpn_configs_ppsr_v1"

    private let joeWGPersistKey = "wireguard_configs_joe_v1"
    private let ignitionWGPersistKey = "wireguard_configs_ignition_v1"
    private let ppsrWGPersistKey = "wireguard_configs_ppsr_v1"

    init() {
        loadProxies()
        loadIgnitionProxies()
        loadPPSRProxies()
        loadConnectionModes()
        loadVPNConfigs()
        loadWGConfigs()
    }

    func setConnectionMode(_ mode: ConnectionMode, for target: ProxyTarget) {
        switch target {
        case .joe: joeConnectionMode = mode
        case .ignition: ignitionConnectionMode = mode
        case .ppsr: ppsrConnectionMode = mode
        }
        persistConnectionModes()
    }

    func connectionMode(for target: ProxyTarget) -> ConnectionMode {
        switch target {
        case .joe: joeConnectionMode
        case .ignition: ignitionConnectionMode
        case .ppsr: ppsrConnectionMode
        }
    }

    func proxies(for target: ProxyTarget) -> [ProxyConfig] {
        switch target {
        case .joe: savedProxies
        case .ignition: ignitionProxies
        case .ppsr: ppsrProxies
        }
    }

    func bulkImportSOCKS5(_ text: String, for target: ProxyTarget) -> ImportReport {
        switch target {
        case .joe: return bulkImportSOCKS5(text, forIgnition: false)
        case .ignition: return bulkImportSOCKS5(text, forIgnition: true)
        case .ppsr: return bulkImportSOCKS5PPSR(text)
        }
    }

    func bulkImportSOCKS5(_ text: String, forIgnition: Bool = false) -> ImportReport {
        let expandedLines = expandProxyLines(text)

        var added = 0
        var duplicates = 0
        var failed: [String] = []

        let targetList = forIgnition ? ignitionProxies : savedProxies
        for line in expandedLines {
            if let proxy = parseProxyLine(line) {
                let isDuplicate = targetList.contains { $0.host == proxy.host && $0.port == proxy.port && $0.username == proxy.username }
                if isDuplicate {
                    duplicates += 1
                } else {
                    if forIgnition {
                        ignitionProxies.append(proxy)
                    } else {
                        savedProxies.append(proxy)
                    }
                    added += 1
                }
            } else {
                failed.append(line)
            }
        }

        if added > 0 {
            if forIgnition { persistIgnitionProxies() } else { persistProxies() }
        }

        let report = ImportReport(added: added, duplicates: duplicates, failed: failed)
        lastImportReport = report
        return report
    }

    private func bulkImportSOCKS5PPSR(_ text: String) -> ImportReport {
        let expandedLines = expandProxyLines(text)

        var added = 0
        var duplicates = 0
        var failed: [String] = []

        for line in expandedLines {
            if let proxy = parseProxyLine(line) {
                let isDuplicate = ppsrProxies.contains { $0.host == proxy.host && $0.port == proxy.port && $0.username == proxy.username }
                if isDuplicate {
                    duplicates += 1
                } else {
                    ppsrProxies.append(proxy)
                    added += 1
                }
            } else {
                failed.append(line)
            }
        }

        if added > 0 { persistPPSRProxies() }
        let report = ImportReport(added: added, duplicates: duplicates, failed: failed)
        lastImportReport = report
        return report
    }

    private func expandProxyLines(_ text: String) -> [String] {
        let rawLines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var expandedLines: [String] = []
        for line in rawLines {
            if line.contains("\t") {
                expandedLines.append(contentsOf: line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            } else if line.contains(" ") && !line.contains("://") {
                expandedLines.append(contentsOf: line.components(separatedBy: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            } else {
                expandedLines.append(line)
            }
        }
        return expandedLines
    }

    private func parseProxyLine(_ raw: String) -> ProxyConfig? {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        let schemePatterns = ["socks5h://", "socks5://", "socks4://", "socks://", "http://", "https://"]
        for scheme in schemePatterns {
            if line.lowercased().hasPrefix(scheme) {
                line = String(line.dropFirst(scheme.count))
                break
            }
        }

        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        guard !line.isEmpty else { return nil }

        var username: String?
        var password: String?
        var hostPort: String

        if let atIndex = line.lastIndex(of: "@") {
            let authPart = String(line[line.startIndex..<atIndex])
            hostPort = String(line[line.index(after: atIndex)...])

            let authComponents = splitFirst(authPart, separator: ":")
            if let pw = authComponents.rest {
                username = authComponents.first
                password = pw
            } else {
                username = authPart
            }
        } else {
            let colonCount = line.filter({ $0 == ":" }).count
            if colonCount >= 3 {
                let parts = line.components(separatedBy: ":")
                if parts.count == 4, let _ = Int(parts[3]) {
                    username = parts[0]
                    password = parts[1]
                    hostPort = "\(parts[2]):\(parts[3])"
                } else if parts.count == 4, let _ = Int(parts[1]) {
                    hostPort = "\(parts[0]):\(parts[1])"
                    username = parts[2]
                    password = parts[3]
                } else {
                    hostPort = line
                }
            } else {
                hostPort = line
            }
        }

        hostPort = hostPort.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        guard !hostPort.isEmpty else { return nil }

        let hpParts = hostPort.components(separatedBy: ":")
        guard hpParts.count >= 2 else { return nil }

        let portString = hpParts.last?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let port = Int(portString), port > 0, port <= 65535 else { return nil }

        let host = hpParts.dropLast().joined(separator: ":").trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }

        let validHostChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let hostChars = CharacterSet(charactersIn: host)
        guard validHostChars.isSuperset(of: hostChars) || isValidIPv4(host) else { return nil }

        if let u = username, u.isEmpty { username = nil }
        if let p = password, p.isEmpty { password = nil }

        return ProxyConfig(host: host, port: port, username: username, password: password)
    }

    private func splitFirst(_ s: String, separator: Character) -> (first: String, rest: String?) {
        if let idx = s.firstIndex(of: separator) {
            return (String(s[s.startIndex..<idx]), String(s[s.index(after: idx)...]))
        }
        return (s, nil)
    }

    private func isValidIPv4(_ host: String) -> Bool {
        let octets = host.components(separatedBy: ".")
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard let num = Int(octet) else { return false }
            return num >= 0 && num <= 255
        }
    }

    func nextWorkingProxy(for target: ProxyTarget) -> ProxyConfig? {
        switch target {
        case .joe: return nextWorkingProxy(forIgnition: false)
        case .ignition: return nextWorkingProxy(forIgnition: true)
        case .ppsr: return nextWorkingPPSRProxy()
        }
    }

    func nextWorkingProxy(forIgnition: Bool = false) -> ProxyConfig? {
        if forIgnition {
            let working = ignitionProxies.filter(\.isWorking)
            guard !working.isEmpty else {
                return ignitionProxies.isEmpty ? nil : ignitionProxies[currentIgnitionProxyIndex % ignitionProxies.count]
            }
            currentIgnitionProxyIndex = currentIgnitionProxyIndex % working.count
            let proxy = working[currentIgnitionProxyIndex]
            currentIgnitionProxyIndex += 1
            return proxy
        }
        let working = savedProxies.filter(\.isWorking)
        guard !working.isEmpty else {
            return savedProxies.isEmpty ? nil : savedProxies[currentProxyIndex % savedProxies.count]
        }
        currentProxyIndex = currentProxyIndex % working.count
        let proxy = working[currentProxyIndex]
        currentProxyIndex += 1
        return proxy
    }

    private func nextWorkingPPSRProxy() -> ProxyConfig? {
        let working = ppsrProxies.filter(\.isWorking)
        guard !working.isEmpty else {
            return ppsrProxies.isEmpty ? nil : ppsrProxies[currentPPSRProxyIndex % ppsrProxies.count]
        }
        currentPPSRProxyIndex = currentPPSRProxyIndex % working.count
        let proxy = working[currentPPSRProxyIndex]
        currentPPSRProxyIndex += 1
        return proxy
    }

    func markProxyWorking(_ proxy: ProxyConfig) {
        if let idx = savedProxies.firstIndex(where: { $0.id == proxy.id }) {
            savedProxies[idx].isWorking = true
            savedProxies[idx].lastTested = Date()
            savedProxies[idx].failCount = 0
            persistProxies()
        }
        if let idx = ignitionProxies.firstIndex(where: { $0.id == proxy.id }) {
            ignitionProxies[idx].isWorking = true
            ignitionProxies[idx].lastTested = Date()
            ignitionProxies[idx].failCount = 0
            persistIgnitionProxies()
        }
        if let idx = ppsrProxies.firstIndex(where: { $0.id == proxy.id }) {
            ppsrProxies[idx].isWorking = true
            ppsrProxies[idx].lastTested = Date()
            ppsrProxies[idx].failCount = 0
            persistPPSRProxies()
        }
    }

    func markProxyFailed(_ proxy: ProxyConfig) {
        if let idx = savedProxies.firstIndex(where: { $0.id == proxy.id }) {
            savedProxies[idx].failCount += 1
            savedProxies[idx].lastTested = Date()
            if savedProxies[idx].failCount >= 3 {
                savedProxies[idx].isWorking = false
            }
            persistProxies()
        }
        if let idx = ignitionProxies.firstIndex(where: { $0.id == proxy.id }) {
            ignitionProxies[idx].failCount += 1
            ignitionProxies[idx].lastTested = Date()
            if ignitionProxies[idx].failCount >= 3 {
                ignitionProxies[idx].isWorking = false
            }
            persistIgnitionProxies()
        }
        if let idx = ppsrProxies.firstIndex(where: { $0.id == proxy.id }) {
            ppsrProxies[idx].failCount += 1
            ppsrProxies[idx].lastTested = Date()
            if ppsrProxies[idx].failCount >= 3 {
                ppsrProxies[idx].isWorking = false
            }
            persistPPSRProxies()
        }
    }

    func removeProxy(_ proxy: ProxyConfig, fromIgnition: Bool = false) {
        if fromIgnition {
            ignitionProxies.removeAll { $0.id == proxy.id }
            persistIgnitionProxies()
        } else {
            savedProxies.removeAll { $0.id == proxy.id }
            persistProxies()
        }
    }

    func removeProxy(_ proxy: ProxyConfig, target: ProxyTarget) {
        switch target {
        case .joe:
            savedProxies.removeAll { $0.id == proxy.id }
            persistProxies()
        case .ignition:
            ignitionProxies.removeAll { $0.id == proxy.id }
            persistIgnitionProxies()
        case .ppsr:
            ppsrProxies.removeAll { $0.id == proxy.id }
            persistPPSRProxies()
        }
    }

    func removeAll(forIgnition: Bool = false) {
        if forIgnition {
            ignitionProxies.removeAll()
            currentIgnitionProxyIndex = 0
            persistIgnitionProxies()
        } else {
            savedProxies.removeAll()
            currentProxyIndex = 0
            persistProxies()
        }
    }

    func removeAll(target: ProxyTarget) {
        switch target {
        case .joe: removeAll(forIgnition: false)
        case .ignition: removeAll(forIgnition: true)
        case .ppsr:
            ppsrProxies.removeAll()
            currentPPSRProxyIndex = 0
            persistPPSRProxies()
        }
    }

    func removeDead(forIgnition: Bool = false) {
        if forIgnition {
            ignitionProxies.removeAll { !$0.isWorking && $0.lastTested != nil }
            persistIgnitionProxies()
        } else {
            savedProxies.removeAll { !$0.isWorking && $0.lastTested != nil }
            persistProxies()
        }
    }

    func removeDead(target: ProxyTarget) {
        switch target {
        case .joe: removeDead(forIgnition: false)
        case .ignition: removeDead(forIgnition: true)
        case .ppsr:
            ppsrProxies.removeAll { !$0.isWorking && $0.lastTested != nil }
            persistPPSRProxies()
        }
    }

    func resetAllStatus(forIgnition: Bool = false) {
        if forIgnition {
            for i in ignitionProxies.indices {
                ignitionProxies[i].isWorking = false
                ignitionProxies[i].lastTested = nil
                ignitionProxies[i].failCount = 0
            }
            persistIgnitionProxies()
        } else {
            for i in savedProxies.indices {
                savedProxies[i].isWorking = false
                savedProxies[i].lastTested = nil
                savedProxies[i].failCount = 0
            }
            persistProxies()
        }
    }

    func resetAllStatus(target: ProxyTarget) {
        switch target {
        case .joe: resetAllStatus(forIgnition: false)
        case .ignition: resetAllStatus(forIgnition: true)
        case .ppsr:
            for i in ppsrProxies.indices {
                ppsrProxies[i].isWorking = false
                ppsrProxies[i].lastTested = nil
                ppsrProxies[i].failCount = 0
            }
            persistPPSRProxies()
        }
    }

    func testAllProxies(forIgnition: Bool = false) async {
        let maxConcurrent = 5
        if forIgnition {
            let proxySnapshot = ignitionProxies
            await withTaskGroup(of: (UUID, Bool).self) { group in
                var launched = 0
                for proxy in proxySnapshot {
                    if launched >= maxConcurrent {
                        if let result = await group.next() {
                            applyTestResult(result, forIgnition: true)
                        }
                    }
                    group.addTask {
                        let working = await self.testSingleProxy(proxy)
                        return (proxy.id, working)
                    }
                    launched += 1
                }
                for await result in group {
                    applyTestResult(result, forIgnition: true)
                }
            }
            persistIgnitionProxies()
        } else {
            let proxySnapshot = savedProxies
            await withTaskGroup(of: (UUID, Bool).self) { group in
                var launched = 0
                for proxy in proxySnapshot {
                    if launched >= maxConcurrent {
                        if let result = await group.next() {
                            applyTestResult(result, forIgnition: false)
                        }
                    }
                    group.addTask {
                        let working = await self.testSingleProxy(proxy)
                        return (proxy.id, working)
                    }
                    launched += 1
                }
                for await result in group {
                    applyTestResult(result, forIgnition: false)
                }
            }
            persistProxies()
        }
    }

    func testAllProxies(target: ProxyTarget) async {
        switch target {
        case .joe: await testAllProxies(forIgnition: false)
        case .ignition: await testAllProxies(forIgnition: true)
        case .ppsr:
            let maxConcurrent = 5
            let proxySnapshot = ppsrProxies
            await withTaskGroup(of: (UUID, Bool).self) { group in
                var launched = 0
                for proxy in proxySnapshot {
                    if launched >= maxConcurrent {
                        if let result = await group.next() {
                            applyPPSRTestResult(result)
                        }
                    }
                    group.addTask {
                        let working = await self.testSingleProxy(proxy)
                        return (proxy.id, working)
                    }
                    launched += 1
                }
                for await result in group {
                    applyPPSRTestResult(result)
                }
            }
            persistPPSRProxies()
        }
    }

    private func applyTestResult(_ result: (UUID, Bool), forIgnition: Bool) {
        let (proxyId, working) = result
        if forIgnition {
            if let idx = ignitionProxies.firstIndex(where: { $0.id == proxyId }) {
                ignitionProxies[idx].isWorking = working
                ignitionProxies[idx].lastTested = Date()
                if working { ignitionProxies[idx].failCount = 0 }
                else { ignitionProxies[idx].failCount += 1 }
            }
        } else {
            if let idx = savedProxies.firstIndex(where: { $0.id == proxyId }) {
                savedProxies[idx].isWorking = working
                savedProxies[idx].lastTested = Date()
                if working { savedProxies[idx].failCount = 0 }
                else { savedProxies[idx].failCount += 1 }
            }
        }
    }

    private func applyPPSRTestResult(_ result: (UUID, Bool)) {
        let (proxyId, working) = result
        if let idx = ppsrProxies.firstIndex(where: { $0.id == proxyId }) {
            ppsrProxies[idx].isWorking = working
            ppsrProxies[idx].lastTested = Date()
            if working { ppsrProxies[idx].failCount = 0 }
            else { ppsrProxies[idx].failCount += 1 }
        }
    }

    private nonisolated func testSingleProxy(_ proxy: ProxyConfig) async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15

        var proxyDict: [String: Any] = [
            "SOCKSEnable": 1,
            "SOCKSProxy": proxy.host,
            "SOCKSPort": proxy.port,
        ]
        if let u = proxy.username { proxyDict["SOCKSUser"] = u }
        if let p = proxy.password { proxyDict["SOCKSPassword"] = p }
        config.connectionProxyDictionary = proxyDict

        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let testURLs = [
            "https://api.ipify.org?format=json",
            "https://httpbin.org/ip",
            "https://ifconfig.me/ip"
        ]

        for urlString in testURLs {
            guard let url = URL(string: urlString) else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }

    func exportProxies(forIgnition: Bool = false) -> String {
        let list = forIgnition ? ignitionProxies : savedProxies
        return formatProxyList(list)
    }

    func exportProxies(target: ProxyTarget) -> String {
        formatProxyList(proxies(for: target))
    }

    private func formatProxyList(_ list: [ProxyConfig]) -> String {
        list.map { proxy in
            if let u = proxy.username, let p = proxy.password {
                return "socks5://\(u):\(p)@\(proxy.host):\(proxy.port)"
            } else {
                return "socks5://\(proxy.host):\(proxy.port)"
            }
        }.joined(separator: "\n")
    }

    var activeProxies: [ProxyConfig] {
        savedProxies
    }

    func proxies(forIgnition: Bool) -> [ProxyConfig] {
        forIgnition ? ignitionProxies : savedProxies
    }

    private func persistIgnitionProxies() {
        persistProxyList(ignitionProxies, key: ignitionPersistKey)
    }

    private func loadIgnitionProxies() {
        ignitionProxies = loadProxyList(key: ignitionPersistKey)
    }

    private func persistProxies() {
        persistProxyList(savedProxies, key: persistKey)
    }

    private func persistPPSRProxies() {
        persistProxyList(ppsrProxies, key: ppsrPersistKey)
    }

    private func loadPPSRProxies() {
        ppsrProxies = loadProxyList(key: ppsrPersistKey)
    }

    private func persistProxyList(_ list: [ProxyConfig], key: String) {
        let encoded = list.map { p -> [String: Any] in
            var dict: [String: Any] = [
                "id": p.id.uuidString,
                "host": p.host,
                "port": p.port,
                "isWorking": p.isWorking,
                "failCount": p.failCount,
            ]
            if let u = p.username { dict["username"] = u }
            if let pw = p.password { dict["password"] = pw }
            if let d = p.lastTested { dict["lastTested"] = d.timeIntervalSince1970 }
            return dict
        }
        if let data = try? JSONSerialization.data(withJSONObject: encoded) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadProxyList(key: String) -> [ProxyConfig] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { dict -> ProxyConfig? in
            guard let host = dict["host"] as? String,
                  let port = dict["port"] as? Int else { return nil }
            var proxy = ProxyConfig(
                host: host,
                port: port,
                username: dict["username"] as? String,
                password: dict["password"] as? String
            )
            proxy.isWorking = dict["isWorking"] as? Bool ?? false
            proxy.failCount = dict["failCount"] as? Int ?? 0
            if let ts = dict["lastTested"] as? TimeInterval {
                proxy.lastTested = Date(timeIntervalSince1970: ts)
            }
            return proxy
        }
    }

    private func persistConnectionModes() {
        let dict: [String: String] = [
            "joe": joeConnectionMode.rawValue,
            "ignition": ignitionConnectionMode.rawValue,
            "ppsr": ppsrConnectionMode.rawValue,
        ]
        UserDefaults.standard.set(dict, forKey: connectionModePersistKey)
    }

    private func loadConnectionModes() {
        guard let dict = UserDefaults.standard.dictionary(forKey: connectionModePersistKey) as? [String: String] else { return }
        if let joe = dict["joe"], let mode = ConnectionMode(rawValue: joe) { joeConnectionMode = mode }
        if let ign = dict["ignition"], let mode = ConnectionMode(rawValue: ign) { ignitionConnectionMode = mode }
        if let ppsr = dict["ppsr"], let mode = ConnectionMode(rawValue: ppsr) { ppsrConnectionMode = mode }
    }

    func vpnConfigs(for target: ProxyTarget) -> [OpenVPNConfig] {
        switch target {
        case .joe: joeVPNConfigs
        case .ignition: ignitionVPNConfigs
        case .ppsr: ppsrVPNConfigs
        }
    }

    func importVPNConfig(_ config: OpenVPNConfig, for target: ProxyTarget) {
        switch target {
        case .joe:
            guard !joeVPNConfigs.contains(where: { $0.remoteHost == config.remoteHost && $0.remotePort == config.remotePort }) else { return }
            joeVPNConfigs.append(config)
        case .ignition:
            guard !ignitionVPNConfigs.contains(where: { $0.remoteHost == config.remoteHost && $0.remotePort == config.remotePort }) else { return }
            ignitionVPNConfigs.append(config)
        case .ppsr:
            guard !ppsrVPNConfigs.contains(where: { $0.remoteHost == config.remoteHost && $0.remotePort == config.remotePort }) else { return }
            ppsrVPNConfigs.append(config)
        }
        persistVPNConfigs(for: target)
    }

    func removeVPNConfig(_ config: OpenVPNConfig, target: ProxyTarget) {
        switch target {
        case .joe: joeVPNConfigs.removeAll { $0.id == config.id }
        case .ignition: ignitionVPNConfigs.removeAll { $0.id == config.id }
        case .ppsr: ppsrVPNConfigs.removeAll { $0.id == config.id }
        }
        persistVPNConfigs(for: target)
    }

    func toggleVPNConfig(_ config: OpenVPNConfig, target: ProxyTarget, enabled: Bool) {
        switch target {
        case .joe:
            if let idx = joeVPNConfigs.firstIndex(where: { $0.id == config.id }) { joeVPNConfigs[idx].isEnabled = enabled }
        case .ignition:
            if let idx = ignitionVPNConfigs.firstIndex(where: { $0.id == config.id }) { ignitionVPNConfigs[idx].isEnabled = enabled }
        case .ppsr:
            if let idx = ppsrVPNConfigs.firstIndex(where: { $0.id == config.id }) { ppsrVPNConfigs[idx].isEnabled = enabled }
        }
        persistVPNConfigs(for: target)
    }

    func clearAllVPNConfigs(target: ProxyTarget) {
        switch target {
        case .joe: joeVPNConfigs.removeAll()
        case .ignition: ignitionVPNConfigs.removeAll()
        case .ppsr: ppsrVPNConfigs.removeAll()
        }
        persistVPNConfigs(for: target)
    }

    private func persistVPNConfigs(for target: ProxyTarget) {
        let key: String
        let configs: [OpenVPNConfig]
        switch target {
        case .joe: key = joeVPNPersistKey; configs = joeVPNConfigs
        case .ignition: key = ignitionVPNPersistKey; configs = ignitionVPNConfigs
        case .ppsr: key = ppsrVPNPersistKey; configs = ppsrVPNConfigs
        }
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadVPNConfigs() {
        if let data = UserDefaults.standard.data(forKey: joeVPNPersistKey),
           let configs = try? JSONDecoder().decode([OpenVPNConfig].self, from: data) {
            joeVPNConfigs = configs
        }
        if let data = UserDefaults.standard.data(forKey: ignitionVPNPersistKey),
           let configs = try? JSONDecoder().decode([OpenVPNConfig].self, from: data) {
            ignitionVPNConfigs = configs
        }
        if let data = UserDefaults.standard.data(forKey: ppsrVPNPersistKey),
           let configs = try? JSONDecoder().decode([OpenVPNConfig].self, from: data) {
            ppsrVPNConfigs = configs
        }
    }

    func wgConfigs(for target: ProxyTarget) -> [WireGuardConfig] {
        switch target {
        case .joe: joeWGConfigs
        case .ignition: ignitionWGConfigs
        case .ppsr: ppsrWGConfigs
        }
    }

    func importWGConfig(_ config: WireGuardConfig, for target: ProxyTarget) {
        switch target {
        case .joe:
            guard !joeWGConfigs.contains(where: { $0.peerEndpoint == config.peerEndpoint }) else { return }
            joeWGConfigs.append(config)
        case .ignition:
            guard !ignitionWGConfigs.contains(where: { $0.peerEndpoint == config.peerEndpoint }) else { return }
            ignitionWGConfigs.append(config)
        case .ppsr:
            guard !ppsrWGConfigs.contains(where: { $0.peerEndpoint == config.peerEndpoint }) else { return }
            ppsrWGConfigs.append(config)
        }
        persistWGConfigs(for: target)
    }

    func bulkImportWGConfigs(_ configs: [WireGuardConfig], for target: ProxyTarget) -> ImportReport {
        var added = 0
        var duplicates = 0
        let failed: [String] = []
        let existing = wgConfigs(for: target)
        for config in configs {
            let isDuplicate = existing.contains(where: { $0.peerEndpoint == config.peerEndpoint })
            if isDuplicate {
                duplicates += 1
            } else {
                switch target {
                case .joe: joeWGConfigs.append(config)
                case .ignition: ignitionWGConfigs.append(config)
                case .ppsr: ppsrWGConfigs.append(config)
                }
                added += 1
            }
        }
        if added > 0 { persistWGConfigs(for: target) }
        let report = ImportReport(added: added, duplicates: duplicates, failed: failed)
        lastImportReport = report
        return report
    }

    func removeWGConfig(_ config: WireGuardConfig, target: ProxyTarget) {
        switch target {
        case .joe: joeWGConfigs.removeAll { $0.id == config.id }
        case .ignition: ignitionWGConfigs.removeAll { $0.id == config.id }
        case .ppsr: ppsrWGConfigs.removeAll { $0.id == config.id }
        }
        persistWGConfigs(for: target)
    }

    func toggleWGConfig(_ config: WireGuardConfig, target: ProxyTarget, enabled: Bool) {
        switch target {
        case .joe:
            if let idx = joeWGConfigs.firstIndex(where: { $0.id == config.id }) { joeWGConfigs[idx].isEnabled = enabled }
        case .ignition:
            if let idx = ignitionWGConfigs.firstIndex(where: { $0.id == config.id }) { ignitionWGConfigs[idx].isEnabled = enabled }
        case .ppsr:
            if let idx = ppsrWGConfigs.firstIndex(where: { $0.id == config.id }) { ppsrWGConfigs[idx].isEnabled = enabled }
        }
        persistWGConfigs(for: target)
    }

    func clearAllWGConfigs(target: ProxyTarget) {
        switch target {
        case .joe: joeWGConfigs.removeAll()
        case .ignition: ignitionWGConfigs.removeAll()
        case .ppsr: ppsrWGConfigs.removeAll()
        }
        persistWGConfigs(for: target)
    }

    private func persistWGConfigs(for target: ProxyTarget) {
        let key: String
        let configs: [WireGuardConfig]
        switch target {
        case .joe: key = joeWGPersistKey; configs = joeWGConfigs
        case .ignition: key = ignitionWGPersistKey; configs = ignitionWGConfigs
        case .ppsr: key = ppsrWGPersistKey; configs = ppsrWGConfigs
        }
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadWGConfigs() {
        if let data = UserDefaults.standard.data(forKey: joeWGPersistKey),
           let configs = try? JSONDecoder().decode([WireGuardConfig].self, from: data) {
            joeWGConfigs = configs
        }
        if let data = UserDefaults.standard.data(forKey: ignitionWGPersistKey),
           let configs = try? JSONDecoder().decode([WireGuardConfig].self, from: data) {
            ignitionWGConfigs = configs
        }
        if let data = UserDefaults.standard.data(forKey: ppsrWGPersistKey),
           let configs = try? JSONDecoder().decode([WireGuardConfig].self, from: data) {
            ppsrWGConfigs = configs
        }
    }

    private func loadProxies() {
        let loaded = loadProxyList(key: persistKey)
        if !loaded.isEmpty {
            savedProxies = loaded
        } else {
            migrateFromV1()
        }
    }

    private func migrateFromV1() {
        let v1Key = "saved_socks5_proxies_v1"
        guard let data = UserDefaults.standard.data(forKey: v1Key),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        savedProxies = array.compactMap { dict -> ProxyConfig? in
            guard let host = dict["host"] as? String,
                  let port = dict["port"] as? Int else { return nil }
            var proxy = ProxyConfig(
                host: host,
                port: port,
                username: dict["username"] as? String,
                password: dict["password"] as? String
            )
            proxy.isWorking = dict["isWorking"] as? Bool ?? false
            if let ts = dict["lastTested"] as? TimeInterval {
                proxy.lastTested = Date(timeIntervalSince1970: ts)
            }
            return proxy
        }

        if !savedProxies.isEmpty {
            persistProxies()
            UserDefaults.standard.removeObject(forKey: v1Key)
        }
    }
}
