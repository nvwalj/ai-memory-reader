import Foundation

/// Errors worth telling the user apart. Anything else surfaces as `.transport`.
enum GitHubError: LocalizedError, Equatable {
    case notFound(String)
    case needsToken(String)
    case rateLimited(resetsAt: Date?)
    case truncatedTree
    case tooLarge(path: String, bytes: Int)
    case notText(path: String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let slug):
            return "Couldn't find \(slug). Check the spelling, or add a token if it's private."
        case .needsToken(let slug):
            return "\(slug) is private. Add a GitHub token in Settings to read it."
        case .rateLimited(let resetsAt):
            guard let resetsAt else {
                return "GitHub rate limit reached. Add a token in Settings to raise it."
            }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "GitHub rate limit reached — resets at \(formatter.string(from: resetsAt)). "
                 + "Adding a token in Settings raises the limit from 60 to 5,000 requests an hour."
        case .truncatedTree:
            return "This repository is too large for GitHub to list in one response, so some files are missing."
        case .tooLarge(let path, let bytes):
            return "\(path) is \(bytes / 1_000_000) MB — too large to open on device."
        case .notText(let path):
            return "\(path) isn't a text file."
        case .transport(let message):
            return message
        }
    }
}

/// Reads public (and, with a token, private) repositories over the GitHub API.
///
/// Two API calls are enough to open a repository — the repo record for its
/// default branch, and one recursive tree listing. File contents come from
/// `raw.githubusercontent.com`, which is a CDN and doesn't spend API quota, so
/// browsing a repo costs nothing after it's been added. With a token, contents
/// go through the API instead, because raw.githubusercontent.com can't
/// authenticate.
struct GitHubClient: Sendable {
    /// Blobs above this are refused rather than loaded into a text view.
    static let maxFileBytes = 5_000_000

    private let session: URLSession
    private let token: String?

    init(token: String?, session: URLSession = .shared) {
        self.token = token?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.session = session
    }

    // MARK: - Repository

    func repositoryInfo(_ repo: GitHubRepoRef) async throws -> GitHubRepoInfo {
        let data = try await apiData(path: "/repos/\(repo.owner)/\(repo.name)", slug: repo.slug)
        struct Payload: Decodable {
            let default_branch: String
            let `private`: Bool
            let description: String?
        }
        let decoded = try decode(Payload.self, from: data)
        return GitHubRepoInfo(
            defaultBranch: decoded.default_branch,
            isPrivate: decoded.private,
            description: decoded.description
        )
    }

    // MARK: - Tree

    /// The full recursive listing at `ref`. `truncated` is carried through rather
    /// than thrown, so a huge repo still browses — the UI warns instead.
    func tree(_ repo: GitHubRepoRef, ref: String) async throws -> GitHubTree {
        let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
        let data = try await apiData(
            path: "/repos/\(repo.owner)/\(repo.name)/git/trees/\(encodedRef)",
            query: [URLQueryItem(name: "recursive", value: "1")],
            slug: repo.slug
        )
        struct Payload: Decodable {
            struct Entry: Decodable {
                let path: String
                let type: String
                let sha: String
                let size: Int?
            }
            let sha: String
            let tree: [Entry]
            let truncated: Bool
        }
        let decoded = try decode(Payload.self, from: data)
        return GitHubTree(
            sha: decoded.sha,
            entries: decoded.tree.map {
                GitHubTreeEntry(path: $0.path, type: $0.type, sha: $0.sha, size: $0.size)
            },
            truncated: decoded.truncated,
            fetchedAt: Date()
        )
    }

    // MARK: - File contents

    func fileText(_ repo: GitHubRepoRef, ref: String, path: String, knownSize: Int?) async throws -> String {
        if let knownSize, knownSize > Self.maxFileBytes {
            throw GitHubError.tooLarge(path: path, bytes: knownSize)
        }
        let data = try await fileData(repo, ref: ref, path: path)
        guard data.count <= Self.maxFileBytes else {
            throw GitHubError.tooLarge(path: path, bytes: data.count)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw GitHubError.notText(path: path)
        }
        return text
    }

    func fileData(_ repo: GitHubRepoRef, ref: String, path: String) async throws -> Data {
        var request: URLRequest
        if token != nil {
            // raw.githubusercontent.com takes no credentials, so private repos
            // have to go through the API's raw media type instead.
            let encoded = path
                .split(separator: "/")
                .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                .joined(separator: "/")
            var components = URLComponents(string: "https://api.github.com/repos/\(repo.owner)/\(repo.name)/contents/\(encoded)")!
            components.queryItems = [URLQueryItem(name: "ref", value: ref)]
            request = URLRequest(url: components.url!)
            request.setValue("application/vnd.github.raw", forHTTPHeaderField: "Accept")
        } else {
            let encoded = path
                .split(separator: "/")
                .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                .joined(separator: "/")
            let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
            guard let url = URL(string: "https://raw.githubusercontent.com/\(repo.owner)/\(repo.name)/\(encodedRef)/\(encoded)") else {
                throw GitHubError.notFound(path)
            }
            request = URLRequest(url: url)
        }
        applyCommonHeaders(to: &request)
        return try await send(request, slug: "\(repo.slug)/\(path)")
    }

    // MARK: - Plumbing

    private func apiData(path: String, query: [URLQueryItem] = [], slug: String) async throws -> Data {
        var components = URLComponents(string: "https://api.github.com" + path)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw GitHubError.notFound(slug) }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        applyCommonHeaders(to: &request)
        return try await send(request, slug: slug)
    }

    private func applyCommonHeaders(to request: inout URLRequest) {
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AIMemoryReader", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 30
    }

    private func send(_ request: URLRequest, slug: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            // A cancelled request is SwiftUI tearing down a `.task`, not a
            // failure. Surface it as cancellation so callers can stay silent
            // instead of telling the user their repository is unreachable.
            if error.code == .cancelled { throw CancellationError() }
            throw GitHubError.transport(friendly(error))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GitHubError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw GitHubError.needsToken(slug)
        case 403, 429:
            // GitHub uses 403 for both "out of quota" and "not yours". The
            // remaining-count header is what tells them apart.
            let remaining = http.value(forHTTPHeaderField: "x-ratelimit-remaining")
            if remaining == "0" {
                let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset")
                    .flatMap(Double.init)
                    .map { Date(timeIntervalSince1970: $0) }
                throw GitHubError.rateLimited(resetsAt: reset)
            }
            throw token == nil ? GitHubError.needsToken(slug) : GitHubError.notFound(slug)
        case 404:
            // A private repo is indistinguishable from a missing one without
            // credentials, so say the thing the user can act on.
            throw token == nil ? GitHubError.notFound(slug) : GitHubError.notFound(slug)
        default:
            throw GitHubError.transport("GitHub returned \(http.statusCode) for \(slug).")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GitHubError.transport("GitHub sent a response this version doesn't understand.")
        }
    }

    private func friendly(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed:
            return "No internet connection."
        case .timedOut:
            return "GitHub timed out."
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost:
            return "Couldn't reach GitHub."
        default:
            return error.localizedDescription
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
