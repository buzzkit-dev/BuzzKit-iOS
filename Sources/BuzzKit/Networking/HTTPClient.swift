import Foundation

struct HTTPRequest: Sendable {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    var method: Method
    var path: String
    var body: Data?
    var headers: [String: String]
}

actor HTTPClient {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private let logger: BKLogger
    private let maxAttempts: Int
    private let sleep: @Sendable (UInt64) async -> Void

    init(
        baseURL: URL,
        apiKey: String,
        logger: BKLogger,
        session: URLSession = HTTPClient.makeSession(),
        maxAttempts: Int = 3,
        sleep: @escaping @Sendable (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.logger = logger
        self.maxAttempts = maxAttempts
        self.sleep = sleep
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    func send<Value: Decodable & Sendable>(
        _ request: HTTPRequest,
        as type: Value.Type
    ) async throws -> Value {
        let data = try await perform(request)
        let envelope: Envelope<Value>
        do {
            envelope = try JSONCoding.decoder.decode(Envelope<Value>.self, from: data)
        } catch {
            logger.error("Undecodable response for \(request.path): \(error)")
            throw BuzzKitError.invalidResponse
        }
        if let value = envelope.data, envelope.success {
            return value
        }
        if let problem = envelope.error {
            throw BuzzKitError.api(code: problem.code, message: problem.message)
        }
        throw BuzzKitError.invalidResponse
    }

    private func perform(_ request: HTTPRequest) async throws -> Data {
        var attempt = 0
        var lastError: Error = BuzzKitError.invalidResponse
        while attempt < maxAttempts {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: urlRequest(for: request))
                guard let http = response as? HTTPURLResponse else { throw BuzzKitError.invalidResponse }
                if http.statusCode < 500, http.statusCode != 429 {
                    return data
                }
                logger.warn("\(request.method.rawValue) \(request.path) answered \(http.statusCode)")
                if attempt < maxAttempts {
                    await sleep(retryDelay(for: attempt, response: http))
                    continue
                }
                throw BuzzKitError.network(underlying: URLError(.badServerResponse))
            } catch let error as BuzzKitError {
                throw error
            } catch {
                lastError = error
                logger.warn("\(request.method.rawValue) \(request.path) failed: \(error.localizedDescription)")
                if attempt < maxAttempts {
                    await sleep(retryDelay(for: attempt, response: nil))
                }
            }
        }
        throw BuzzKitError.network(underlying: lastError)
    }

    private func urlRequest(for request: HTTPRequest) -> URLRequest {
        var url = URLRequest(url: baseURL.appendingPathComponent(request.path))
        url.httpMethod = request.method.rawValue
        url.httpBody = request.body
        url.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        url.setValue("application/json", forHTTPHeaderField: "Content-Type")
        url.setValue(SDKInfo.userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in request.headers {
            url.setValue(value, forHTTPHeaderField: name)
        }
        return url
    }

    private func retryDelay(for attempt: Int, response: HTTPURLResponse?) -> UInt64 {
        if let after = response?.value(forHTTPHeaderField: "Retry-After"), let seconds = Double(after) {
            return UInt64(min(seconds, 30) * 1_000_000_000)
        }
        let base = pow(2, Double(attempt - 1))
        let jitter = Double.random(in: 0...0.4)
        return UInt64(min(base + jitter, 20) * 1_000_000_000)
    }
}

enum JSONCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601.date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(raw)")
            }
            return date
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, container in
            var single = container.singleValueContainer()
            try single.encode(ISO8601.string(from: date))
        }
        return encoder
    }()
}

enum ISO8601 {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    static func date(from string: String) -> Date? {
        (try? fractional.parse(string)) ?? (try? plain.parse(string))
    }

    static func string(from date: Date) -> String {
        fractional.format(date)
    }
}

enum SDKInfo {
    static let version = "0.1.0"
    static var userAgent: String {
        "buzzkit-ios/\(version)"
    }
}
