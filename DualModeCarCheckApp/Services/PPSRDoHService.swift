import Foundation

nonisolated struct DoHProvider: Sendable {
    let name: String
    let url: String
}

nonisolated struct DNSAnswer: Sendable {
    let ip: String
    let provider: String
    let latencyMs: Int
}

nonisolated struct DoHResponse: Codable, Sendable {
    let Status: Int?
    let Answer: [DoHAnswerEntry]?
}

nonisolated struct DoHAnswerEntry: Codable, Sendable {
    let name: String?
    let type: Int?
    let TTL: Int?
    let data: String?
}

@MainActor
class PPSRDoHService {
    static let shared = PPSRDoHService()

    private var providerIndex: Int = 0

    let providers: [DoHProvider] = [
        DoHProvider(name: "Cloudflare", url: "https://cloudflare-dns.com/dns-query"),
        DoHProvider(name: "Google", url: "https://dns.google/dns-query"),
        DoHProvider(name: "Quad9", url: "https://dns.quad9.net:5053/dns-query"),
        DoHProvider(name: "OpenDNS", url: "https://doh.opendns.com/dns-query"),
        DoHProvider(name: "Mullvad", url: "https://dns.mullvad.net/dns-query"),
        DoHProvider(name: "AdGuard", url: "https://dns.adguard-dns.com/dns-query"),
        DoHProvider(name: "NextDNS", url: "https://dns.nextdns.io/dns-query"),
        DoHProvider(name: "ControlD", url: "https://freedns.controld.com/p0"),
        DoHProvider(name: "CleanBrowsing", url: "https://doh.cleanbrowsing.org/doh/security-filter/"),
        DoHProvider(name: "DNS.SB", url: "https://doh.dns.sb/dns-query"),
    ]

    var currentProvider: DoHProvider {
        providers[providerIndex % providers.count]
    }

    func nextProvider() -> DoHProvider {
        let provider = providers[providerIndex % providers.count]
        providerIndex += 1
        return provider
    }

    func resolveWithRotation(hostname: String) async -> DNSAnswer? {
        for _ in 0..<3 {
            let provider = nextProvider()
            if let answer = await resolve(hostname: hostname, using: provider) {
                return answer
            }
        }
        return nil
    }

    func resolve(hostname: String, using provider: DoHProvider) async -> DNSAnswer? {
        guard var components = URLComponents(string: provider.url) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "name", value: hostname),
            URLQueryItem(name: "type", value: "A"),
        ]
        guard let url = components.url else { return nil }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 8)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let latency = Int(Date().timeIntervalSince(start) * 1000)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            guard !data.isEmpty else { return nil }

            let decoded = try JSONDecoder().decode(DoHResponse.self, from: data)

            guard decoded.Status == 0 || decoded.Status == nil else { return nil }

            guard let answers = decoded.Answer,
                  let aRecord = answers.first(where: { $0.type == 1 }),
                  let ip = aRecord.data,
                  !ip.isEmpty else {
                return nil
            }

            return DNSAnswer(ip: ip, provider: provider.name, latencyMs: latency)
        } catch {
            return nil
        }
    }

    func preflightResolve(hostname: String) async -> (provider: String, ip: String, latencyMs: Int)? {
        for _ in 0..<3 {
            let provider = nextProvider()
            if let answer = await resolve(hostname: hostname, using: provider) {
                return (provider: answer.provider, ip: answer.ip, latencyMs: answer.latencyMs)
            }
        }
        return nil
    }

    var providerCount: Int {
        providers.count
    }

    var allProviderNames: [String] {
        providers.map(\.name)
    }

    func resetRotation() {
        providerIndex = 0
    }
}
