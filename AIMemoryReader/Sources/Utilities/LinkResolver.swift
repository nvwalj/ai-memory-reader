import Foundation

/// What a markdown link points at, once resolved against the file that holds it.
enum LinkTarget: Equatable {
    /// A file AIMR renders itself. `heading` is the `#fragment`, when the link had one.
    case document(URL, heading: String?)
    /// A folder — load it into the sidebar.
    case directory(URL)
    /// A local file AIMR can't render (image, PDF, source code). Hand it to the system.
    case externalFile(URL)
    /// `#heading` with no path in front of it: scroll inside the current document.
    case anchor(String)
    /// A scheme the system owns — http, mailto, and friends.
    case web(URL)
    /// Looks local, but nothing is there. Carries the link text for the message.
    case missing(String)
}

/// Turns a markdown link destination into something the app can act on.
///
/// Markdown in an AI memory folder is full of links between files —
/// `[User profile](user_profile.md)` in an index, `[[user-profile]]` between
/// memories, `../CLAUDE.md` across folders. Handing those to the system opens
/// them in whatever app owns `.md`, which is never what the reader wants.
enum LinkResolver {
    /// Extensions AIMR displays in its own detail pane.
    static let readableExtensions: Set<String> = [
        "md", "mdx", "mdc", "markdown", "txt",
        "json", "jsonl", "ndjson",
        "yaml", "yml",
    ]

    /// Schemes that belong to the system (or to AIMR's own URL handler) and
    /// should never be treated as a path on disk.
    private static let foreignSchemePattern = try? NSRegularExpression(
        pattern: "^[A-Za-z][A-Za-z0-9+.-]*:"
    )

    // MARK: - Entry points

    static func resolve(_ url: URL, relativeTo baseDirectory: URL) -> LinkTarget {
        // `OpenURLAction` hands us a URL that has already been parsed and
        // percent-encoded. `absoluteString` is the closest thing to what the
        // author actually typed, which is what the string path below wants.
        resolve(rawLink: url.absoluteString, relativeTo: baseDirectory)
    }

    static func resolve(rawLink raw: String, relativeTo baseDirectory: URL) -> LinkTarget {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .missing(raw) }

        // Split the fragment off *before* decoding. A literal `#` inside a
        // filename arrives as `%23`, and decoding first would turn it into an
        // anchor separator that was never there.
        let (pathPart, fragment) = splitFragment(trimmed)

        if pathPart.isEmpty {
            guard let fragment, !fragment.isEmpty else { return .missing(trimmed) }
            return .anchor(decode(fragment))
        }

        if hasForeignScheme(pathPart) {
            if pathPart.lowercased().hasPrefix("file:"),
               let fileURL = URL(string: pathPart), fileURL.isFileURL {
                return classify(fileURL.standardizedFileURL,
                                fragment: fragment.map(decode),
                                originalText: trimmed)
            }
            guard let url = URL(string: trimmed) else { return .missing(trimmed) }
            return .web(url)
        }

        return classify(localURL(for: decode(pathPart), relativeTo: baseDirectory),
                        fragment: fragment.map(decode),
                        originalText: trimmed)
    }

    // MARK: - Path resolution

    private static func localURL(for path: String, relativeTo baseDirectory: URL) -> URL {
        let expanded = path.hasPrefix("~") ? NSString(string: path).expandingTildeInPath : path
        let url = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : baseDirectory.appendingPathComponent(expanded)
        return url.standardizedFileURL
    }

    /// Decide what `url` is, widening the search when the literal path misses.
    private static func classify(_ url: URL, fragment: String?, originalText: String) -> LinkTarget {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false

        if fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) {
            return isDirectory.boolValue ? .directory(url) : kind(of: url, fragment: fragment)
        }

        // Extensionless destinations are the wiki convention — `[[user-profile]]`
        // means `user-profile.md`.
        if url.pathExtension.isEmpty {
            for ext in ["md", "mdc", "mdx", "markdown", "txt"] {
                let candidate = url.appendingPathExtension(ext)
                if fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
                    return kind(of: candidate, fragment: fragment)
                }
            }
        }

        // Last resort: a sibling whose name matches once separators are ignored.
        // Claude's memory files are `user_profile.md` on disk but reference each
        // other as `[[user-profile]]` — the frontmatter slug, not the filename.
        if let fuzzy = siblingMatching(url) {
            return kind(of: fuzzy, fragment: fragment)
        }

        return .missing(originalText)
    }

    private static func kind(of url: URL, fragment: String?) -> LinkTarget {
        readableExtensions.contains(url.pathExtension.lowercased())
            ? .document(url, heading: fragment)
            : .externalFile(url)
    }

    /// Find a readable file next to `url` whose name matches after normalization.
    private static func siblingMatching(_ url: URL) -> URL? {
        let wanted = normalized(url.lastPathComponent)
        guard !wanted.isEmpty else { return nil }

        let directory = url.deletingLastPathComponent()
        // Listed by name, not by URL: the URL-returning overload canonicalizes a
        // symlinked parent (`/tmp` → `/private/tmp`, or a symlinked project
        // folder), and a hit in a different namespace than the sidebar's tree
        // would fail to match any node in it. Appending the name to the
        // directory we were handed keeps the caller's namespace.
        guard let names = try? FileManager.default
            .contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return nil }

        let match = names.first { name in
            guard !name.hasPrefix(".") else { return false }
            let ext = (name as NSString).pathExtension.lowercased()
            return readableExtensions.contains(ext) && normalized(name) == wanted
        }
        return match.map { directory.appendingPathComponent($0) }
    }

    /// Drop a readable extension, then everything that isn't a letter or digit.
    /// `user-profile`, `user_profile.md` and `User Profile` all land on the same key.
    static func normalized(_ filename: String) -> String {
        var base = filename
        if let dot = base.lastIndex(of: "."),
           readableExtensions.contains(String(base[base.index(after: dot)...]).lowercased()) {
            base = String(base[base.startIndex..<dot])
        }
        return base.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - String helpers

    private static func splitFragment(_ link: String) -> (path: String, fragment: String?) {
        guard let hash = link.firstIndex(of: "#") else { return (link, nil) }
        return (String(link[link.startIndex..<hash]),
                String(link[link.index(after: hash)...]))
    }

    private static func decode(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }

    private static func hasForeignScheme(_ path: String) -> Bool {
        guard let regex = foreignSchemePattern else { return false }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }
}
