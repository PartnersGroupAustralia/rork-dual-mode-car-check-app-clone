import SwiftUI
import UniformTypeIdentifiers

struct PPSRSettingsView: View {
    @Bindable var vm: PPSRAutomationViewModel
    @AppStorage("introVideoEnabled") private var introVideoEnabled: Bool = false
    @State private var showEmailImport: Bool = false
    @State private var emailCSVText: String = ""
    @State private var cropX: String = ""
    @State private var cropY: String = ""
    @State private var cropW: String = ""
    @State private var cropH: String = ""
    @State private var showCropEditor: Bool = false
    @State private var showDNSManager: Bool = false
    @State private var showPPSRProxyImport: Bool = false
    @State private var ppsrProxyBulkText: String = ""
    @State private var ppsrProxyImportReport: ProxyRotationService.ImportReport?
    @State private var isTestingPPSRProxies: Bool = false
    @State private var showPPSRVPNFileImporter: Bool = false
    @State private var showPPSRWGFileImporter: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var showImportSheet: Bool = false
    @State private var importConfigText: String = ""
    @State private var importResult: AppDataExportService.ImportResult?
    @State private var exportedJSON: String = ""
    @State private var showImportFileImporter: Bool = false
    @State private var nordAccessKeyInput: String = ""
    @State private var isTestingVPNConfigs: Bool = false

    private let proxyService = ProxyRotationService.shared
    private let nordService = NordVPNService.shared

