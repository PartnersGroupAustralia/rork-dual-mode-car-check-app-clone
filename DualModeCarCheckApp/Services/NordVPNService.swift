import Foundation
import Observation

nonisolated struct NordVPNServer: Codable, Sendable {
    let id: Int
    let hostname: String
    let station: String
    let load: Int
    let locations: [NordLocation]?
    let technologies: [NordTechnology]?

    var publicKey: String? {
        technologies?.first(where: { $0.identifier == "wireguard_udp" })?
            .metadata?.first?.value
    }

    var hasOpenVPNTCP: Bool {
        technologies?.contains(where: { $0.identifier == "openvpn_tcp" }) ?? false
    }

    var hasOpenVPNUDP: Bool {
        technologies?.contains(where: { $0.identifier == "openvpn_udp" }) ?? false
    }

    var city: String? {
        locations?.first?.country?.city?.name
    }

    var country: String? {
        locations?.first?.country?.name
    }

    var tcpOVPNDownloadURL: URL? {
        URL(string: "https://downloads.nordcdn.com/configs/files/ovpn_tcp/servers/\(hostname).tcp.ovpn")
    }

    var udpOVPNDownloadURL: URL? {
        URL(string: "https://downloads.nordcdn.com/configs/files/ovpn_udp/servers/\(hostname).udp.ovpn")
    }
}

nonisolated struct NordLocation: Codable, Sendable {
    let country: NordCountry?
}

nonisolated struct NordCountry: Codable, Sendable {
    let name: String?
    let city: NordCity?
}

nonisolated struct NordCity: Codable, Sendable {
    let name: String?
}

nonisolated struct NordTechnology: Codable, Sendable {
    let id: Int?
    let identifier: String?
    let metadata: [NordMetadata]?
}

nonisolated struct NordMetadata: Codable, Sendable {
    let name: String?
    let value: String?
}

nonisolated struct NordCredentials: Codable, Sendable {
    let nordlynx_private_key: String?
}

@Observable
@MainActor
class NordVPNService {
    static let shared = NordVPNService()

    var accessKey: String = ""
    var privateKey: String = ""
    var isLoadingServers: Bool = false
    var isLoadingKey: Bool = false
    var lastError: String?
    var recommendedServers: [NordVPNServer] = []
    var lastFetched: Date?

    private let accessKeyPersistKey = "nordvpn_access_key_v1"
    private let privateKeyPersistKey = "nordvpn_private_key_v1"
    private let logger = DebugLogger.shared

    init() {
        accessKey = UserDefaults.standard.string(forKey: accessKeyPersistKey) ?? ""
        privateKey = UserDefaults.standard.string(forKey: privateKeyPersistKey) ?? ""
    }

    func setAccessKey(_ key: String) {
        accessKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(accessKey, forKey: accessKeyPersistKey)
    }

    func setPrivateKey(_ key: String) {
        privateKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(privateKey, forKey: privateKeyPersistKey)
    }

    var hasAccessKey: Bool { !accessKey.isEmpty }
    var hasPrivateKey: Bool { !privateKey.isEmpty }

