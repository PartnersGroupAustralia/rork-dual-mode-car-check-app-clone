import Foundation
import Observation
import WebKit

nonisolated enum SuperTestPhase: String, Sendable, CaseIterable, Identifiable {
    case idle = "Idle"
    case fingerprint = "Fingerprint Detection"
    case joeURLs = "Joe Fortune URLs"
    case ignitionURLs = "Ignition URLs"
    case ppsrConnection = "PPSR Connection"
    case dnsServers = "DNS Servers"
    case socks5Proxies = "SOCKS5 Proxies"
    case openvpnProfiles = "OpenVPN Profiles"
    case complete = "Complete"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .idle: "circle"
        case .fingerprint: "fingerprint"
        case .joeURLs: "suit.spade.fill"
        case .ignitionURLs: "flame.fill"
        case .ppsrConnection: "car.side.fill"
        case .dnsServers: "lock.shield.fill"
        case .socks5Proxies: "network"
        case .openvpnProfiles: "shield.lefthalf.filled"
        case .complete: "checkmark.seal.fill"
        }
    }

    var color: String {
        switch self {
        case .idle: "secondary"
        case .fingerprint: "purple"
        case .joeURLs: "green"
        case .ignitionURLs: "orange"
        case .ppsrConnection: "cyan"
        case .dnsServers: "blue"
        case .socks5Proxies: "red"
        case .openvpnProfiles: "indigo"
        case .complete: "green"
        }
    }
}

nonisolated struct SuperTestItemResult: Identifiable, Sendable {
    let id: UUID
    let name: String
    let category: SuperTestPhase
    let passed: Bool
    let latencyMs: Int?
    let detail: String
    let timestamp: Date

    init(name: String, category: SuperTestPhase, passed: Bool, latencyMs: Int? = nil, detail: String) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.passed = passed
        self.latencyMs = latencyMs
        self.detail = detail
        self.timestamp = Date()
    }
}

nonisolated struct SuperTestReport: Sendable {
    let results: [SuperTestItemResult]
    let fingerprintScore: Int?
    let fingerprintPassed: Bool
    let totalTested: Int
    let totalPassed: Int
    let totalFailed: Int
    let totalDisabled: Int
    let totalEnabled: Int
    let duration: TimeInterval
    let timestamp: Date

    var passRate: Double {
        guard totalTested > 0 else { return 0 }
        return Double(totalPassed) / Double(totalTested)
    }

    var formattedPassRate: String {
        String(format: "%.0f%%", passRate * 100)
    }

    var formattedDuration: String {
        if duration < 60 { return String(format: "%.1fs", duration) }
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return "\(mins)m \(secs)s"
    }
}

@Observable
@MainActor
class SuperTestService {
    static let shared = SuperTestService()

    var isRunning: Bool = false
    var currentPhase: SuperTestPhase = .idle
    var progress: Double = 0
    var currentItem: String = ""
    var results: [SuperTestItemResult] = []
    var logs: [PPSRLogEntry] = []
    var lastReport: SuperTestReport?
    var phaseProgress: [SuperTestPhase: (total: Int, done: Int)] = [:]

    private var testTask: Task<Void, Never>?

    private let urlRotation = LoginURLRotationService.shared
    private let proxyService = ProxyRotationService.shared
    private let dohService = PPSRDoHService.shared
    private let diagnostics = PPSRConnectionDiagnosticService.shared

    var phaseSummary: [(phase: SuperTestPhase, passed: Int, failed: Int)] {
        let phases: [SuperTestPhase] = [.fingerprint, .joeURLs, .ignitionURLs, .ppsrConnection, .dnsServers, .socks5Proxies, .openvpnProfiles]
        return phases.map { phase in
            let phaseResults = results.filter { $0.category == phase }
            let passed = phaseResults.filter(\.passed).count
            let failed = phaseResults.filter { !$0.passed }.count
            return (phase, passed, failed)
        }
    }

