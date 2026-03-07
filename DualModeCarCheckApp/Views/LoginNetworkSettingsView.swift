import SwiftUI
import UniformTypeIdentifiers

struct LoginNetworkSettingsView: View {
    @Bindable var vm: LoginViewModel
    @State private var showURLManager: Bool = false
    @State private var showJoeProxyImport: Bool = false
    @State private var showIgnitionTargetProxyImport: Bool = false
    @State private var targetProxyBulkText: String = ""
    @State private var targetProxyImportReport: ProxyRotationService.ImportReport?
    @State private var isTestingJoeTargetProxies: Bool = false
    @State private var isTestingIgnitionTargetProxies: Bool = false
    @State private var showVPNFileImporter: Bool = false
    @State private var vpnImportTarget: ProxyRotationService.ProxyTarget = .joe
    @State private var showWGFileImporter: Bool = false
    @State private var wgImportTarget: ProxyRotationService.ProxyTarget = .joe
    @State private var showDNSManager: Bool = false
    @State private var nordAccessKeyInput: String = ""
    @State private var isEditingNordKey: Bool = false
    @State private var isTestingVPNConfigs: Bool = false
    @State private var isValidatingURLs: Bool = false
    private let nordService = NordVPNService.shared

    private var accentColor: Color {
        vm.isIgnitionMode ? .orange : .green
    }

