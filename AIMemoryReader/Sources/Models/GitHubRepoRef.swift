import Foundation

/// A repository the user has added, plus the branch and subfolder they pointed at.
///
/// `ref` is nil until the default branch has been looked up; `subpath` is set when
/// the user pastes a deep link like `.../tree/main/docs`, which scopes the browse
/// to that folder instead of the whole repo.
struct GitHubRepoRef: Codable, Hashable, Identifiable, Sendable {
    var owner: String
    var name: String
    var ref: String?
    var subpath: String?

    var slug: String { "\(owner)/\(name)" }

    var id: String {
        var key = slug
        if let ref { key += "@\(ref)" }
        if let subpath, !subpath.isEmpty { key += "/\(subpath)" }
        return key
    }

    /// What the repo row shows: `owner/repo`, with the branch only when the user
    /// asked for one that isn't the default.
    func displayName(defaultBranch: String?) -> String {
        var text = slug
        if let ref, ref != defaultBranch { text += " @\(ref)" }
        if let subpath, !subpath.isEmpty { text += "/\(subpath)" }
        return text
    }

    var webURL: URL? {
        var path = "https://github.com/\(owner)/\(name)"
        if let ref {
            path += "/tree/\(ref)"
            if let subpath, !subpath.isEmpty { path += "/\(subpath)" }
        }
        return URL(string: path)
    }

    // MARK: - Parsing

    /// Accepts what people actually have on the clipboard: `owner/repo`, an
    /// https URL with or without `/tree/<branch>/<dir>`, an SSH remote, and any
    /// of those with a trailing `.git` or slash.
    static func parse(_ input: String) -> GitHubRepoRef? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // git@github.com:owner/repo.git
        if let range = text.range(of: "git@github.com:") {
            text = String(text[range.upperBound...])
        } else if let host = text.range(of: "github.com/") {
            text = String(text[host.upperBound...])
        } else if text.contains("://") {
            // A URL, but not a GitHub one.
            return nil
        }

        if text.hasSuffix(".git") { text.removeLast(4) }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Strip a query string or fragment left over from a copied browser URL.
        if let cut = text.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            text = String(text[text.startIndex..<cut])
        }

        let parts = text.split(separator: "/").map(String.init)
        guard parts.count >= 2, isValidComponent(parts[0]), isValidComponent(parts[1]) else {
            return nil
        }

        var repo = GitHubRepoRef(owner: parts[0], name: parts[1], ref: nil, subpath: nil)

        // .../tree/<ref>/<subpath...> or .../blob/<ref>/<file>
        if parts.count >= 4, parts[2] == "tree" || parts[2] == "blob" {
            repo.ref = parts[3]
            let rest = parts.dropFirst(4).joined(separator: "/")
            if !rest.isEmpty { repo.subpath = rest }
        }
        return repo
    }

    /// GitHub allows letters, digits, `-`, `_` and `.` in owner and repo names.
    private static func isValidComponent(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }
}

/// One entry in a repository's file tree.
struct GitHubTreeEntry: Codable, Hashable, Sendable {
    let path: String
    let type: String        // "blob" | "tree" | "commit" (submodule)
    let sha: String
    let size: Int?

    var isFile: Bool { type == "blob" }
    var name: String { path.split(separator: "/").last.map(String.init) ?? path }
}

/// A repository's tree at one commit, as fetched or as restored from cache.
struct GitHubTree: Codable, Sendable {
    let sha: String
    let entries: [GitHubTreeEntry]
    /// GitHub caps the recursive tree response; when this is true the listing is
    /// incomplete and the UI has to say so rather than imply the repo is small.
    let truncated: Bool
    let fetchedAt: Date
}

/// The handful of repository fields the browser needs.
struct GitHubRepoInfo: Codable, Sendable {
    let defaultBranch: String
    let isPrivate: Bool
    let description: String?
}
