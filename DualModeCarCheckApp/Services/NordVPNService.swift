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

    var city: String? {
        locations?.first?.country?.city?.name
    }

    var country: String? {
        locations?.first?.country?.name
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
                return
            }
            let creds = try JSONDecoder().decode(NordCredentials.self, from: data)
            if let pk = creds.nordlynx_private_key, !pk.isEmpty {
                setPrivateKey(pk)
            } else {
                lastError = "No private key in response"
            }
        } catch {
            lastError = "Failed to fetch key: \(error.localizedDescription)"
        }
    }

    func fetchRecommendedServers(country: String? = nil, limit: Int = 10, technology: String = "wireguard_udp") async {
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
                return
            }
            let servers = try JSONDecoder().decode([NordVPNServer].self, from: data)
            recommendedServers = servers
            lastFetched = Date()
        } catch {
            lastError = "Failed to fetch servers: \(error.localizedDescription)"
        }
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

    func generateOpenVPNEndpoint(from server: NordVPNServer, proto: String = "udp", port: Int = 1194) -> OpenVPNConfig {
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
