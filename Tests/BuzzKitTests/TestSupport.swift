import Foundation
@testable import BuzzKit

final class MockURLProtocol: URLProtocol {
    private static let state = LockedState<(
        handlers: [String: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)],
        requests: [String: [URLRequest]]
    )>((handlers: [:], requests: [:]))

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let handler = Self.state.withLock { state -> (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? in
            state.requests[key, default: []].append(self.request)
            return state.handlers[key]
        }
        do {
            guard let handler else { throw URLError(.badURL) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func register(key: String, handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        state.withLock { $0.handlers["Bearer " + key] = handler }
    }

    static func requests(key: String) -> [URLRequest] {
        state.withLock { $0.requests["Bearer " + key] ?? [] }
    }
}

struct MockAPI {
    let key = "bk_pk_test_" + UUID().uuidString.lowercased()

    func client(maxAttempts: Int = 3) -> HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return HTTPClient(
            baseURL: URL(string: "https://api.test.buzzkit.dev")!,
            apiKey: key,
            logger: BKLogger(level: .none),
            session: URLSession(configuration: configuration),
            maxAttempts: maxAttempts,
            sleep: { _ in }
        )
    }

    func stub(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        MockURLProtocol.register(key: key, handler: handler)
    }

    func requests() -> [URLRequest] {
        MockURLProtocol.requests(key: key)
    }
}

func jsonResponse(_ status: Int, _ body: String, url: URL = URL(string: "https://api.test.buzzkit.dev")!) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    return (response, Data(body.utf8))
}

func bodyData(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var body = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: 4096)
        if read <= 0 { break }
        body.append(buffer, count: read)
    }
    return body
}
