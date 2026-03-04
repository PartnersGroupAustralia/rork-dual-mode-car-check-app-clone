import Foundation

nonisolated struct WireGuardConfig: Identifiable, Codable, Sendable {
    let id: UUID
    let fileName: String
    let interfaceAddress: String
    let interfacePrivateKey: String
    let interfaceDNS: String
    let peerPublicKey: String
    let peerEndpoint: String
    let peerAllowedIPs: String
    let peerPersistentKeepalive: Int?
    let rawContent: String
    var isEnabled: Bool
    var importedAt: Date

    init(
        fileName: String,
        interfaceAddress: String,
        interfacePrivateKey: String,
        interfaceDNS: String,
        peerPublicKey: String,
        peerEndpoint: String,
        peerAllowedIPs: String,
        peerPersistentKeepalive: Int?,
        rawContent: String
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.interfaceAddress = interfaceAddress
        self.interfacePrivateKey = interfacePrivateKey
        self.interfaceDNS = interfaceDNS
        self.peerPublicKey = peerPublicKey
        self.peerEndpoint = peerEndpoint
        self.peerAllowedIPs = peerAllowedIPs
        self.peerPersistentKeepalive = peerPersistentKeepalive
        self.rawContent = rawContent
        self.isEnabled = true
        self.importedAt = Date()
    }

    var endpointHost: String {
        let parts = peerEndpoint.components(separatedBy: ":")
        return parts.first ?? peerEndpoint
    }

    var endpointPort: Int {
        let parts = peerEndpoint.components(separatedBy: ":")
        if parts.count >= 2, let port = Int(parts.last ?? "") { return port }
        return 51820
    }

    var displayString: String {
        "\(endpointHost):\(endpointPort)"
    }

    var serverName: String {
        let host = endpointHost
        if host.contains("nordvpn.com") {
            return host.replacingOccurrences(of: ".nordvpn.com", with: "")
        }
        return host
    }

    var statusLabel: String {
        isEnabled ? "Enabled" : "Disabled"
    }

    static func parse(fileName: String, content: String) -> WireGuardConfig? {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var address = ""
        var privateKey = ""
        var dns = ""
        var publicKey = ""
        var endpoint = ""
        var allowedIPs = "0.0.0.0/0"
        var keepalive: Int?

        nonisolated enum Section { case none, interface_, peer }
        var currentSection: Section = .none

        for line in lines {
            let lower = line.lowercased()

            if lower.hasPrefix("[interface]") { currentSection = .interface_; continue }
            if lower.hasPrefix("[peer]") { currentSection = .peer; continue }

            guard line.contains("=") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch currentSection {
            case .interface_:
                switch key {
                case "address": address = value
                case "privatekey": privateKey = value
                case "dns": dns = value
                default: break
                }
            case .peer:
                switch key {
                case "publickey": publicKey = value
                case "endpoint": endpoint = value
                case "allowedips": allowedIPs = value
                case "persistentkeepalive": keepalive = Int(value)
                default: break
                }
            case .none:
                break
            }
        }

        guard !privateKey.isEmpty, !publicKey.isEmpty, !endpoint.isEmpty else { return nil }

        if address.isEmpty { address = "10.5.0.2/32" }

        return WireGuardConfig(
            fileName: fileName,
            interfaceAddress: address,
            interfacePrivateKey: privateKey,
            interfaceDNS: dns,
            peerPublicKey: publicKey,
            peerEndpoint: endpoint,
            peerAllowedIPs: allowedIPs,
            peerPersistentKeepalive: keepalive,
            rawContent: content
        )
    }
}