    var body: some View {
        List {
            unifiedNetworkBanner
            urlRotationSection
            urlValidationSection
            nordVPNSection
            endpointSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Networks")
        .sheet(isPresented: $showURLManager) { urlManagerSheet }
        .sheet(isPresented: $showDNSManager) { loginDNSManagerSheet }
        .sheet(isPresented: $showJoeProxyImport) { targetProxyImportSheet(target: .joe) }
        .sheet(isPresented: $showIgnitionTargetProxyImport) { targetProxyImportSheet(target: .ignition) }
        .fileImporter(isPresented: $showVPNFileImporter, allowedContentTypes: [.data, .plainText], allowsMultipleSelection: true) { result in
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
                            vm.proxyService.importVPNConfig(config, for: vpnImportTarget)
                            imported += 1
                        } else {
                            vm.log("Failed to parse: \(fileName)", level: .warning)
                        }
                    }
                }
                if imported > 0 {
                    vm.log("Imported \(imported) OpenVPN config(s)", level: .success)
                }
            case .failure(let error):
                vm.log("VPN import error: \(error.localizedDescription)", level: .error)
            }
        }
        .fileImporter(isPresented: $showWGFileImporter, allowedContentTypes: [.data, .plainText], allowsMultipleSelection: true) { result in
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
                    let report = vm.proxyService.bulkImportWGConfigs(parsed, for: wgImportTarget)
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

    // MARK: - URL Rotation

    private var urlRotationSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("URL Rotation").font(.body)
                    Text("\(vm.urlRotation.enabledURLs.count) of \(vm.urlRotation.activeURLs.count) URLs enabled").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(vm.isIgnitionMode ? "Ignition" : "Joe")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(accentColor.opacity(0.12)).clipShape(Capsule())
            }

            Button { showURLManager = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet").foregroundStyle(accentColor)
                    Text("Manage URLs")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }

            Button {
                vm.urlRotation.enableAllURLs()
                vm.log("Re-enabled all URLs", level: .success)
            } label: {
                Label("Re-enable All URLs", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("URL Rotation")
        } footer: {
            Text("Each test uses the next enabled URL in rotation. Failed URLs are auto-disabled after 2 consecutive failures.")
        }
    }

    // MARK: - Unified Network Banner

    private var unifiedNetworkBanner: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unified Network Active").font(.subheadline.bold())
                    Text("Mode: \(vm.proxyService.unifiedConnectionMode.label) \u{2022} Region: \(vm.proxyService.networkRegion.label)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: vm.proxyService.networkRegion.icon)
                        .font(.caption)
                        .foregroundStyle(vm.proxyService.networkRegion == .usa ? .blue : .orange)
                    Text(vm.proxyService.networkRegion.rawValue)
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(vm.proxyService.networkRegion == .usa ? .blue : .orange)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background((vm.proxyService.networkRegion == .usa ? Color.blue : .orange).opacity(0.12))
                .clipShape(Capsule())
            }
        } header: {
            Text("Network")
        } footer: {
            Text("Network configs (Proxy/VPN/WG/DNS), calibration, and region are managed in Automation Config. Changes sync across Joe, Ignition & PPSR.")
        }
    }

    // MARK: - URL Validation

    private var urlValidationSection: some View {
        Section {
            Button {
                guard !isValidatingURLs else { return }
                isValidatingURLs = true
                vm.log("Validating Joe Fortune URLs (static → www fallback)...")
                Task {
                    await vm.urlRotation.validateAndUpdateJoeURLs()
                    let enabled = vm.urlRotation.joeURLs.filter(\.isEnabled).count
                    vm.log("Joe URL validation complete: \(enabled)/\(vm.urlRotation.joeURLs.count) active", level: .success)
                    isValidatingURLs = false
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill").font(.title3).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Validate Joe URLs").font(.subheadline.bold())
                        Text("Prefer static.* subdomain, fallback to www.*").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isValidatingURLs {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(isValidatingURLs)
        } header: {
            Text("URL Validation")
        }
    }



    private func connectionModeSection(
        title: String,
        target: ProxyRotationService.ProxyTarget,
        color: Color,
        icon: String,
        showProxyImportBinding: Binding<Bool>,
        isTestingBinding: Binding<Bool>
    ) -> some View {
        let currentMode = vm.proxyService.connectionMode(for: target)
        let proxyList = vm.proxyService.proxies(for: target)
        return Section {
            Picker(selection: Binding(
                get: { vm.proxyService.connectionMode(for: target) },
                set: { newMode in
                    withAnimation(.spring(duration: 0.3)) {
                        vm.proxyService.setConnectionMode(newMode, for: target)
                    }
                    vm.log("\(title) switched to \(newMode.label) mode", level: .success)
                }
            )) {
                ForEach(ConnectionMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon).foregroundStyle(color)
                    Text("\(title) Connection")
                }
            }
            .pickerStyle(.menu)
            .sensoryFeedback(.impact(weight: .medium), trigger: currentMode)

            if currentMode == .proxy {
                HStack(spacing: 10) {
                    Image(systemName: "network").foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(title) Proxies").font(.body)
                        Text("\(proxyList.count) proxies loaded").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    proxyStatusBadge(proxies: proxyList)
                }

                Button { showProxyImportBinding.wrappedValue = true } label: {
                    Label("Import Proxies", systemImage: "doc.on.clipboard.fill")
                }

                if !proxyList.isEmpty {
                    Button {
                        guard !isTestingBinding.wrappedValue else { return }
                        isTestingBinding.wrappedValue = true
                        Task {
                            vm.log("Testing all \(proxyList.count) \(title) proxies...")
                            await vm.proxyService.testAllProxies(target: target)
                            let working = vm.proxyService.proxies(for: target).filter(\.isWorking).count
                            vm.log("\(title) proxy test: \(working)/\(proxyList.count) working", level: .success)
                            isTestingBinding.wrappedValue = false
                        }
                    } label: {
                        HStack {
                            Label("Test Proxies", systemImage: "antenna.radiowaves.left.and.right")
                            if isTestingBinding.wrappedValue { Spacer(); ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isTestingBinding.wrappedValue)

                    Button {
                        let exported = vm.proxyService.exportProxies(target: target)
                        UIPasteboard.general.string = exported
                        vm.log("Exported \(proxyList.count) \(title) proxies to clipboard", level: .success)
                    } label: {
                        Label("Export to Clipboard", systemImage: "doc.on.doc")
                    }

                    let deadCount = proxyList.filter({ !$0.isWorking && $0.lastTested != nil }).count
                    if deadCount > 0 {
                        Button(role: .destructive) {
                            vm.proxyService.removeDead(target: target)
                            vm.log("Removed \(deadCount) dead \(title) proxies")
                        } label: {
                            Label("Remove \(deadCount) Dead", systemImage: "xmark.circle")
                        }
                    }

                    ForEach(proxyList) { proxy in
                        targetProxyRow(proxy: proxy, target: target)
                    }

                    Button {
                        vm.proxyService.resetAllStatus(target: target)
                        vm.log("Reset all \(title) proxy statuses")
                    } label: {
                        Label("Reset All Status", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        vm.proxyService.removeAll(target: target)
                        vm.log("Cleared all \(title) proxies")
                    } label: {
                        Label("Clear All Proxies", systemImage: "trash")
                    }
                }
            } else if currentMode == .openvpn {
                let vpnList = vm.proxyService.vpnConfigs(for: target)
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(title) OpenVPN").font(.body)
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

                Button {
                    vpnImportTarget = target
                    showVPNFileImporter = true
                } label: {
                    Label("Import .ovpn File", systemImage: "doc.badge.plus")
                }

                if !vpnList.isEmpty {
                    Button {
                        guard !isTestingVPNConfigs else { return }
                        isTestingVPNConfigs = true
                        Task {
                            vm.log("Testing \(vpnList.count) \(title) OpenVPN configs...")
                            await vm.proxyService.testAllVPNConfigs(target: target)
                            let reachable = vm.proxyService.vpnConfigs(for: target).filter(\.isReachable).count
                            vm.log("\(title) OpenVPN test: \(reachable)/\(vpnList.count) reachable", level: .success)
                            isTestingVPNConfigs = false
                        }
                    } label: {
                        HStack {
                            Label("Test All OpenVPN", systemImage: "antenna.radiowaves.left.and.right")
                            if isTestingVPNConfigs { Spacer(); ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isTestingVPNConfigs)

                    ForEach(vpnList) { vpn in
                        HStack(spacing: 8) {
                            Image(systemName: vpn.isEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(vpn.isEnabled ? .indigo : .secondary)
                                .onTapGesture {
                                    vm.proxyService.toggleVPNConfig(vpn, target: target, enabled: !vpn.isEnabled)
                                }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(vpn.fileName)
                                    .font(.system(.caption, design: .monospaced, weight: .medium))
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(vpn.displayString)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                    Text(vpn.statusLabel)
                                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                                        .foregroundStyle(vpn.isReachable ? .green : (vpn.lastTested != nil ? .red : .gray))
                                    if let latency = vpn.lastLatencyMs {
                                        Text("\(latency)ms")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                vm.proxyService.removeVPNConfig(vpn, target: target)
                                vm.log("Removed VPN: \(vpn.fileName)")
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }

                    let unreachableCount = vpnList.filter({ !$0.isReachable && $0.lastTested != nil }).count
                    if unreachableCount > 0 {
                        Button(role: .destructive) {
                            vm.proxyService.removeUnreachableVPNConfigs(target: target)
                            vm.log("Removed \(unreachableCount) unreachable \(title) OpenVPN configs")
                        } label: {
                            Label("Remove \(unreachableCount) Unreachable", systemImage: "xmark.circle")
                        }
                    }

                    Button(role: .destructive) {
                        vm.proxyService.clearAllVPNConfigs(target: target)
                        vm.log("Cleared all \(title) OpenVPN configs")
                    } label: {
                        Label("Clear All Configs", systemImage: "trash")
                    }
                }
            } else if currentMode == .wireguard {
                let wgList = vm.proxyService.wgConfigs(for: target)
                HStack(spacing: 10) {
                    Image(systemName: "lock.trianglebadge.exclamationmark.fill").foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(title) WireGuard").font(.body)
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

                Button {
                    wgImportTarget = target
                    showWGFileImporter = true
                } label: {
                    Label("Import .conf Files", systemImage: "doc.badge.plus")
                }

                if !wgList.isEmpty {
                    Button {
                        vm.log("Testing \(wgList.count) \(title) WireGuard configs...")
                        Task {
                            await vm.proxyService.testAllWGConfigs(target: target)
                            let reachable = vm.proxyService.wgConfigs(for: target).filter(\.isReachable).count
                            vm.log("\(title) WireGuard test: \(reachable)/\(wgList.count) reachable", level: .success)
                        }
                    } label: {
                        Label("Test All WireGuard", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    ForEach(wgList) { wg in
                        HStack(spacing: 8) {
                            Image(systemName: wg.isEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(wg.isEnabled ? .purple : .secondary)
                                .onTapGesture {
                                    vm.proxyService.toggleWGConfig(wg, target: target, enabled: !wg.isEnabled)
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
                                vm.proxyService.removeWGConfig(wg, target: target)
                                vm.log("Removed WireGuard: \(wg.fileName)")
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }

                    let unreachableWGCount = wgList.filter({ !$0.isReachable && $0.lastTested != nil }).count
                    if unreachableWGCount > 0 {
                        Button(role: .destructive) {
                            vm.proxyService.removeUnreachableWGConfigs(target: target)
                            vm.log("Removed \(unreachableWGCount) unreachable \(title) WireGuard configs")
                        } label: {
                            Label("Remove \(unreachableWGCount) Unreachable", systemImage: "xmark.circle")
                        }
                    }

                    Button(role: .destructive) {
                        vm.proxyService.clearAllWGConfigs(target: target)
                        vm.log("Cleared all \(title) WireGuard configs")
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
                        Text("\(enabled)/\(total) providers enabled").font(.caption2).foregroundStyle(.secondary)
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
                Text("\(title) Connection")
                Spacer()
                Text(currentMode.label)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(connectionModeColor(currentMode, tint: color))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(connectionModeColor(currentMode, tint: color).opacity(0.12))
                    .clipShape(Capsule())
            }
        } footer: {
            switch currentMode {
            case .proxy: Text("\(title) uses SOCKS5 proxies for all connections.")
            case .openvpn: Text("\(title) uses OpenVPN configs. Import .ovpn files to connect.")
            case .wireguard: Text("\(title) uses WireGuard configs. Import NordVPN .conf files to connect.")
            case .dns: Text("\(title) uses DoH DNS rotation for connections.")
            }
        }
    }

    // MARK: - NordVPN

    @State private var isDownloadingNordOVPN: Bool = false
    @State private var nordOVPNDownloadTarget: ProxyRotationService.ProxyTarget = .joe

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
                    Menu {
                        Button {
                            downloadNordOVPN(target: .joe)
                        } label: { Label("Download All TCP → Joe", systemImage: "suit.spade.fill") }
                        Button {
                            downloadNordOVPN(target: .ignition)
                        } label: { Label("Download All TCP → Ignition", systemImage: "flame.fill") }
                    } label: {
                        HStack(spacing: 10) {
                            if nordService.isDownloadingOVPN {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.doc.fill").foregroundStyle(.indigo)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Download All TCP .ovpn Files").font(.subheadline.bold())
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
                                            vm.proxyService.importVPNConfig(config, for: .joe)
                                            vm.log("Imported TCP .ovpn [Joe]: \(server.hostname)", level: .success)
                                        } else {
                                            vm.log("Failed to download .ovpn: \(server.hostname)", level: .error)
                                        }
                                    }
                                } label: { Label("TCP → Joe", systemImage: "suit.spade.fill") }
                                Button {
                                    Task {
                                        if let config = await nordService.downloadOVPNConfig(from: server, proto: .tcp) {
                                            vm.proxyService.importVPNConfig(config, for: .ignition)
                                            vm.log("Imported TCP .ovpn [Ignition]: \(server.hostname)", level: .success)
                                        } else {
                                            vm.log("Failed to download .ovpn: \(server.hostname)", level: .error)
                                        }
                                    }
                                } label: { Label("TCP → Ignition", systemImage: "flame.fill") }
                                if nordService.hasPrivateKey, let _ = server.publicKey {
                                    Divider()
                                    Button {
                                        if let wg = nordService.generateWireGuardConfig(from: server) {
                                            vm.proxyService.importWGConfig(wg, for: .joe)
                                            vm.log("Imported WG [Joe]: \(server.hostname)", level: .success)
                                        }
                                    } label: { Label("WG → Joe", systemImage: "lock.fill") }
                                    Button {
                                        if let wg = nordService.generateWireGuardConfig(from: server) {
                                            vm.proxyService.importWGConfig(wg, for: .ignition)
                                            vm.log("Imported WG [Ignition]: \(server.hostname)", level: .success)
                                        }
                                    } label: { Label("WG → Ignition", systemImage: "lock.fill") }
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
        } header: {
            Text("NordVPN")
        } footer: {
            Text("Fetches recommended TCP OpenVPN servers from NordVPN and downloads real .ovpn config files for import.")
        }
    }

    private func downloadNordOVPN(target: ProxyRotationService.ProxyTarget) {
        guard !nordService.isDownloadingOVPN else { return }
        Task {
            let result = await nordService.downloadAllTCPConfigs(for: nordService.recommendedServers, target: target)
            let targetName = target == .joe ? "Joe" : "Ignition"
            vm.log("NordVPN TCP: \(result.imported) imported, \(result.failed) failed → \(targetName)", level: result.imported > 0 ? .success : .error)
        }
    }

    // MARK: - Endpoint

    private var endpointSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Target") {
                    HStack(spacing: 4) {
                        Circle().fill(endpointColor).frame(width: 6, height: 6)
                        Text(vm.connectionStatus == .connected ? "Live" : vm.connectionStatus.rawValue)
                            .font(.system(.body, design: .monospaced)).foregroundStyle(endpointColor)
                    }
                }
                LabeledContent("Site") { Text(vm.urlRotation.currentSiteName).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
                LabeledContent("URLs") { Text("\(vm.urlRotation.enabledURLs.count) active").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
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
        } header: {
            Text("Live Endpoint")
        }
    }

    private var endpointColor: Color {
        switch vm.connectionStatus {
        case .connected: .green; case .connecting: .orange; case .disconnected: .secondary; case .error: .red
        }
    }

    // MARK: - Helpers

    private func targetProxyRow(proxy: ProxyConfig, target: ProxyRotationService.ProxyTarget) -> some View {
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
            Button(role: .destructive) { vm.proxyService.removeProxy(proxy, target: target) } label: { Label("Delete", systemImage: "trash") }
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

    private func connectionModeColor(_ mode: ConnectionMode, tint: Color) -> Color {
        switch mode {
        case .proxy: tint
        case .openvpn: .indigo
        case .wireguard: .purple
        case .dns: .cyan
        }
    }

    // MARK: - Sheets

    private func targetProxyImportSheet(target: ProxyRotationService.ProxyTarget) -> some View {
        let targetName: String
        let targetColor: Color
        switch target {
        case .joe: targetName = "Joe Fortune"; targetColor = .green
        case .ignition: targetName = "Ignition"; targetColor = .orange
        case .ppsr: targetName = "PPSR"; targetColor = .blue
        }
        return NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(targetColor).frame(width: 10, height: 10)
                        Text("Import \(targetName) SOCKS5 Proxies").font(.headline)
                    }
                    Text("Paste proxies in any common format, one per line.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button {
                        if let clipboard = UIPasteboard.general.string, !clipboard.isEmpty {
                            targetProxyBulkText = clipboard
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                    let lineCount = targetProxyBulkText.components(separatedBy: .newlines).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count
                    if lineCount > 0 {
                        Text("\(lineCount) lines").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }

                TextEditor(text: $targetProxyBulkText)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 10)).frame(minHeight: 200)
                    .overlay(alignment: .topLeading) {
                        if targetProxyBulkText.isEmpty {
                            Text("Paste SOCKS5 proxies here...\n\n127.0.0.1:1080\nuser:pass@proxy.com:9050")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 14).padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                if let report = targetProxyImportReport {
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
            .navigationTitle("\(targetName) Proxies").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if target == .joe { showJoeProxyImport = false }
                        else { showIgnitionTargetProxyImport = false }
                        targetProxyBulkText = ""
                        targetProxyImportReport = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let report = vm.proxyService.bulkImportSOCKS5(targetProxyBulkText, for: target)
                        targetProxyImportReport = report
                        if report.added > 0 {
                            vm.log("Imported \(report.added) \(targetName) SOCKS5 proxies", level: .success)
                        }
                        targetProxyBulkText = ""
                        if report.failed.isEmpty && report.added > 0 {
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                if target == .joe { showJoeProxyImport = false }
                                else { showIgnitionTargetProxyImport = false }
                                targetProxyImportReport = nil
                            }
                        }
                    }
                    .disabled(targetProxyBulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    @State private var loginDNSImportText: String = ""
    @State private var showLoginDNSImport: Bool = false
    @State private var newLoginDNSName: String = ""
    @State private var newLoginDNSURL: String = ""

    private var loginDNSManagerSheet: some View {
        NavigationStack {
            List {
                if showLoginDNSImport {
                    Section("Import DNS Servers") {
                        Text("One per line. Format: Name|URL or just URL")
                            .font(.caption2).foregroundStyle(.secondary)

                        TextEditor(text: $loginDNSImportText)
                            .font(.system(.callout, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(.rect(cornerRadius: 8))
                            .frame(minHeight: 80)
                            .overlay(alignment: .topLeading) {
                                if loginDNSImportText.isEmpty {
                                    Text("Custom|https://dns.example.com/dns-query")
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.quaternary)
                                        .padding(.horizontal, 12).padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }

                        HStack {
                            Button {
                                if let clip = UIPasteboard.general.string { loginDNSImportText = clip }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard").font(.caption)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            Spacer()
                            Button {
                                let result = PPSRDoHService.shared.bulkImportProviders(loginDNSImportText)
                                vm.log("DNS import: \(result.added) added, \(result.duplicates) dupes", level: result.added > 0 ? .success : .warning)
                                loginDNSImportText = ""
                                if result.added > 0 { withAnimation(.snappy) { showLoginDNSImport = false } }
                            } label: {
                                Label("Import", systemImage: "arrow.down.doc.fill").font(.caption.bold())
                            }
                            .buttonStyle(.borderedProminent).tint(.cyan)
                            .disabled(loginDNSImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    Section("Add Single Server") {
                        TextField("Name", text: $newLoginDNSName)
                            .font(.system(.body, design: .monospaced))
                        TextField("https://dns.example.com/dns-query", text: $newLoginDNSURL)
                            .font(.system(.callout, design: .monospaced))
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button {
                            if PPSRDoHService.shared.addProvider(name: newLoginDNSName, url: newLoginDNSURL) {
                                vm.log("Added DNS: \(newLoginDNSName)", level: .success)
                                newLoginDNSName = ""
                                newLoginDNSURL = ""
                            }
                        } label: {
                            Label("Add Server", systemImage: "plus.circle.fill")
                        }
                        .disabled(newLoginDNSName.trimmingCharacters(in: .whitespaces).isEmpty || newLoginDNSURL.trimmingCharacters(in: .whitespaces).isEmpty)
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
                                vm.log("Deleted DNS: \(provider.name)")
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    Text("DNS Servers (\(enabled)/\(PPSRDoHService.shared.managedProviders.count))")
                }

                Section {
                    Button {
                        withAnimation(.snappy) { showLoginDNSImport.toggle() }
                    } label: {
                        Label(showLoginDNSImport ? "Hide Import" : "Import / Add Servers", systemImage: "plus.circle.fill")
                    }
                    Button {
                        PPSRDoHService.shared.enableAll()
                        vm.log("Enabled all DNS providers", level: .success)
                    } label: {
                        Label("Enable All", systemImage: "checkmark.circle")
                    }
                    Button {
                        PPSRDoHService.shared.resetToDefaults()
                        vm.log("Reset DNS to defaults", level: .success)
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

    @State private var urlViewingIgnition: Bool = false
    @State private var showURLImportBox: Bool = false
    @State private var urlImportText: String = ""

    private var urlManagerSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.spring(duration: 0.3)) { urlViewingIgnition = false }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "suit.spade.fill")
                                Text("Joe").font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(!urlViewingIgnition ? Color.green : Color(.tertiarySystemFill))
                            .foregroundStyle(!urlViewingIgnition ? .white : .secondary)
                        }
                        .clipShape(.rect(cornerRadii: .init(topLeading: 10, bottomLeading: 10)))

                        Button {
                            withAnimation(.spring(duration: 0.3)) { urlViewingIgnition = true }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                Text("Ignition").font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(urlViewingIgnition ? Color.orange : Color(.tertiarySystemFill))
                            .foregroundStyle(urlViewingIgnition ? .white : .secondary)
                        }
                        .clipShape(.rect(cornerRadii: .init(bottomTrailing: 10, topTrailing: 10)))
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if showURLImportBox {
                    Section("Import URLs") {
                        TextEditor(text: $urlImportText)
                            .font(.system(.callout, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(.rect(cornerRadius: 8))
                            .frame(minHeight: 100)
                            .overlay(alignment: .topLeading) {
                                if urlImportText.isEmpty {
                                    Text("One URL per line...\nhttps://domain.com/login")
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.quaternary)
                                        .padding(.horizontal, 12).padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }

                        HStack {
                            Button {
                                if let clip = UIPasteboard.general.string { urlImportText = clip }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard").font(.caption)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            Spacer()
                            Button {
                                let result = vm.urlRotation.bulkImportURLs(urlImportText, forIgnition: urlViewingIgnition)
                                vm.log("URL import: \(result.added) added, \(result.duplicates) dupes, \(result.invalid) invalid", level: result.added > 0 ? .success : .warning)
                                urlImportText = ""
                                if result.added > 0 {
                                    withAnimation(.snappy) { showURLImportBox = false }
                                }
                            } label: {
                                Label("Import", systemImage: "arrow.down.doc.fill").font(.caption.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(urlViewingIgnition ? .orange : .green)
                            .disabled(urlImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                let urlList = urlViewingIgnition ? vm.urlRotation.ignitionURLs : vm.urlRotation.joeURLs
                Section {
                    ForEach(urlList) { urlEntry in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(urlEntry.isEnabled ? (urlViewingIgnition ? Color.orange : Color.green) : Color.red.opacity(0.5))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(urlEntry.host)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(urlEntry.isEnabled ? .primary : .secondary)
                                    .strikethrough(!urlEntry.isEnabled)
                                HStack(spacing: 6) {
                                    if urlEntry.failCount > 0 {
                                        Text("\(urlEntry.failCount) fails").font(.caption2).foregroundStyle(.red)
                                    }
                                    if urlEntry.totalAttempts > 0 {
                                        Text(urlEntry.formattedSuccessRate).font(.caption2).foregroundStyle(.secondary)
                                        Text(urlEntry.formattedAvgResponse).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                            Button {
                                vm.urlRotation.toggleURL(id: urlEntry.id, enabled: !urlEntry.isEnabled)
                            } label: {
                                Image(systemName: urlEntry.isEnabled ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(urlEntry.isEnabled ? .green : .red.opacity(0.5))
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                vm.urlRotation.deleteURL(id: urlEntry.id)
                                vm.log("Deleted URL: \(urlEntry.host)")
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    let enabled = urlList.filter(\.isEnabled).count
                    Text("\(urlViewingIgnition ? "Ignition" : "Joe") URLs (\(enabled)/\(urlList.count))")
                }

                Section {
                    Button {
                        withAnimation(.snappy) { showURLImportBox.toggle() }
                    } label: {
                        Label(showURLImportBox ? "Hide Import" : "Import URLs", systemImage: "plus.circle.fill")
                    }
                    Button {
                        vm.urlRotation.enableAllURLs()
                        vm.log("Re-enabled all URLs", level: .success)
                    } label: {
                        Label("Re-enable All", systemImage: "arrow.counterclockwise")
                    }
                    Button {
                        vm.urlRotation.resetPerformanceStats()
                        vm.log("Reset URL performance stats")
                    } label: {
                        Label("Reset Stats", systemImage: "chart.bar.xaxis")
                    }
                    Button {
                        vm.urlRotation.resetToDefaults(forIgnition: urlViewingIgnition)
                        vm.log("Reset \(urlViewingIgnition ? "Ignition" : "Joe") URLs to defaults", level: .success)
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.uturn.backward")
                    }
                    if !urlList.isEmpty {
                        Button(role: .destructive) {
                            vm.urlRotation.deleteAllURLs(forIgnition: urlViewingIgnition)
                            vm.log("Deleted all \(urlViewingIgnition ? "Ignition" : "Joe") URLs")
                        } label: {
                            Label("Delete All \(urlViewingIgnition ? "Ignition" : "Joe") URLs", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Actions")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("URL Manager").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showURLManager = false } }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }
}
