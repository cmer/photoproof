// ImmichClient.swift
// Async/await client for the subset of the Immich API used by PhotoProof:
//   GET  /api/users/me                 — Test Connection
//   POST /api/assets/bulk-upload-check — does this SHA1 already exist?
//   POST /api/search/metadata          — and is the matching asset trashed?
//
// Transient errors (network drops, 502/503/504) are retried with exponential
// backoff (250ms, 1s, 4s) up to 3 times. Authentication failures and other
// non-transient HTTP errors fail fast.

import Foundation

struct ImmichUser: Codable, Equatable, Sendable {
    let id: String
    let email: String
    let name: String
}

enum ImmichError: Error, LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case notFound
    case server(Int)
    case offline
    case timedOut
    case decoding
    case other(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That URL doesn't look right. It should be like https://immich.example.com."
        case .unauthorized:
            return "Server reachable but the API key was rejected."
        case .notFound:
            return "Couldn't find Immich at that URL — check the address."
        case .server(let code):
            return "Server returned HTTP \(code)."
        case .offline:
            return "Couldn't reach the server. Is it running and on the network?"
        case .timedOut:
            return "The server took too long to respond."
        case .decoding:
            return "Got a response but couldn't read it as Immich JSON. Is this really an Immich server?"
        case .other(let message):
            return message
        }
    }
}

final class ImmichClient: Sendable {

    static let bulkBatchSize = 200
    static let retryDelays: [TimeInterval] = [0.25, 1.0, 4.0]

    let baseURL: URL
    let apiKey: String
    private let session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    /// Normalize a user-pasted URL: trim whitespace, drop trailing slashes, and
    /// drop a trailing /api so the user can paste either form. Returns nil if
    /// the result isn't a valid http(s) URL with a host.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/api") { s.removeLast(4) }
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty,
              let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else {
            return nil
        }
        return url
    }

    // MARK: - Endpoints

    func ping() async throws -> ImmichUser {
        let req = makeRequest(path: "api/users/me", method: "GET", body: nil)
        let data = try await execute(req, allowRetry: false)
        do {
            return try JSONDecoder().decode(ImmichUser.self, from: data)
        } catch {
            throw ImmichError.decoding
        }
    }

    /// POST /api/assets/bulk-upload-check.
    /// `pairs` is a single batch — caller is responsible for chunking to
    /// `Self.bulkBatchSize` and managing concurrency.
    /// Returns a map of `id` → `action` ("accept" | "reject" | other).
    func bulkUploadCheck(_ pairs: [(id: String, sha1: String)]) async throws -> [String: String] {
        struct Body: Encodable {
            struct Asset: Encodable { let id: String; let checksum: String }
            let assets: [Asset]
        }
        struct Response: Decodable {
            struct Result: Decodable {
                let id: String
                let action: String
            }
            let results: [Result]
        }
        let body = Body(assets: pairs.map { .init(id: $0.id, checksum: $0.sha1) })
        let bodyData = try JSONEncoder().encode(body)
        let req = makeRequest(path: "api/assets/bulk-upload-check", method: "POST", body: bodyData)
        let data = try await execute(req, allowRetry: true)
        let resp: Response
        do {
            resp = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ImmichError.decoding
        }
        var out: [String: String] = [:]
        out.reserveCapacity(resp.results.count)
        for r in resp.results { out[r.id] = r.action }
        return out
    }

    /// POST /api/search/metadata with `withDeleted: true`.
    /// Returns the first matching asset, or nil if none found.
    func findAssetByChecksum(_ sha1: String) async throws -> SearchAsset? {
        struct Body: Encodable {
            let checksum: String
            let size: Int
            let page: Int
            let withDeleted: Bool
        }
        struct Response: Decodable {
            struct Assets: Decodable { let items: [SearchAsset] }
            let assets: Assets
        }
        let body = Body(checksum: sha1, size: 1, page: 1, withDeleted: true)
        let bodyData = try JSONEncoder().encode(body)
        let req = makeRequest(path: "api/search/metadata", method: "POST", body: bodyData)
        let data = try await execute(req, allowRetry: true)
        do {
            let resp = try JSONDecoder().decode(Response.self, from: data)
            return resp.assets.items.first
        } catch {
            throw ImmichError.decoding
        }
    }

    struct SearchAsset: Decodable, Sendable {
        let id: String
        let isTrashed: Bool
    }

    // MARK: - Private

    private func makeRequest(path: String, method: String, body: Data?) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        req.timeoutInterval = 60
        return req
    }

    private func execute(_ request: URLRequest, allowRetry: Bool) async throws -> Data {
        let attempts = allowRetry ? Self.retryDelays.count + 1 : 1
        var lastError: ImmichError = .other("No attempt made")

        for attempt in 0..<attempts {
            if attempt > 0 {
                let delay = Self.retryDelays[attempt - 1]
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            if Task.isCancelled { throw CancellationError() }

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = .other("Unexpected response type.")
                    continue
                }
                switch http.statusCode {
                case 200..<300:
                    return data
                case 401, 403:
                    throw ImmichError.unauthorized
                case 404:
                    throw ImmichError.notFound
                case 502, 503, 504:
                    lastError = .server(http.statusCode)
                    continue  // retry transient server errors
                default:
                    throw ImmichError.server(http.statusCode)
                }
            } catch let urlError as URLError {
                switch urlError.code {
                case .timedOut:
                    lastError = .timedOut
                    continue
                case .notConnectedToInternet, .networkConnectionLost,
                     .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost:
                    lastError = .offline
                    continue
                case .cancelled:
                    throw CancellationError()
                default:
                    lastError = .other(urlError.localizedDescription)
                    continue
                }
            } catch let immichError as ImmichError {
                throw immichError  // non-transient: don't retry
            }
        }
        throw lastError
    }
}
