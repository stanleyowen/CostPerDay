import Testing
import Foundation
@testable import CostPerDay

/// Thread-safe box for mutable state shared between a test and the URLProtocol
/// callback, which runs on its own queue.
private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

/// Intercepts every request made through a session configured with this protocol,
/// so the rate-fetching tests never touch the real network.
private final class StubURLProtocol: URLProtocol {
    static let handler = Box<(@Sendable (URLRequest) -> (Data?, HTTPURLResponse?, Error?))?>(nil)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler.value else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (data, response, error) = handler(request)
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data {
            client?.urlProtocol(self, didLoad: data)
        }
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private func stubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private func freshDefaults(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func jsonResponse(_ body: [String: Any], for request: URLRequest) -> (Data?, HTTPURLResponse?, Error?) {
    let data = try! JSONSerialization.data(withJSONObject: body)
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
    return (data, response, nil)
}

/// Runs serially: every test mutates the shared `StubURLProtocol.handler`, and
/// parallel execution would let one test's stub answer another test's request.
@Suite("Exchange rate service", .serialized)
struct ExchangeRateServiceTests {
    @Test("Same currency never touches the network")
    func sameCurrencyShortCircuits() async {
        StubURLProtocol.handler.value = { _ in fatalError("should not be called") }
        let service = ExchangeRateService(session: stubbedSession(), defaults: freshDefaults("same-currency"), cacheKey: "k")
        let result = await service.quote(from: "USD", to: "USD")
        guard case .success(let quote) = result else { Issue.record("expected success"); return }
        #expect(quote.rate == 1)
    }

    @Test("A successful fetch returns the rate for the requested target")
    func successfulFetch() async {
        StubURLProtocol.handler.value = { request in
            jsonResponse(["result": "success", "base_code": "USD", "rates": ["TWD": 31.5, "JPY": 149.2]], for: request)
        }
        let service = ExchangeRateService(session: stubbedSession(), defaults: freshDefaults("fetch-success"), cacheKey: "k")
        let result = await service.quote(from: "USD", to: "TWD")
        guard case .success(let quote) = result else { Issue.record("expected success"); return }
        #expect(quote.rate == 31.5)
        #expect(!quote.servedFromCache)
    }

    @Test("A second lookup against the same base reuses the cache instead of refetching")
    func cacheAvoidsRefetch() async {
        let calls = Box(0)
        StubURLProtocol.handler.value = { request in
            calls.value += 1
            return jsonResponse(["result": "success", "base_code": "USD", "rates": ["TWD": 31.5, "JPY": 149.2]], for: request)
        }
        let service = ExchangeRateService(session: stubbedSession(), defaults: freshDefaults("cache-reuse"), cacheKey: "k")
        _ = await service.quote(from: "USD", to: "TWD")
        _ = await service.quote(from: "USD", to: "JPY")
        #expect(calls.value == 1)
    }

    @Test("A network failure with nothing cached is reported as an error")
    func failureWithoutCache() async {
        StubURLProtocol.handler.value = { _ in (nil, nil, URLError(.notConnectedToInternet)) }
        let service = ExchangeRateService(session: stubbedSession(), defaults: freshDefaults("failure-no-cache"), cacheKey: "k")
        let result = await service.quote(from: "USD", to: "TWD")
        guard case .failure = result else { Issue.record("expected failure"); return }
    }

    @Test("A network failure falls back to a previously cached rate")
    func failureFallsBackToCache() async {
        let succeed = Box(true)
        StubURLProtocol.handler.value = { request in
            succeed.value
                ? jsonResponse(["result": "success", "base_code": "USD", "rates": ["TWD": 31.5]], for: request)
                : (nil, nil, URLError(.notConnectedToInternet))
        }
        let service = ExchangeRateService(session: stubbedSession(), defaults: freshDefaults("failure-fallback"), cacheKey: "k")
        _ = await service.quote(from: "USD", to: "TWD") // primes the cache
        succeed.value = false
        let result = await service.quote(from: "USD", to: "TWD")
        guard case .success(let quote) = result else { Issue.record("expected fallback success"); return }
        #expect(quote.rate == 31.5)
        #expect(quote.servedFromCache)
    }

    @Test("A malformed response is treated as a failure, not a crash")
    func malformedResponseIsHandled() async {
        StubURLProtocol.handler.value = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (Data("not json".utf8), response, nil)
        }
        let service = ExchangeRateService(session: stubbedSession(), defaults: freshDefaults("malformed"), cacheKey: "k")
        let result = await service.quote(from: "USD", to: "TWD")
        guard case .failure = result else { Issue.record("expected failure"); return }
    }

    @Test("Rates persist to the defaults suite so a new instance can reuse them")
    func cachePersistsAcrossInstances() async {
        let suiteName = "persist-across-instances"
        let defaults = freshDefaults(suiteName)
        StubURLProtocol.handler.value = { request in
            jsonResponse(["result": "success", "base_code": "USD", "rates": ["TWD": 31.5]], for: request)
        }
        let first = ExchangeRateService(session: stubbedSession(), defaults: defaults, cacheKey: "k")
        _ = await first.quote(from: "USD", to: "TWD")

        StubURLProtocol.handler.value = { _ in fatalError("should not be called — cache should serve this") }
        let second = ExchangeRateService(session: stubbedSession(), defaults: defaults, cacheKey: "k")
        let result = await second.quote(from: "USD", to: "TWD")
        guard case .success(let quote) = result else { Issue.record("expected success from persisted cache"); return }
        #expect(quote.rate == 31.5)
    }
}
