import Foundation

enum FileTreeBuilder {
    static func buildTree(at url: URL, strictFiltering: Bool = true) -> FileNode {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) else {
            return FileNode(url: url, isDirectory: false)
        }

        if isDir.boolValue {
            let contents = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let children = contents
                .sorted { lhs, rhs in
                    let lhsIsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    let rhsIsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if lhsIsDir != rhsIsDir { return lhsIsDir }
                    return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
                }
                .compactMap { childURL -> FileNode? in
                    let childIsDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if !childIsDir && !FileNode.isSupportedFile(childURL, strict: strictFiltering) {
                        return nil
                    }
                    return buildTree(at: childURL, strictFiltering: strictFiltering)
                }
                .filter { node in
                    // Remove empty directories
                    if node.isDirectory {
                        return node.children?.isEmpty == false
                    }
                    return true
                }

            return FileNode(url: url, isDirectory: true, children: children)
        } else {
            return FileNode(url: url, isDirectory: false)
        }
    }

    /// Reconcile `existing` in place to match `fresh`, reusing existing FileNode
    /// objects wherever the path (id) matches — recursively. Preserving object
    /// identity keeps `isExpanded`, scroll position, and any `selectedFile`
    /// pointing into the tree intact, so the sidebar List is never torn down on a
    /// filesystem event. `existing.children` is reassigned only at the levels where
    /// the child set or order actually changed, so content-only events (e.g. an
    /// agent appending to a session log) cause zero observation churn.
    static func merge(into existing: FileNode, from fresh: FileNode) {
        guard existing.isDirectory else { return }
        let freshChildren = fresh.children ?? []

        var existingByID: [String: FileNode] = [:]
        for child in existing.children ?? [] { existingByID[child.id] = child }

        var reconciled: [FileNode] = []
        reconciled.reserveCapacity(freshChildren.count)
        for freshChild in freshChildren {
            if let keep = existingByID[freshChild.id], keep.isDirectory == freshChild.isDirectory {
                if keep.isDirectory { merge(into: keep, from: freshChild) }
                reconciled.append(keep)
            } else {
                reconciled.append(freshChild)
            }
        }

        if (existing.children ?? []).map(\.id) != reconciled.map(\.id) {
            existing.children = reconciled
        }
    }
}
