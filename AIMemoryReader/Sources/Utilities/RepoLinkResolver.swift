import Foundation

/// Where a link inside a repository document points.
enum RepoLinkTarget: Equatable {
    case document(path: String, heading: String?)
    /// A link to a directory that has no index document — open its listing.
    case folder(path: String)
    case anchor(String)
    case web(URL)
    case missing(String)
}

/// The same link rules as `LinkResolver`, applied to a GitHub tree instead of a
/// folder on disk.
///
/// Repository docs are full of relative links — a `docs/` index pointing at its
/// siblings, a README pointing at `CONTRIBUTING.md` — and on a phone there is no
/// "open in another app" that makes sense for them. Everything the tree knows
/// about resolves in place; everything else is a web link or a dead one.
enum RepoLinkResolver {
    static func resolve(rawLink raw: String, fromDocumentAt documentPath: String, in root: RepoNode) -> RepoLinkTarget {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .missing(raw) }

        let (pathPart, fragment) = LinkResolver.splitFragment(trimmed)
        let heading = fragment.map(LinkResolver.decode)

        if pathPart.isEmpty {
            guard let heading, !heading.isEmpty else { return .missing(trimmed) }
            return .anchor(heading)
        }

        if LinkResolver.hasForeignScheme(pathPart) {
            guard let url = URL(string: trimmed) else { return .missing(trimmed) }
            return .web(url)
        }

        let decoded = LinkResolver.decode(pathPart)
        // A leading slash in repo docs means "repo root", not the device root.
        let base = decoded.hasPrefix("/")
            ? ""
            : (documentPath as NSString).deletingLastPathComponent
        let candidate = normalize(join(base, decoded))

        if let node = locate(candidate, in: root) {
            return node.isDirectory
                ? .folder(path: node.path)
                : .document(path: node.path, heading: heading)
        }
        return .missing(trimmed)
    }

    // MARK: - Lookup

    private static func locate(_ path: String, in root: RepoNode) -> RepoNode? {
        if let exact = root.find(path: path), !exact.isDirectory { return exact }

        // Extensionless destinations — `[[user-profile]]`, or a README link
        // written without its suffix.
        if (path as NSString).pathExtension.isEmpty {
            for ext in ["md", "mdc", "mdx", "markdown", "txt"] {
                if let hit = root.find(path: "\(path).\(ext)"), !hit.isDirectory { return hit }
            }
        }

        // A folder link resolves to the index document inside it, the way GitHub
        // itself renders a directory; a folder without one falls through as the
        // directory itself, so the caller can open its listing.
        if let folder = root.find(path: path), folder.isDirectory {
            let index = folder.children.first {
                !$0.isDirectory && ["readme", "index"].contains(
                    ($0.name as NSString).deletingPathExtension.lowercased()
                )
            }
            return index ?? folder
        }

        // Last resort, matching `LinkResolver`: a sibling whose name matches once
        // separators and case are dropped, which is how Claude's `[[user-profile]]`
        // finds `user_profile.md`.
        let parentPath = (path as NSString).deletingLastPathComponent
        let wanted = LinkResolver.normalized((path as NSString).lastPathComponent)
        guard !wanted.isEmpty else { return nil }
        let parent = parentPath.isEmpty ? root : root.find(path: parentPath)
        return parent?.children.first {
            !$0.isDirectory && LinkResolver.normalized($0.name) == wanted
        }
    }

    // MARK: - Path arithmetic

    private static func join(_ base: String, _ relative: String) -> String {
        if relative.hasPrefix("/") { return String(relative.dropFirst()) }
        if base.isEmpty { return relative }
        return "\(base)/\(relative)"
    }

    /// Resolve `.` and `..` without touching the filesystem. A `..` that walks
    /// above the repo root is dropped, matching how GitHub renders such a link.
    static func normalize(_ path: String) -> String {
        var stack: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if !stack.isEmpty { stack.removeLast() }
            default:
                stack.append(String(component))
            }
        }
        return stack.joined(separator: "/")
    }
}
