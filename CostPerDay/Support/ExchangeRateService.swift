import Foundation

struct ExchangeRateSnapshot: Codable, Sendable {
    let baseCode: String
    let fetchedAt: Date
    let rates: [String: Double]
}

enum ExchangeRateError: LocalizedError, Sendable {
    case network
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .network: "Couldn't reach the exchange rate service."
        case .unavailable(let code): "No rate is published for \(code)."
        }
    }
}

/// Fetches exchange rates and caches them locally so quotes keep working offline
/// after the first successful fetch. One request per base currency returns rates
/// to every target currency at once, so switching the target never costs another
/// round trip.
actor ExchangeRateService {
    static let shared = ExchangeRateService()

    struct Quote: Sendable {
        let rate: Double
        let asOf: Date
        /// True when this came from the local cache rather than a fresh network hit —
        /// either because the cache is still fresh, or because the fetch just failed
        /// and this is the offline fallback.
        let servedFromCache: Bool
    }

    /// Cached rates newer than this are used as-is without hitting the network.
    /// Older ones still serve as an offline fallback if a fresh fetch fails.
    private let refreshInterval: TimeInterval = 12 * 3600

    private let session: URLSession
    private let defaults: UserDefaults
    private let cacheKey: String
    private var cache: [String: ExchangeRateSnapshot]

    init(session: URLSession = .shared, defaults: UserDefaults = .standard, cacheKey: String = "exchangeRateCache_v1") {
        self.session = session
        self.defaults = defaults
        self.cacheKey = cacheKey
        self.cache = Self.load(from: defaults, key: cacheKey)
    }

    func quote(from: String, to: String) async -> Result<Quote, ExchangeRateError> {
        guard from != to else { return .success(Quote(rate: 1, asOf: .now, servedFromCache: false)) }

        if let snapshot = cache[from],
           Date.now.timeIntervalSince(snapshot.fetchedAt) < refreshInterval,
           let rate = snapshot.rates[to] {
            return .success(Quote(rate: rate, asOf: snapshot.fetchedAt, servedFromCache: true))
        }

        do {
            let snapshot = try await fetch(base: from)
            cache[from] = snapshot
            persist()
            guard let rate = snapshot.rates[to] else {
                return fallback(from: from, to: to) ?? .failure(.unavailable(to))
            }
            return .success(Quote(rate: rate, asOf: snapshot.fetchedAt, servedFromCache: false))
        } catch {
            return fallback(from: from, to: to) ?? .failure(.network)
        }
    }

    private func fallback(from: String, to: String) -> Result<Quote, ExchangeRateError>? {
        guard let snapshot = cache[from], let rate = snapshot.rates[to] else { return nil }
        return .success(Quote(rate: rate, asOf: snapshot.fetchedAt, servedFromCache: true))
    }

    private func fetch(base: String) async throws -> ExchangeRateSnapshot {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(base)") else {
            throw ExchangeRateError.network
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExchangeRateError.network
        }
        struct Payload: Decodable {
            let result: String
            let base_code: String
            let rates: [String: Double]
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ExchangeRateError.network
        }
        guard payload.result == "success" else { throw ExchangeRateError.network }
        return ExchangeRateSnapshot(baseCode: payload.base_code, fetchedAt: .now, rates: payload.rates)
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [String: ExchangeRateSnapshot] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: ExchangeRateSnapshot].self, from: data)) ?? [:]
    }
}