    func startSuperTest() {
        guard !isRunning else { return }

        isRunning = true
        currentPhase = .idle
        progress = 0
        results.removeAll()
        logs.removeAll()
        phaseProgress.removeAll()
        currentItem = ""

        addLog("SUPER TEST — Starting comprehensive infrastructure test")

        let startTime = Date()

        testTask = Task {
            await runFingerprintTest()
            if Task.isCancelled { finalize(startTime: startTime); return }

            await runJoeURLTests()
            if Task.isCancelled { finalize(startTime: startTime); return }

            await runIgnitionURLTests()
            if Task.isCancelled { finalize(startTime: startTime); return }

            await runPPSRConnectionTest()
            if Task.isCancelled { finalize(startTime: startTime); return }

            await runDNSServerTests()
            if Task.isCancelled { finalize(startTime: startTime); return }

            await runSOCKS5ProxyTests()
            if Task.isCancelled { finalize(startTime: startTime); return }

            await runOpenVPNProfileTests()

            finalize(startTime: startTime)
        }
    }

    func stopSuperTest() {
        testTask?.cancel()
        testTask = nil
        isRunning = false
        currentPhase = .idle
        currentItem = ""
        addLog("SUPER TEST — Stopped by user", level: .warning)
    }

    private func finalize(startTime: Date) {
        let duration = Date().timeIntervalSince(startTime)
        let totalTested = results.count
        let totalPassed = results.filter(\.passed).count
        let totalFailed = results.filter { !$0.passed }.count

        let fingerprintResults = results.filter { $0.category == .fingerprint }
        let fpScore = fingerprintResults.first.flatMap(\.latencyMs)
        let fpPassed = fingerprintResults.first?.passed ?? false

        let disabledCount = countDisabledItems()
        let enabledCount = countEnabledItems()

        lastReport = SuperTestReport(
            results: results,
            fingerprintScore: fpScore,
            fingerprintPassed: fpPassed,
            totalTested: totalTested,
            totalPassed: totalPassed,
            totalFailed: totalFailed,
            totalDisabled: disabledCount,
            totalEnabled: enabledCount,
            duration: duration,
            timestamp: Date()
        )

        currentPhase = .complete
        progress = 1.0
        currentItem = ""
        isRunning = false

        addLog("SUPER TEST COMPLETE — \(totalPassed)/\(totalTested) passed, \(totalFailed) failed, \(disabledCount) auto-disabled, \(enabledCount) auto-enabled in \(lastReport!.formattedDuration)", level: .success)
    }

    private func countDisabledItems() -> Int {
        results.filter { !$0.passed }.count
    }

    private func countEnabledItems() -> Int {
        results.filter(\.passed).count
    }

    // MARK: - Fingerprint Detection Test

    private func runFingerprintTest() async {
        currentPhase = .fingerprint
        currentItem = "Fingerprint.com Detection Test"
        phaseProgress[.fingerprint] = (total: 2, done: 0)
        addLog("Phase 1: Fingerprint & Headless Detection")

        let webViewScore = await runWebViewFingerprintTest()
        phaseProgress[.fingerprint] = (total: 2, done: 1)

        let headlessScore = await runHeadlessDetectionTest()
        phaseProgress[.fingerprint] = (total: 2, done: 2)

        let avgScore = (webViewScore + headlessScore) / 2
        let passed = avgScore <= FingerprintValidationService.maxAcceptableScore

        results.append(SuperTestItemResult(
            name: "WebView Fingerprint Score",
            category: .fingerprint,
            passed: webViewScore <= FingerprintValidationService.maxAcceptableScore,
            latencyMs: webViewScore,
            detail: "Score: \(webViewScore)/\(FingerprintValidationService.maxAcceptableScore) — \(webViewScore <= FingerprintValidationService.maxAcceptableScore ? "CLEAN" : "DETECTED")"
        ))

        results.append(SuperTestItemResult(
            name: "Headless/Bot Detection",
            category: .fingerprint,
            passed: headlessScore <= FingerprintValidationService.maxAcceptableScore,
            latencyMs: headlessScore,
            detail: "Score: \(headlessScore)/\(FingerprintValidationService.maxAcceptableScore) — \(headlessScore <= FingerprintValidationService.maxAcceptableScore ? "CLEAN" : "DETECTED")"
        ))

        addLog("Fingerprint: WebView=\(webViewScore), Headless=\(headlessScore), Overall: \(passed ? "PASS" : "FAIL")", level: passed ? .success : .error)
        updateProgress(0.15)
    }

