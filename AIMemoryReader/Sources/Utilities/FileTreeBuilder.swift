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
}