    func fetchPrivateKey() async {
        guard hasAccessKey else {
            lastError = "No access key configured"
            return
        }

        isLoadingKey = true
        lastError = nil
        defer { isLoadingKey = false }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        guard let url = URL(string: "https://api.nordvpn.com/v1/users/services/credentials") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let credentials = "token:\(accessKey)"
        if let credData = credentials.data(using: .utf8) {
            request.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                lastError = "API returned HTTP \(http.statusCode)"
                logger.log("NordVPN: fetchPrivateKey failed — HTTP \(http.statusCode)", category: .vpn, level: .error, metadata: ["statusCode": "\(http.statusCode)"])
                return
            }
            let creds = try JSONDecoder().decode(NordCredentials.self, from: data)
            if let pk = creds.nordlynx_private_key, !pk.isEmpty {
                setPrivateKey(pk)
                logger.log("NordVPN: private key fetched successfully", category: .vpn, level: .success)
            } else {
                lastError = "No private key in response"
                logger.log("NordVPN: response missing nordlynx_private_key", category: .vpn, level: .error)
            }
        } catch {
            lastError = "Failed to fetch key: \(error.localizedDescription)"
            logger.logError("NordVPN: fetchPrivateKey network error", error: error, category: .vpn)
        }
    }

    var isDownloadingOVPN: Bool = false
    var ovpnDownloadProgress: String = ""

    func fetchRecommendedServers(country: String? = nil, limit: Int = 10, technology: String = "openvpn_tcp") async {
        isLoadingServers = true
        lastError = nil
        defer { isLoadingServers = false }

        var urlString = "https://api.nordvpn.com/v1/servers/recommendations?filters[servers_technologies][identifier]=\(technology)&limit=\(limit)"
        if let country = country {
            urlString += "&filters[country_id]=\(country)"
        }

        guard let url = URL(string: urlString) else {
            lastError = "Invalid API URL"
            return
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                lastError = "API returned HTTP \(http.statusCode)"
                logger.log("NordVPN: fetchServers failed — HTTP \(http.statusCode)", category: .vpn, level: .error)
                return
            }
            let servers = try JSONDecoder().decode([NordVPNServer].self, from: data)
            recommendedServers = servers
            lastFetched = Date()
            logger.log("NordVPN: fetched \(servers.count) servers (tech: \(technology))", category: .vpn, level: .success)
        } catch {
            lastError = "Failed to fetch servers: \(error.localizedDescription)"
            logger.logError("NordVPN: fetchServers error", error: error, category: .vpn)
        }
    }

    func downloadOVPNConfig(from server: NordVPNServer, proto: NordOVPNProto = .tcp) async -> OpenVPNConfig? {
        let downloadURL: URL?
        switch proto {
        case .tcp: downloadURL = server.tcpOVPNDownloadURL
        case .udp: downloadURL = server.udpOVPNDownloadURL
        }

        guard let url = downloadURL else {
            logger.log("NordVPN: no download URL for \(server.hostname) (\(proto.rawValue))", category: .vpn, level: .error)
            return nil
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                logger.log("NordVPN: OVPN download HTTP \(http.statusCode) for \(server.hostname)", category: .vpn, level: .error)
                return nil
            }
            guard let content = String(data: data, encoding: .utf8), !content.isEmpty else {
                logger.log("NordVPN: OVPN download empty/non-UTF8 for \(server.hostname)", category: .vpn, level: .error)
                return nil
            }
            let fileName = "\(server.hostname).\(proto == .tcp ? "tcp" : "udp").ovpn"
            let parsed = OpenVPNConfig.parse(fileName: fileName, content: content)
            if parsed != nil {
                logger.log("NordVPN: downloaded \(fileName) (\(data.count) bytes)", category: .vpn, level: .success)
            } else {
                logger.log("NordVPN: OVPN parse failed for \(fileName) (\(data.count) bytes)", category: .vpn, level: .error)
            }
            return parsed
        } catch {
            logger.logError("NordVPN: OVPN download error for \(server.hostname)", error: error, category: .vpn)
            return nil
        }
    }

    func downloadAllTCPConfigs(for servers: [NordVPNServer], target: ProxyRotationService.ProxyTarget) async -> (imported: Int, failed: Int) {
        isDownloadingOVPN = true
        ovpnDownloadProgress = "0/\(servers.count)"
        defer {
            isDownloadingOVPN = false
            ovpnDownloadProgress = ""
        }

        let proxyService = ProxyRotationService.shared
        var imported = 0
        var failed = 0

        for (index, server) in servers.enumerated() {
            ovpnDownloadProgress = "\(index + 1)/\(servers.count)"
            if let config = await downloadOVPNConfig(from: server, proto: .tcp) {
                proxyService.importVPNConfig(config, for: target)
                imported += 1
            } else {
                failed += 1
            }
        }

        return (imported, failed)
    }

    func fetchAndDownloadTCPServers(country: String? = nil, limit: Int = 10, target: ProxyRotationService.ProxyTarget) async -> (imported: Int, failed: Int) {
        await fetchRecommendedServers(country: country, limit: limit, technology: "openvpn_tcp")
        guard !recommendedServers.isEmpty else {
            return (0, 0)
        }
        return await downloadAllTCPConfigs(for: recommendedServers, target: target)
    }

    func generateWireGuardConfig(from server: NordVPNServer) -> WireGuardConfig? {
        guard let publicKey = server.publicKey, !publicKey.isEmpty else { return nil }
        guard hasPrivateKey else { return nil }

        let endpoint = "\(server.station):51820"
        let rawContent = """
        [Interface]
        PrivateKey = \(privateKey)
        Address = 10.5.0.2/32
        DNS = 103.86.96.100, 103.86.99.100

        [Peer]
        PublicKey = \(publicKey)
        AllowedIPs = 0.0.0.0/0
        Endpoint = \(endpoint)
        PersistentKeepalive = 25
        """

        return WireGuardConfig(
            fileName: server.hostname,
            interfaceAddress: "10.5.0.2/32",
            interfacePrivateKey: privateKey,
            interfaceDNS: "103.86.96.100, 103.86.99.100",
            interfaceMTU: nil,
            peerPublicKey: publicKey,
            peerPreSharedKey: nil,
            peerEndpoint: endpoint,
            peerAllowedIPs: "0.0.0.0/0",
            peerPersistentKeepalive: 25,
            rawContent: rawContent
        )
    }

    func generateOpenVPNEndpoint(from server: NordVPNServer, proto: String = "tcp", port: Int = 443) -> OpenVPNConfig {
        let rawContent = """
        client
        dev tun
        proto \(proto)
        remote \(server.hostname) \(port)
        resolv-retry infinite
        nobind
        persist-key
        persist-tun
        remote-cert-tls server
        cipher AES-256-GCM
        auth SHA512
        verb 3
        """

        return OpenVPNConfig(
            fileName: server.hostname,
            remoteHost: server.hostname,
            remotePort: port,
            proto: proto,
            rawContent: rawContent
        )
    }
}

nonisolated enum NordOVPNProto: String, Sendable {
    case tcp
    case udp
}