    var body: some View {
        List {
            importSection
            networksLinkSection
            automationSection
            concurrencySection
            stealthSection
            emailSection
            screenshotSection
            debugSection
            iCloudSection
            configExportImportSection
            appearanceSection
            introVideoSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Advanced Settings")
        .sheet(isPresented: $showEmailImport) { emailImportSheet }
        .sheet(isPresented: $showCropEditor) { cropEditorSheet }
        .sheet(isPresented: $showDNSManager) { dnsManagerSheet }
        .sheet(isPresented: $showPPSRProxyImport) { ppsrProxyImportSheet }
        .sheet(isPresented: $showExportSheet) { exportConfigSheet }
        .sheet(isPresented: $showImportSheet) { importConfigSheet }
        .fileImporter(isPresented: $showPPSRVPNFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
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
        .fileImporter(isPresented: $showPPSRWGFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
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

    private var networksLinkSection: some View {
        Section {
            NavigationLink {
                PPSRNetworkSettingsView(vm: vm)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "network").font(.title3).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Networks").font(.subheadline.bold())
                        Text("Connection, proxies, VPN, DNS & diagnostics").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

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

    private var stealthSection: some View {
        Section {
            Toggle(isOn: $vm.stealthEnabled) {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill").foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ultra Stealth Mode").font(.body)
                        Text("Rotating user agents, fingerprints & viewports").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.purple)
            .sensoryFeedback(.impact(weight: .light), trigger: vm.stealthEnabled)
        } header: {
            Text("Stealth")
        } footer: {
            Text(vm.stealthEnabled ? "Each session uses a unique browser identity. Canvas, WebGL, timezone and navigator properties are spoofed." : "Enable to rotate browser fingerprints across sessions.")
        }
    }

    private var automationSection: some View {
        Section {
            Toggle(isOn: $vm.retrySubmitOnFail) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Retry Submit on Fail").font(.body)
                        Text("Automatically retries submit if no clear result").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.orange)
            .sensoryFeedback(.impact(weight: .light), trigger: vm.retrySubmitOnFail)
        } header: {
            Text("Automation")
        }
    }

    private var screenshotSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.dashed").foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screenshot Mode").font(.body)
                    Text("Full-page capture on every test").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Full Page").font(.system(.caption, design: .monospaced, weight: .bold)).foregroundStyle(.indigo)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Color.indigo.opacity(0.12)).clipShape(Capsule())
            }

            Button {
                cropX = vm.screenshotCropRect == .zero ? "" : "\(Int(vm.screenshotCropRect.origin.x))"
                cropY = vm.screenshotCropRect == .zero ? "" : "\(Int(vm.screenshotCropRect.origin.y))"
                cropW = vm.screenshotCropRect == .zero ? "" : "\(Int(vm.screenshotCropRect.size.width))"
                cropH = vm.screenshotCropRect == .zero ? "" : "\(Int(vm.screenshotCropRect.size.height))"
                showCropEditor = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "crop").foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Focus Crop Area").font(.body)
                        Text(vm.screenshotCropRect == .zero ? "No crop — showing full page" : "Crop: \(Int(vm.screenshotCropRect.origin.x)),\(Int(vm.screenshotCropRect.origin.y)) \(Int(vm.screenshotCropRect.width))×\(Int(vm.screenshotCropRect.height))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }

            if vm.screenshotCropRect != .zero {
                Button(role: .destructive) {
                    vm.screenshotCropRect = .zero
                    vm.persistSettings()
                    vm.log("Cleared screenshot focus crop area")
                } label: {
                    Label("Clear Focus Crop", systemImage: "xmark.circle")
                }
            }
        } header: {
            Text("Screenshots")
        }
    }

    private var debugSection: some View {
        Section {
            Toggle(isOn: $vm.debugMode) {
                HStack(spacing: 10) {
                    Image(systemName: "ladybug.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Debug Mode").font(.body)
                        Text("Captures full-page screenshot per test").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.orange)

            if vm.debugMode {
                NavigationLink {
                    PPSRDebugScreenshotsView(vm: vm)
                } label: {
                    HStack {
                        Image(systemName: "photo.stack").foregroundStyle(.orange)
                        Text("Debug Screenshots")
                        Spacer()
                        Text("\(vm.debugScreenshots.count)").font(.system(.caption, design: .monospaced, weight: .bold)).foregroundStyle(.secondary)
                    }
                }

                if !vm.debugScreenshots.isEmpty {
                    Button(role: .destructive) { vm.debugScreenshots.removeAll() } label: { Label("Clear All Screenshots", systemImage: "trash") }
                }
            }
            NavigationLink {
                DebugLogView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Debug Log").font(.body)
                        Text("View debug entries").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        } header: {
            Text("Debug")
        } footer: {
            Text(vm.debugMode ? "Full-page screenshot captured per test." : "Enable to capture WebView screenshots during automation.")
        }
    }

    private var importSection: some View {
        Section {
            if !vm.untestedCards.isEmpty {
                Button {
                    vm.testAllUntested()
                } label: {
                    HStack {
                        Spacer()
                        Label("Test All Untested (\(vm.untestedCards.count))", systemImage: "play.fill").font(.headline)
                        Spacer()
                    }
                }
                .disabled(vm.isRunning)
                .listRowBackground(vm.isRunning ? Color.indigo.opacity(0.4) : Color.indigo)
                .foregroundStyle(.white)
                .sensoryFeedback(.impact(weight: .heavy), trigger: vm.isRunning)
            }
        } header: {
            Text("Quick Actions")
        }
    }

    private var iCloudSection: some View {
        Section {
            Button { vm.syncFromiCloud() } label: {
                HStack(spacing: 10) { Image(systemName: "icloud.and.arrow.down").foregroundStyle(.blue); Text("Sync from iCloud") }
            }
            Button {
                vm.persistCards()
                vm.log("Forced save to local + iCloud", level: .success)
            } label: {
                HStack(spacing: 10) { Image(systemName: "icloud.and.arrow.up").foregroundStyle(.blue); Text("Force Save to iCloud") }
            }
        } header: {
            Text("iCloud Sync")
        } footer: {
            Text("Cards are automatically saved locally and to iCloud.")
        }
    }

    private var emailSection: some View {
        Section {
            Toggle(isOn: $vm.useEmailRotation) {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.arrow.triangle.branch.fill").foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Generate Email").font(.body)
                        Text("Rotate through uploaded email list").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.teal)

            if vm.useEmailRotation {
                HStack {
                    Image(systemName: "list.bullet").foregroundStyle(.teal)
                    Text("Email Pool")
                    Spacer()
                    Text("\(vm.rotationEmailCount) emails").font(.system(.caption, design: .monospaced, weight: .bold)).foregroundStyle(.secondary)
                }
                Button { showEmailImport = true } label: { Label("Import Email CSV", systemImage: "square.and.arrow.down") }
                if vm.rotationEmailCount > 0 {
                    Button { vm.resetRotationEmailsToDefault() } label: { Label("Reset to Default List", systemImage: "arrow.counterclockwise") }
                    Button(role: .destructive) { vm.clearRotationEmails() } label: { Label("Clear Email List", systemImage: "trash") }
                }
            }

            if !vm.useEmailRotation {
                TextField("Test email", text: $vm.testEmail)
                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
            }
        } header: {
            Text("Email")
        } footer: {
            Text(vm.useEmailRotation ? "Each test uses the next email from the pool." : "Applied to all PPSR checks.")
        }
    }

    private var concurrencySection: some View {
        Section {
            Picker("Max Sessions", selection: $vm.maxConcurrency) {
                ForEach(1...8, id: \.self) { n in Text("\(n)").tag(n) }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Concurrency")
        } footer: {
            Text("Up to 8 concurrent WKWebView sessions.")
        }
    }

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

            if !nordService.hasAccessKey {
                HStack {
                    SecureField("Nord Access Key", text: $nordAccessKeyInput)
                        .font(.system(.caption, design: .monospaced))
                        .textContentType(.password)
                    Button("Save") {
                        nordService.setAccessKey(nordAccessKeyInput)
                        nordAccessKeyInput = ""
                    }
                    .disabled(nordAccessKeyInput.isEmpty)
                }
            } else {
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
                    Task { await nordService.fetchRecommendedServers(limit: 10) }
                } label: {
                    HStack {
                        if nordService.isLoadingServers { ProgressView().controlSize(.small) }
                        Label("Fetch Recommended Servers", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(nordService.isLoadingServers)

                if !nordService.recommendedServers.isEmpty {
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
                            if nordService.hasPrivateKey && server.publicKey != nil {
                                Button {
                                    if let wgConfig = nordService.generateWireGuardConfig(from: server) {
                                        proxyService.importWGConfig(wgConfig, for: .ppsr)
                                        vm.log("Imported WG: \(server.hostname)", level: .success)
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
                                }
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
            Text("Configure NordVPN access key to auto-generate WireGuard and OpenVPN configs from recommended servers.")
        }
    }

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

    private var appearanceSection: some View {
        Section {
            Picker(selection: $vm.appearanceMode) {
                ForEach(PPSRAutomationViewModel.AppearanceMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            } label: {
                HStack(spacing: 10) { Image(systemName: "paintbrush.fill").foregroundStyle(.purple); Text("Appearance") }
            }
        } header: {
            Text("Appearance")
        }
    }

    private var introVideoSection: some View {
        Section {
            Toggle(isOn: $introVideoEnabled) {
                HStack(spacing: 10) {
                    Image(systemName: "film.fill").foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Intro Video").font(.body)
                        Text("Play intro video on app launch").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.pink)
            .sensoryFeedback(.impact(weight: .light), trigger: introVideoEnabled)
        } header: {
            Text("Startup")
        } footer: {
            Text(introVideoEnabled ? "Intro video will play each time you open the app." : "Intro video is disabled. Enable to show it on launch.")
        }
    }

    private var configExportImportSection: some View {
        Section {
            Button {
                exportedJSON = AppDataExportService.shared.exportJSON()
                showExportSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up.fill").foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Configuration").font(.body)
                        Text("URLs, proxies, DNS, VPN, blacklist & settings").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }

            Button {
                importConfigText = ""
                importResult = nil
                showImportSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import Configuration").font(.body)
                        Text("Paste or load a JSON config to merge").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Configuration Backup")
        } footer: {
            Text("Export saves all URLs, proxies, VPN configs, DNS servers, blacklist, and connection modes as JSON. Import merges without overwriting existing entries.")
        }
    }

    private var exportConfigSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = exportedJSON
                        vm.log("Config JSON copied to clipboard", level: .success)
                    } label: {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc.fill")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent).tint(.blue)

                    Spacer()

                    let byteCount = exportedJSON.utf8.count
                    Text("\(byteCount / 1024)KB")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                ScrollView {
                    Text(exportedJSON)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(.rect(cornerRadius: 10))
                }
                .padding(.horizontal)
            }
            .padding(.top)
            .navigationTitle("Export Config").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showExportSheet = false } }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private var importConfigSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Button {
                        if let clip = UIPasteboard.general.string { importConfigText = clip }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button { showImportFileImporter = true } label: {
                        Label("Load File", systemImage: "folder").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Spacer()

                    let lineCount = importConfigText.components(separatedBy: .newlines).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count
                    if lineCount > 0 {
                        Text("\(lineCount) lines").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                TextEditor(text: $importConfigText)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 10)).frame(minHeight: 180)
                    .overlay(alignment: .topLeading) {
                        if importConfigText.isEmpty {
                            Text("Paste exported JSON config here...")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 14).padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal)

                if let result = importResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.summary)
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(.green)
                        if !result.errors.isEmpty {
                            ForEach(result.errors, id: \.self) { error in
                                Text(error)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Import Config").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showImportSheet = false; importConfigText = ""; importResult = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let result = AppDataExportService.shared.importJSON(importConfigText)
                        importResult = result
                        vm.log(result.summary, level: result.errors.isEmpty ? .success : .warning)
                        if result.errors.isEmpty {
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                showImportSheet = false
                                importConfigText = ""
                                importResult = nil
                            }
                        }
                    }
                    .disabled(importConfigText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: $showImportFileImporter, allowedContentTypes: [.json, .plainText], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                        importConfigText = text
                    }
                case .failure(let error):
                    vm.log("File import error: \(error.localizedDescription)", level: .error)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "8.0.0")
            LabeledContent("Engine", value: "WKWebView Live")
            LabeledContent("Storage", value: "Unlimited · Local + iCloud")
            LabeledContent("Stealth") { Text(vm.stealthEnabled ? "Ultra Stealth" : "Standard").foregroundStyle(vm.stealthEnabled ? .purple : .secondary) }
            LabeledContent("Connection") {
                Text(proxyService.ppsrConnectionMode.label)
                    .foregroundStyle(proxyService.ppsrConnectionMode == .proxy ? .blue : .cyan)
            }
            LabeledContent("Mode") { Text("Live — Real Transactions").foregroundStyle(.orange) }
            Button(role: .destructive) { vm.clearAll() } label: { Label("Clear Session History", systemImage: "trash") }
        } header: {
            Text("About")
        }
    }

    private var cropEditorSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Focus Crop Area").font(.headline)
                    Text("Define a rectangle (in points) to crop from the full-page screenshot.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        cropField("X", text: $cropX)
                        cropField("Y", text: $cropY)
                    }
                    HStack(spacing: 12) {
                        cropField("Width", text: $cropW)
                        cropField("Height", text: $cropH)
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Focus Crop").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showCropEditor = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let x = Double(cropX) ?? 0; let y = Double(cropY) ?? 0
                        let w = Double(cropW) ?? 0; let h = Double(cropH) ?? 0
                        if w > 0 && h > 0 {
                            vm.screenshotCropRect = CGRect(x: x, y: y, width: w, height: h)
                            vm.log("Set focus crop: \(Int(x)),\(Int(y)) \(Int(w))×\(Int(h))")
                        } else {
                            vm.screenshotCropRect = .zero
                        }
                        vm.persistSettings()
                        showCropEditor = false
                    }
                }
            }
        }
        .presentationDetents([.medium]).presentationDragIndicator(.visible)
    }

    private func cropField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            TextField("0", text: text)
                .keyboardType(.numberPad).font(.system(.body, design: .monospaced))
                .padding(10).background(Color(.tertiarySystemGroupedBackground)).clipShape(.rect(cornerRadius: 8))
        }
    }

    private var emailImportSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import Emails").font(.headline)
                    Text("Paste email addresses separated by commas or newlines.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $emailCSVText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(12)
                    .background(Color(.tertiarySystemGroupedBackground)).clipShape(.rect(cornerRadius: 10))
                    .frame(minHeight: 180)
                Spacer()
            }
            .padding()
            .navigationTitle("Import Emails").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showEmailImport = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let count = vm.importEmails(emailCSVText)
                        emailCSVText = ""
                        showEmailImport = false
                        vm.log("Imported \(count) emails for rotation", level: .success)
                    }
                    .disabled(emailCSVText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

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