    private func runWebViewFingerprintTest() async -> Int {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 414, height: 896), configuration: config)

        let request = URLRequest(url: URL(string: "about:blank")!)
        webView.load(request)
        try? await Task.sleep(for: .milliseconds(500))

        let fpService = FingerprintValidationService.shared
        let score = await fpService.validate(in: webView, profileSeed: UInt32.random(in: 0...UInt32.max))
        return score.totalScore
    }

    private func runHeadlessDetectionTest() async -> Int {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 414, height: 896), configuration: config)

        let request = URLRequest(url: URL(string: "about:blank")!)
        webView.load(request)
        try? await Task.sleep(for: .milliseconds(500))

        let headlessJS = """
        (function() {
            var score = 0;
            var signals = [];
            try { if (navigator.webdriver) { score += 7; signals.push('webdriver'); } } catch(e) {}
            try { if (!window.chrome && navigator.userAgent.indexOf('Chrome') !== -1) { score += 5; signals.push('chrome_mismatch'); } } catch(e) {}
            try { if (navigator.languages === undefined || navigator.languages.length === 0) { score += 4; signals.push('no_languages'); } } catch(e) {}
            try { if (navigator.plugins === undefined || navigator.plugins.length === 0) { score += 2; signals.push('no_plugins'); } } catch(e) {}
            try {
                var c = document.createElement('canvas');
                var gl = c.getContext('webgl');
                if (!gl) { score += 3; signals.push('no_webgl'); }
            } catch(e) {}
            try { if (navigator.permissions) {
                // sync check only
            }} catch(e) {}
            try {
                var autoFlags = ['__nightmare', '_phantom', 'callPhantom', '__selenium_evaluate', '__webdriver_evaluate'];
                for (var i = 0; i < autoFlags.length; i++) {
                    if (window[autoFlags[i]] !== undefined) { score += 7; signals.push('auto_flag:' + autoFlags[i]); break; }
                }
            } catch(e) {}
            return JSON.stringify({score: score, signals: signals});
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(headlessJS)
            if let str = result as? String,
               let data = str.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let score = json["score"] as? Int {
                return score
            }
        } catch {}

        return 0
    }

    // MARK: - Joe Fortune URL Tests

    private func runJoeURLTests() async {
        currentPhase = .joeURLs
        let urls = urlRotation.joeURLs
        let total = urls.count
        phaseProgress[.joeURLs] = (total: total, done: 0)
        addLog("Phase 2: Testing \(total) Joe Fortune URLs")

        for (index, rotatingURL) in urls.enumerated() {
            if Task.isCancelled { return }
            currentItem = rotatingURL.host
            let result = await pingURL(rotatingURL.urlString, name: rotatingURL.host, category: .joeURLs)
            results.append(result)

            if result.passed {
                urlRotation.toggleURL(id: rotatingURL.id, enabled: true)
            } else {
                urlRotation.toggleURL(id: rotatingURL.id, enabled: false)
                addLog("Auto-disabled Joe URL: \(rotatingURL.host)", level: .warning)
            }

            phaseProgress[.joeURLs] = (total: total, done: index + 1)
        }

        let passed = results.filter { $0.category == .joeURLs && $0.passed }.count
        addLog("Joe URLs: \(passed)/\(total) passed", level: passed > 0 ? .success : .error)
        updateProgress(0.30)
    }

    // MARK: - Ignition URL Tests

    private func runIgnitionURLTests() async {
        currentPhase = .ignitionURLs
        let urls = urlRotation.ignitionURLs
        let total = urls.count
        phaseProgress[.ignitionURLs] = (total: total, done: 0)
        addLog("Phase 3: Testing \(total) Ignition URLs")

        for (index, rotatingURL) in urls.enumerated() {
            if Task.isCancelled { return }
            currentItem = rotatingURL.host
            let result = await pingURL(rotatingURL.urlString, name: rotatingURL.host, category: .ignitionURLs)
            results.append(result)

            if result.passed {
                urlRotation.toggleURL(id: rotatingURL.id, enabled: true)
            } else {
                urlRotation.toggleURL(id: rotatingURL.id, enabled: false)
                addLog("Auto-disabled Ignition URL: \(rotatingURL.host)", level: .warning)
            }

            phaseProgress[.ignitionURLs] = (total: total, done: index + 1)
        }

        let passed = results.filter { $0.category == .ignitionURLs && $0.passed }.count
        addLog("Ignition URLs: \(passed)/\(total) passed", level: passed > 0 ? .success : .error)
        updateProgress(0.45)
    }

    // MARK: - PPSR Connection Test

    private func runPPSRConnectionTest() async {
        currentPhase = .ppsrConnection
        currentItem = "transact.ppsr.gov.au"
        phaseProgress[.ppsrConnection] = (total: 3, done: 0)
        addLog("Phase 4: Testing PPSR Connection")

        let healthCheck = await diagnostics.quickHealthCheck()
        phaseProgress[.ppsrConnection] = (total: 3, done: 1)

        results.append(SuperTestItemResult(
            name: "PPSR Health Check",
            category: .ppsrConnection,
            passed: healthCheck.healthy,
            detail: healthCheck.detail
        ))

        let dnsAnswer = await dohService.resolveWithRotation(hostname: "transact.ppsr.gov.au")
        phaseProgress[.ppsrConnection] = (total: 3, done: 2)

        results.append(SuperTestItemResult(
            name: "PPSR DNS Resolution",
            category: .ppsrConnection,
            passed: dnsAnswer != nil,
            latencyMs: dnsAnswer?.latencyMs,
            detail: dnsAnswer != nil ? "Resolved via \(dnsAnswer!.provider) → \(dnsAnswer!.ip)" : "DNS resolution failed"
        ))

        let sslResult = await testSSL("transact.ppsr.gov.au")
        phaseProgress[.ppsrConnection] = (total: 3, done: 3)

        results.append(SuperTestItemResult(
            name: "PPSR SSL/TLS",
            category: .ppsrConnection,
            passed: sslResult.0,
            latencyMs: sslResult.1,
            detail: sslResult.2
        ))

        let passed = results.filter { $0.category == .ppsrConnection && $0.passed }.count
        addLog("PPSR: \(passed)/3 checks passed", level: passed == 3 ? .success : (passed > 0 ? .warning : .error))
        updateProgress(0.55)
    }

    // MARK: - DNS Server Tests

    private func runDNSServerTests() async {
        currentPhase = .dnsServers
        let providers = dohService.managedProviders
        let total = providers.count
        phaseProgress[.dnsServers] = (total: total, done: 0)
        addLog("Phase 5: Testing \(total) DNS Servers")

        for (index, provider) in providers.enumerated() {
            if Task.isCancelled { return }
            currentItem = provider.name

            let dohProvider = DoHProvider(name: provider.name, url: provider.url)
            let answer = await dohService.resolve(hostname: "transact.ppsr.gov.au", using: dohProvider)
            let passed = answer != nil

            results.append(SuperTestItemResult(
                name: provider.name,
                category: .dnsServers,
                passed: passed,
                latencyMs: answer?.latencyMs,
                detail: passed ? "Resolved → \(answer!.ip) in \(answer!.latencyMs)ms" : "Resolution failed"
            ))

            dohService.toggleProvider(id: provider.id, enabled: passed)
            if !passed {
                addLog("Auto-disabled DNS: \(provider.name)", level: .warning)
            }

            phaseProgress[.dnsServers] = (total: total, done: index + 1)
        }

        let passedCount = results.filter { $0.category == .dnsServers && $0.passed }.count
        addLog("DNS Servers: \(passedCount)/\(total) passed", level: passedCount > 0 ? .success : .error)
        updateProgress(0.70)
    }

    // MARK: - SOCKS5 Proxy Tests

    private func runSOCKS5ProxyTests() async {
        currentPhase = .socks5Proxies
        let allProxies: [(proxy: ProxyConfig, target: ProxyRotationService.ProxyTarget)] =
            proxyService.savedProxies.map { ($0, .joe) } +
            proxyService.ignitionProxies.map { ($0, .ignition) } +
            proxyService.ppsrProxies.map { ($0, .ppsr) }

        let total = allProxies.count
        phaseProgress[.socks5Proxies] = (total: total, done: 0)
        addLog("Phase 6: Testing \(total) SOCKS5 Proxies")

        if total == 0 {
            addLog("No SOCKS5 proxies configured — skipping", level: .warning)
            updateProgress(0.85)
            return
        }

        let maxConcurrent = 5
        var index = 0

        await withTaskGroup(of: (ProxyConfig, ProxyRotationService.ProxyTarget, Bool, Int).self) { group in
            var launched = 0

            for (proxy, target) in allProxies {
                if Task.isCancelled { return }

                if launched >= maxConcurrent {
                    if let result = await group.next() {
                        processProxyResult(result)
                        index += 1
                        phaseProgress[.socks5Proxies] = (total: total, done: index)
                    }
                }

                currentItem = proxy.displayString
                group.addTask {
                    let (passed, latency) = await self.testProxy(proxy)
                    return (proxy, target, passed, latency)
                }
                launched += 1
            }

            for await result in group {
                processProxyResult(result)
                index += 1
                phaseProgress[.socks5Proxies] = (total: total, done: index)
            }
        }

        let passedCount = results.filter { $0.category == .socks5Proxies && $0.passed }.count
        addLog("SOCKS5 Proxies: \(passedCount)/\(total) passed", level: passedCount > 0 ? .success : .error)
        updateProgress(0.85)
    }

    private func processProxyResult(_ result: (ProxyConfig, ProxyRotationService.ProxyTarget, Bool, Int)) {
        let (proxy, target, passed, latency) = result
        let targetLabel: String
        switch target {
        case .joe: targetLabel = "Joe"
        case .ignition: targetLabel = "Ignition"
        case .ppsr: targetLabel = "PPSR"
        }

        results.append(SuperTestItemResult(
            name: "\(proxy.displayString) [\(targetLabel)]",
            category: .socks5Proxies,
            passed: passed,
            latencyMs: passed ? latency : nil,
            detail: passed ? "Connected in \(latency)ms" : "Connection failed"
        ))

        if passed {
            proxyService.markProxyWorking(proxy)
        } else {
            proxyService.markProxyFailed(proxy)
            addLog("Auto-failed proxy: \(proxy.displayString) [\(targetLabel)]", level: .warning)
        }
    }

    // MARK: - OpenVPN Profile Tests

    private func runOpenVPNProfileTests() async {
        currentPhase = .openvpnProfiles
        let allVPN: [(config: OpenVPNConfig, target: ProxyRotationService.ProxyTarget)] =
            proxyService.joeVPNConfigs.map { ($0, .joe) } +
            proxyService.ignitionVPNConfigs.map { ($0, .ignition) } +
            proxyService.ppsrVPNConfigs.map { ($0, .ppsr) }

        let total = allVPN.count
        phaseProgress[.openvpnProfiles] = (total: total, done: 0)
        addLog("Phase 7: Testing \(total) OpenVPN Profiles")

        if total == 0 {
            addLog("No OpenVPN profiles configured — skipping", level: .warning)
            updateProgress(0.95)
            return
        }

        for (index, (vpnConfig, target)) in allVPN.enumerated() {
            if Task.isCancelled { return }

            let targetLabel: String
            switch target {
            case .joe: targetLabel = "Joe"
            case .ignition: targetLabel = "Ignition"
            case .ppsr: targetLabel = "PPSR"
            }

            currentItem = vpnConfig.displayString
            let (passed, latency) = await testVPNHost(vpnConfig)

            results.append(SuperTestItemResult(
                name: "\(vpnConfig.displayString) [\(targetLabel)]",
                category: .openvpnProfiles,
                passed: passed,
                latencyMs: passed ? latency : nil,
                detail: passed ? "Host reachable in \(latency)ms" : "Host unreachable"
            ))

            proxyService.toggleVPNConfig(vpnConfig, target: target, enabled: passed)
            if !passed {
                addLog("Auto-disabled VPN: \(vpnConfig.fileName) [\(targetLabel)]", level: .warning)
            }

            phaseProgress[.openvpnProfiles] = (total: total, done: index + 1)
        }

        let passedCount = results.filter { $0.category == .openvpnProfiles && $0.passed }.count
        addLog("OpenVPN: \(passedCount)/\(total) passed", level: passedCount > 0 ? .success : .error)
        updateProgress(0.95)
    }

    // MARK: - Utility Methods

    private func pingURL(_ urlString: String, name: String, category: SuperTestPhase) async -> SuperTestItemResult {
        guard let url = URL(string: urlString) else {
            return SuperTestItemResult(name: name, category: category, passed: false, detail: "Invalid URL")
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 12)
        request.httpMethod = "HEAD"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let start = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            if let http = response as? HTTPURLResponse {
                let passed = http.statusCode >= 200 && http.statusCode < 400
                return SuperTestItemResult(
                    name: name,
                    category: category,
                    passed: passed,
                    latencyMs: latency,
                    detail: "HTTP \(http.statusCode) in \(latency)ms"
                )
            }
            return SuperTestItemResult(name: name, category: category, passed: true, latencyMs: latency, detail: "Response in \(latency)ms")
        } catch {
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            return SuperTestItemResult(name: name, category: category, passed: false, latencyMs: latency, detail: error.localizedDescription)
        }
    }

    private nonisolated func testProxy(_ proxy: ProxyConfig) async -> (Bool, Int) {
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

        let start = Date()
        let testURLs = ["https://api.ipify.org?format=json", "https://httpbin.org/ip"]

        for urlString in testURLs {
            guard let url = URL(string: urlString) else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                    let latency = Int(Date().timeIntervalSince(start) * 1000)
                    return (true, latency)
                }
            } catch {
                continue
            }
        }
        return (false, 0)
    }

    private func testSSL(_ host: String) async -> (Bool, Int, String) {
        let start = Date()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 12
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: URL(string: "https://\(host)")!)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await session.data(for: request)
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            if let http = response as? HTTPURLResponse {
                return (true, latency, "TLS OK (HTTP \(http.statusCode)) in \(latency)ms")
            }
            return (true, latency, "TLS handshake OK in \(latency)ms")
        } catch {
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            return (false, latency, "SSL failed: \(error.localizedDescription)")
        }
    }

    private func testVPNHost(_ vpnConfig: OpenVPNConfig) async -> (Bool, Int) {
        let host = vpnConfig.remoteHost
        let port = vpnConfig.remotePort

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let start = Date()

        guard let url = URL(string: "https://\(host):\(port)") else {
            let altURL = URL(string: "https://\(host)")!
            do {
                var request = URLRequest(url: altURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 8)
                request.httpMethod = "HEAD"
                let (_, response) = try await session.data(for: request)
                let latency = Int(Date().timeIntervalSince(start) * 1000)
                if let http = response as? HTTPURLResponse {
                    return (http.statusCode < 500, latency)
                }
                return (true, latency)
            } catch {
                return (false, 0)
            }
        }

        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 8)
            request.httpMethod = "HEAD"
            let _ = try await session.data(for: request)
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            return (true, latency)
        } catch let error as NSError {
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorSecureConnectionFailed {
                let latency = Int(Date().timeIntervalSince(start) * 1000)
                return (true, latency)
            }
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCannotConnectToHost {
                return (false, 0)
            }
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            return (latency < 7000, latency)
        }
    }

    private func updateProgress(_ value: Double) {
        progress = value
    }

    private func addLog(_ message: String, level: PPSRLogEntry.Level = .info) {
        logs.insert(PPSRLogEntry(message: message, level: level), at: 0)
        if logs.count > 500 { logs = Array(logs.prefix(500)) }
    }
}
