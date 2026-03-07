import SwiftUI
import UniformTypeIdentifiers

struct PPSRNetworkSettingsView: View {
    @Bindable var vm: PPSRAutomationViewModel
    @State private var showDNSManager: Bool = false
    @State private var showPPSRProxyImport: Bool = false
    @State private var ppsrProxyBulkText: String = ""
    @State private var ppsrProxyImportReport: ProxyRotationService.ImportReport?
    @State private var isTestingPPSRProxies: Bool = false
    @State private var showPPSRVPNFileImporter: Bool = false
    @State private var showPPSRWGFileImporter: Bool = false
    @State private var nordAccessKeyInput: String = ""
    @State private var isEditingNordKey: Bool = false
    @State private var isTestingVPNConfigs: Bool = false

    private let proxyService = ProxyRotationService.shared
    private let nordService = NordVPNService.shared

    var body: some View {
        List {
            connectionModeSection
            nordVPNSection
            endpointSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Networks")
        .sheet(isPresented: $showDNSManager) { dnsManagerSheet }
        .sheet(isPresented: $showPPSRProxyImport) { ppsrProxyImportSheet }
        .fileImporter(isPresented: $showPPSRVPNFileImporter, allowedContentTypes: [.data, .plainText], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                var imported = 0
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url),
                       let content = String(data: data, encoding: .utf8) {
                        let fileName = url.lastPathComponent
                        if let config = OpenVPNConfig.parse(fileName: fileName, content: content) {
                            proxyService.importVPNConfig(config, for: .ppsr)
                            imported += 1
                        } else {
                            vm.log("Failed to parse: \(fileName)", level: .warning)
                        }
                    }
                }
                if imported > 0 {
                    vm.log("Imported \(imported) PPSR OpenVPN config(s)", level: .success)
                }
            case .failure(let error):
                vm.log("VPN import error: \(error.localizedDescription)", level: .error)
            }
        }
        .fileImporter(isPresented: $showPPSRWGFileImporter, allowedContentTypes: [.data, .plainText], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                var parsed: [WireGuardConfig] = []
                var failedFiles: [String] = []
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else {
                        failedFiles.append(url.lastPathComponent)
                        continue
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url),
                       let content = String(data: data, encoding: .utf8) {
                        let fileName = url.lastPathComponent
                        let configs = WireGuardConfig.parseMultiple(fileName: fileName, content: content)
                        if configs.isEmpty {
                            if let single = WireGuardConfig.parse(fileName: fileName, content: content) {
                                parsed.append(single)
                            } else {
                                failedFiles.append(fileName)
                            }
                        } else {
                            parsed.append(contentsOf: configs)
                        }
                    } else {
                        failedFiles.append(url.lastPathComponent)
                    }
                }
                if !parsed.isEmpty {
                    let report = proxyService.bulkImportWGConfigs(parsed, for: .ppsr)
                    vm.log("WireGuard import: \(report.added) added, \(report.duplicates) duplicates", level: .success)
                }
                for name in failedFiles {
                    vm.log("Failed to parse WireGuard: \(name)", level: .warning)
                }
            case .failure(let error):
                vm.log("WireGuard import error: \(error.localizedDescription)", level: .error)
            }
        }
    }

    // MARK: - Connection Mode

    private var connectionModeSection: some View {
        let currentMode = proxyService.connectionMode(for: .ppsr)
        let proxyList = proxyService.proxies(for: .ppsr)
        return Section {
            Picker(selection: Binding(
                get: { proxyService.connectionMode(for: .ppsr) },
                set: { newMode in
                    withAnimation(.spring(duration: 0.3)) {
                        proxyService.setConnectionMode(newMode, for: .ppsr)
                    }
                    vm.log("PPSR switched to \(newMode.label) mode", level: .success)
                }
            )) {
                ForEach(ConnectionMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.shield.fill").foregroundStyle(.blue)
                    Text("PPSR Connection")
                }
            }
            .pickerStyle(.menu)
            .sensoryFeedback(.impact(weight: .medium), trigger: currentMode)

            if currentMode == .proxy {
                HStack(spacing: 10) {
                    Image(systemName: "network").foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PPSR Proxies").font(.body)
                        Text("\(proxyList.count) proxies loaded").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    proxyStatusBadge(proxies: proxyList)
                }

                Button { showPPSRProxyImport = true } label: {
                    Label("Import Proxies", systemImage: "doc.on.clipboard.fill")
                }

                if !proxyList.isEmpty {
                    Button {
                        guard !isTestingPPSRProxies else { return }
                        isTestingPPSRProxies = true
                        Task {
                            vm.log("Testing all \(proxyList.count) PPSR proxies...")
                            await proxyService.testAllProxies(target: .ppsr)
                            let working = proxyService.proxies(for: .ppsr).filter(\.isWorking).count
                            vm.log("PPSR proxy test: \(working)/\(proxyList.count) working", level: .success)
                            isTestingPPSRProxies = false
                        }
                    } label: {
                        HStack {
                            Label("Test Proxies", systemImage: "antenna.radiowaves.left.and.right")
                            if isTestingPPSRProxies { Spacer(); ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isTestingPPSRProxies)

                    Button {
                        let exported = proxyService.exportProxies(target: .ppsr)
                        UIPasteboard.general.string = exported
                        vm.log("Exported \(proxyList.count) PPSR proxies to clipboard", level: .success)
                    } label: {
                        Label("Export to Clipboard", systemImage: "doc.on.doc")
                    }

                    let deadCount = proxyList.filter({ !$0.isWorking && $0.lastTested != nil }).count
                    if deadCount > 0 {
                        Button(role: .destructive) {
                            proxyService.removeDead(target: .ppsr)
                            vm.log("Removed \(deadCount) dead PPSR proxies")
                        } label: {
                            Label("Remove \(deadCount) Dead", systemImage: "xmark.circle")
                        }
                    }

                    ForEach(proxyList) { proxy in
                        ppsrProxyRow(proxy: proxy)
                    }

                    Button {
                        proxyService.resetAllStatus(target: .ppsr)
                        vm.log("Reset all PPSR proxy statuses")
                    } label: {
                        Label("Reset All Status", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        proxyService.removeAll(target: .ppsr)
                        vm.log("Cleared all PPSR proxies")
                    } label: {
                        Label("Clear All Proxies", systemImage: "trash")
                    }
                }
            } else if currentMode == .openvpn {
                let vpnList = proxyService.vpnConfigs(for: .ppsr)
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PPSR OpenVPN").font(.body)
                        Text("\(vpnList.count) configs loaded").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    let enabledCount = vpnList.filter(\.isEnabled).count
                    if enabledCount > 0 {
                        Text("\(enabledCount) active")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.indigo.opacity(0.12)).clipShape(Capsule())
                    }
                }

                Button { showPPSRVPNFileImporter = true } label: {
                    Label("Import .ovpn File", systemImage: "doc.badge.plus")
                }

                if !vpnList.isEmpty {
                    ForEach(vpnList) { vpn in
                        HStack(spacing: 8) {
                            Image(systemName: vpn.isEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(vpn.isEnabled ? .indigo : .secondary)
                                .onTapGesture {
                                    proxyService.toggleVPNConfig(vpn, target: .ppsr, enabled: !vpn.isEnabled)
                                }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(vpn.fileName)
                                    .font(.system(.caption, design: .monospaced, weight: .medium)).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(vpn.displayString)
                                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                                    Text(vpn.statusLabel)
                                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                                        .foregroundStyle(vpn.isReachable ? .green : (vpn.lastTested != nil ? .red : .gray))
                                }
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                proxyService.removeVPNConfig(vpn, target: .ppsr)
                                vm.log("Removed VPN: \(vpn.fileName)")
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }

                    Button(role: .destructive) {
                        proxyService.clearAllVPNConfigs(target: .ppsr)
                        vm.log("Cleared all PPSR OpenVPN configs")
                    } label: {
                        Label("Clear All Configs", systemImage: "trash")
                    }
                }
            } else if currentMode == .wireguard {
                let wgList = proxyService.wgConfigs(for: .ppsr)
                HStack(spacing: 10) {
                    Image(systemName: "lock.trianglebadge.exclamationmark.fill").foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PPSR WireGuard").font(.body)
                        Text("\(wgList.count) configs loaded").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    let enabledCount = wgList.filter(\.isEnabled).count
                    if enabledCount > 0 {
                        Text("\(enabledCount) active")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.purple.opacity(0.12)).clipShape(Capsule())
                    }
                }

                Button { showPPSRWGFileImporter = true } label: {
                    Label("Import .conf Files", systemImage: "doc.badge.plus")
                }

                if !wgList.isEmpty {
                    ForEach(wgList) { wg in
                        HStack(spacing: 8) {
                            Image(systemName: wg.isEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(wg.isEnabled ? .purple : .secondary)
                                .onTapGesture {
                                    proxyService.toggleWGConfig(wg, target: .ppsr, enabled: !wg.isEnabled)
                                }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(wg.fileName)
                                    .font(.system(.caption, design: .monospaced, weight: .medium)).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(wg.displayString)
                                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                                    Text(wg.statusLabel)
                                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                                        .foregroundStyle(wg.isReachable ? .green : (wg.lastTested != nil ? .red : .gray))
                                }
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                proxyService.removeWGConfig(wg, target: .ppsr)
                                vm.log("Removed WireGuard: \(wg.fileName)")
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }

                    Button {
                        Task { await proxyService.testAllWGConfigs(target: .ppsr) }
                    } label: {
                        Label("Test All WireGuard", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    Button(role: .destructive) {
                        proxyService.clearAllWGConfigs(target: .ppsr)
                        vm.log("Cleared all PPSR WireGuard configs")
                    } label: {
                        Label("Clear All Configs", systemImage: "trash")
                    }
                }
            } else {
                let enabled = PPSRDoHService.shared.managedProviders.filter(\.isEnabled).count
                let total = PPSRDoHService.shared.managedProviders.count
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DoH DNS Rotation").font(.body)
                        Text("\(enabled)/\(total) providers enabled · rotates each test").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }

                Button { showDNSManager = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "server.rack").foregroundStyle(.cyan)
                        Text("Manage DNS Servers")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        } header: {
            HStack {
                Text("PPSR Connection")
                Spacer()
                Text(currentMode.label)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(ppsrConnectionModeColor(currentMode))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(ppsrConnectionModeColor(currentMode).opacity(0.12))
                    .clipShape(Capsule())
            }
        } footer: {
            switch currentMode {
            case .proxy: Text("PPSR uses SOCKS5 proxies for all connections.")
            case .openvpn: Text("PPSR uses OpenVPN configs. Import .ovpn files to connect.")
            case .wireguard: Text("PPSR uses WireGuard configs. Import NordVPN .conf files to connect.")
            case .dns: Text("PPSR uses DoH DNS rotation for connections.")
            }
        }
    }

    // MARK: - NordVPN

    private var nordVPNSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "shield.checkered").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NordVPN Integration").font(.body)
                    Text(nordService.hasAccessKey ? "Access key configured" : "No access key")
                        .font(.caption2)
                        .foregroundStyle(nordService.hasAccessKey ? .green : .secondary)
                }
                Spacer()
                if nordService.hasPrivateKey {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption)
                }
            }

            if !nordService.hasAccessKey || isEditingNordKey {
                HStack {
                    SecureField("Nord Access Key", text: $nordAccessKeyInput)
                        .font(.system(.caption, design: .monospaced))
                        .textContentType(.password)
                    Button("Save") {
                        nordService.setAccessKey(nordAccessKeyInput)
                        nordAccessKeyInput = ""
                        isEditingNordKey = false
                    }
                    .disabled(nordAccessKeyInput.isEmpty)
                    if isEditingNordKey {
                        Button("Cancel") {
                            nordAccessKeyInput = ""
                            isEditingNordKey = false
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    isEditingNordKey = true
                } label: {
                    Label("Change Access Key", systemImage: "key.horizontal")
                }
                .foregroundStyle(.orange)

                if !nordService.hasPrivateKey {
                    Button {
                        Task { await nordService.fetchPrivateKey() }
                    } label: {
                        HStack {
                            if nordService.isLoadingKey { ProgressView().controlSize(.small) }
                            Label("Fetch WireGuard Private Key", systemImage: "key.fill")
                        }
                    }
                    .disabled(nordService.isLoadingKey)
                }

                Button {
                    Task { await nordService.fetchRecommendedServers(limit: 10, technology: "openvpn_tcp") }
                } label: {
                    HStack {
                        if nordService.isLoadingServers { ProgressView().controlSize(.small) }
                        Label("Fetch TCP Servers", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(nordService.isLoadingServers)

                if !nordService.recommendedServers.isEmpty {
                    Button {
                        guard !nordService.isDownloadingOVPN else { return }
                        Task {
                            let result = await nordService.downloadAllTCPConfigs(for: nordService.recommendedServers, target: .ppsr)
                            vm.log("NordVPN TCP: \(result.imported) imported, \(result.failed) failed \u{2192} PPSR", level: result.imported > 0 ? .success : .error)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if nordService.isDownloadingOVPN {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.doc.fill").foregroundStyle(.indigo)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Download All TCP .ovpn \u{2192} PPSR").font(.subheadline.bold())
                                Text(nordService.isDownloadingOVPN ? "Downloading \(nordService.ovpnDownloadProgress)..." : "\(nordService.recommendedServers.count) servers available")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .disabled(nordService.isDownloadingOVPN)

                    ForEach(nordService.recommendedServers, id: \.id) { server in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(server.hostname)
                                    .font(.system(.caption, design: .monospaced, weight: .medium))
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if let city = server.city {
                                        Text(city).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Text("Load: \(server.load)%")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(server.load < 30 ? .green : (server.load < 70 ? .orange : .red))
                                }
                            }
                            Spacer()
                            Menu {
                                Button {
                                    Task {
                                        if let config = await nordService.downloadOVPNConfig(from: server, proto: .tcp) {
                                            proxyService.importVPNConfig(config, for: .ppsr)
                                            vm.log("Imported TCP .ovpn [PPSR]: \(server.hostname)", level: .success)
                                        } else {
                                            vm.log("Failed to download .ovpn: \(server.hostname)", level: .error)
                                        }
                                    }
                                } label: { Label("TCP .ovpn \u{2192} PPSR", systemImage: "shield.lefthalf.filled") }
                                if nordService.hasPrivateKey, let _ = server.publicKey {
                                    Divider()
                                    Button {
                                        if let wgConfig = nordService.generateWireGuardConfig(from: server) {
                                            proxyService.importWGConfig(wgConfig, for: .ppsr)
                                            vm.log("Imported WG [PPSR]: \(server.hostname)", level: .success)
                                        }
                                    } label: { Label("WG \u{2192} PPSR", systemImage: "lock.fill") }
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
                            }
                        }
                    }
                }

                Button(role: .destructive) {
                    nordService.setAccessKey("")
                    nordService.setPrivateKey("")
                    nordService.recommendedServers.removeAll()
                } label: {
                    Label("Remove Access Key", systemImage: "trash")
                }
            }

            if let error = nordService.lastError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }

            let currentMode = proxyService.connectionMode(for: .ppsr)
            if currentMode == .openvpn {
                let vpnList = proxyService.vpnConfigs(for: .ppsr)
                if !vpnList.isEmpty {
                    Button {
                        guard !isTestingVPNConfigs else { return }
                        isTestingVPNConfigs = true
                        Task {
                            await proxyService.testAllVPNConfigs(target: .ppsr)
                            let reachable = proxyService.vpnConfigs(for: .ppsr).filter(\.isReachable).count
                            vm.log("OpenVPN test: \(reachable)/\(vpnList.count) reachable", level: .success)
                            isTestingVPNConfigs = false
                        }
                    } label: {
                        HStack {
                            Label("Test All OpenVPN", systemImage: "antenna.radiowaves.left.and.right")
                            if isTestingVPNConfigs { Spacer(); ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isTestingVPNConfigs)
                }
            }
        } header: {
            Text("NordVPN")
        } footer: {
            Text("Fetches recommended TCP OpenVPN servers from NordVPN and downloads real .ovpn config files for import.")
        }
    }

    // MARK: - Endpoint

    private var endpointSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Target") {
                    HStack(spacing: 4) {
                        Circle().fill(endpointColor).frame(width: 6, height: 6)
                        Text(vm.connectionStatus == .connected ? "Live Production" : vm.connectionStatus.rawValue)
                            .font(.system(.body, design: .monospaced)).foregroundStyle(endpointColor)
                    }
                }
                LabeledContent("URL") { Text("transact.ppsr.gov.au/CarCheck/").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
                LabeledContent("Cost") { Text("$2.00 per check").foregroundStyle(.orange) }
                LabeledContent("Timeout") { Text("\(Int(vm.testTimeout))s per test").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
            }

            Button {
                Task { await vm.testConnection() }
            } label: {
                HStack {
                    if vm.connectionStatus == .connecting { ProgressView().controlSize(.small) }
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text(vm.connectionStatus == .connecting ? "Testing..." : "Test Connection")
                }
            }
            .disabled(vm.connectionStatus == .connecting)

            Button {
                Task { await vm.runFullDiagnostic() }
            } label: {
                HStack {
                    if vm.isDiagnosticRunning { ProgressView().controlSize(.small) }
                    Image(systemName: "stethoscope").foregroundStyle(.cyan)
                    Text(vm.isDiagnosticRunning ? "Running Diagnostics..." : "Full Connection Diagnostic")
                }
            }
            .disabled(vm.isDiagnosticRunning)

            if let report = vm.diagnosticReport {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.steps) { step in
                        HStack(spacing: 6) {
                            Image(systemName: diagnosticStepIcon(step.status)).font(.caption2).foregroundStyle(diagnosticStepColor(step.status)).frame(width: 14)
                            Text(step.name).font(.system(.caption2, design: .monospaced, weight: .semibold))
                            Spacer()
                            if let ms = step.latencyMs { Text("\(ms)ms").font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary) }
                            Text(step.status.rawValue).font(.system(.caption2, design: .monospaced, weight: .bold)).foregroundStyle(diagnosticStepColor(step.status))
                        }
                    }
                }
                Text(report.recommendation).font(.caption2).foregroundStyle(report.overallHealthy ? .green : .orange)
            }
        } header: {
            Text("Live Endpoint")
        } footer: {
            if let health = vm.lastHealthCheck {
                Text("Last check: \(health.healthy ? "Healthy" : "Unhealthy") — \(health.detail)")
            }
        }
    }

    private var endpointColor: Color {
        switch vm.connectionStatus {
        case .connected: .green; case .connecting: .orange; case .disconnected: .secondary; case .error: .red
        }
    }

    private func diagnosticStepIcon(_ status: DiagnosticStep.StepStatus) -> String {
        switch status {
        case .passed: "checkmark.circle.fill"; case .failed: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"; case .running: "arrow.triangle.2.circlepath"; case .pending: "circle"
        }
    }

    private func diagnosticStepColor(_ status: DiagnosticStep.StepStatus) -> Color {
        switch status {
        case .passed: .green; case .failed: .red; case .warning: .orange; case .running: .blue; case .pending: .secondary
        }
    }

    // MARK: - Helpers

    private func ppsrProxyRow(proxy: ProxyConfig) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(proxyStatusColor(proxy))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(proxy.displayString)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(proxy.statusLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(proxyStatusColor(proxy))
                    if let date = proxy.lastTested {
                        Text(date, style: .relative)
                            .font(.caption2).foregroundStyle(.quaternary)
                    }
                }
            }
            Spacer()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { proxyService.removeProxy(proxy, target: .ppsr) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func proxyStatusBadge(proxies: [ProxyConfig]) -> some View {
        Group {
            if !proxies.isEmpty {
                HStack(spacing: 4) {
                    let working = proxies.filter(\.isWorking).count
                    if working > 0 {
                        Text("\(working) ok")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    let dead = proxies.filter({ !$0.isWorking && $0.lastTested != nil }).count
                    if dead > 0 {
                        Text("\(dead) dead")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color(.tertiarySystemFill)).clipShape(Capsule())
            }
        }
    }

    private func proxyStatusColor(_ proxy: ProxyConfig) -> Color {
        if proxy.lastTested == nil { return .gray }
        return proxy.isWorking ? .green : .red
    }

    private func ppsrConnectionModeColor(_ mode: ConnectionMode) -> Color {
        switch mode {
        case .proxy: .blue
        case .openvpn: .indigo
        case .wireguard: .purple
        case .dns: .cyan
        }
    }

    // MARK: - Sheets

    private var ppsrProxyImportSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(.blue).frame(width: 10, height: 10)
                        Text("Import PPSR SOCKS5 Proxies").font(.headline)
                    }
                    Text("Paste proxies in any common format, one per line.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button {
                        if let clipboard = UIPasteboard.general.string, !clipboard.isEmpty {
                            ppsrProxyBulkText = clipboard
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                    let lineCount = ppsrProxyBulkText.components(separatedBy: .newlines).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count
                    if lineCount > 0 {
                        Text("\(lineCount) lines").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }

                TextEditor(text: $ppsrProxyBulkText)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 10)).frame(minHeight: 200)
                    .overlay(alignment: .topLeading) {
                        if ppsrProxyBulkText.isEmpty {
                            Text("Paste SOCKS5 proxies here...\n\n127.0.0.1:1080\nuser:pass@proxy.com:9050")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 14).padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                if let report = ppsrProxyImportReport {
                    HStack(spacing: 12) {
                        if report.added > 0 {
                            Label("\(report.added) added", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green)
                        }
                        if report.duplicates > 0 {
                            Label("\(report.duplicates) duplicates", systemImage: "arrow.triangle.2.circlepath").font(.caption.bold()).foregroundStyle(.orange)
                        }
                        if !report.failed.isEmpty {
                            Label("\(report.failed.count) failed", systemImage: "xmark.circle.fill").font(.caption.bold()).foregroundStyle(.red)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("PPSR Proxies").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showPPSRProxyImport = false
                        ppsrProxyBulkText = ""
                        ppsrProxyImportReport = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let report = proxyService.bulkImportSOCKS5(ppsrProxyBulkText, for: .ppsr)
                        ppsrProxyImportReport = report
                        if report.added > 0 {
                            vm.log("Imported \(report.added) PPSR SOCKS5 proxies", level: .success)
                        }
                        ppsrProxyBulkText = ""
                        if report.failed.isEmpty && report.added > 0 {
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                showPPSRProxyImport = false
                                ppsrProxyImportReport = nil
                            }
                        }
                    }
                    .disabled(ppsrProxyBulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    @State private var dnsImportText: String = ""
    @State private var showDNSImport: Bool = false
    @State private var newDNSName: String = ""
    @State private var newDNSURL: String = ""

    private var dnsManagerSheet: some View {
        NavigationStack {
            List {
                if showDNSImport {
                    Section("Import DNS Servers") {
                        Text("One per line. Format: Name|URL or just URL")
                            .font(.caption2).foregroundStyle(.secondary)

                        TextEditor(text: $dnsImportText)
                            .font(.system(.callout, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(.rect(cornerRadius: 8))
                            .frame(minHeight: 80)
                            .overlay(alignment: .topLeading) {
                                if dnsImportText.isEmpty {
                                    Text("Custom|https://dns.example.com/dns-query\nhttps://dns.other.com/dns-query")
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.quaternary)
                                        .padding(.horizontal, 12).padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }

                        HStack {
                            Button {
                                if let clip = UIPasteboard.general.string { dnsImportText = clip }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard").font(.caption)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            Spacer()
                            Button {
                                let result = PPSRDoHService.shared.bulkImportProviders(dnsImportText)
                                vm.log("DNS import: \(result.added) added, \(result.duplicates) dupes, \(result.invalid) invalid", level: result.added > 0 ? .success : .warning)
                                dnsImportText = ""
                                if result.added > 0 { withAnimation(.snappy) { showDNSImport = false } }
                            } label: {
                                Label("Import", systemImage: "arrow.down.doc.fill").font(.caption.bold())
                            }
                            .buttonStyle(.borderedProminent).tint(.cyan)
                            .disabled(dnsImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    Section("Add Single Server") {
                        TextField("Name", text: $newDNSName)
                            .font(.system(.body, design: .monospaced))
                        TextField("https://dns.example.com/dns-query", text: $newDNSURL)
                            .font(.system(.callout, design: .monospaced))
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button {
                            if PPSRDoHService.shared.addProvider(name: newDNSName, url: newDNSURL) {
                                vm.log("Added DNS provider: \(newDNSName)", level: .success)
                                newDNSName = ""
                                newDNSURL = ""
                            }
                        } label: {
                            Label("Add Server", systemImage: "plus.circle.fill")
                        }
                        .disabled(newDNSName.trimmingCharacters(in: .whitespaces).isEmpty || newDNSURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                let enabled = PPSRDoHService.shared.managedProviders.filter(\.isEnabled).count
                Section {
                    ForEach(PPSRDoHService.shared.managedProviders) { provider in
                        HStack(spacing: 10) {
                            Button {
                                PPSRDoHService.shared.toggleProvider(id: provider.id, enabled: !provider.isEnabled)
                            } label: {
                                Image(systemName: provider.isEnabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(provider.isEnabled ? .cyan : .secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(provider.name).font(.system(.subheadline, design: .monospaced, weight: .medium))
                                    if provider.isDefault {
                                        Text("DEFAULT")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.cyan.opacity(0.7))
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Color.cyan.opacity(0.1)).clipShape(Capsule())
                                    }
                                }
                                Text(provider.url.replacingOccurrences(of: "https://", with: ""))
                                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                PPSRDoHService.shared.deleteProvider(id: provider.id)
                                vm.log("Deleted DNS provider: \(provider.name)")
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    Text("DNS Servers (\(enabled)/\(PPSRDoHService.shared.managedProviders.count))")
                }

                Section {
                    Button {
                        withAnimation(.snappy) { showDNSImport.toggle() }
                    } label: {
                        Label(showDNSImport ? "Hide Import" : "Import / Add Servers", systemImage: "plus.circle.fill")
                    }
                    Button {
                        PPSRDoHService.shared.enableAll()
                        vm.log("Enabled all DNS providers", level: .success)
                    } label: {
                        Label("Enable All", systemImage: "checkmark.circle")
                    }
                    Button {
                        PPSRDoHService.shared.resetToDefaults()
                        vm.log("Reset DNS providers to defaults", level: .success)
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.uturn.backward")
                    }
                } header: {
                    Text("Actions")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("DNS Manager").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showDNSManager = false } }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }
}
