import Foundation

extension Notification.Name {
    static let fileWatcherDidDetectChange = Notification.Name("fileWatcherDidDetectChange")
}

#if os(macOS)
/// Watches a directory tree for .md file changes using FSEvents
final class FileWatcher: Sendable {
    private let path: String
    nonisolated init(path: String) {
        self.path = path
    }

    /// Starts watching. Returns a stream reference that the caller must keep alive.
    /// Call `stopStream(_:)` to stop watching.
    func startStream() -> FSEventStreamRef? {
        let pathsToWatch = [path] as CFArray

        let queue = DispatchQueue(label: "com.aitools.filewatcher", qos: .utility)

        var context = FSEventStreamContext()

        guard let stream = FSEventStreamCreate(
            nil,
            { _, _, numEvents, eventPaths, eventFlags, _ in
                // Notify on any change — file-level filtering (.md only) was too
                // restrictive because directory-level events (create/delete) don't
                // carry the child filename. We debounce on the receiving side.
                if numEvents > 0 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .fileWatcherDidDetectChange, object: nil)
                    }
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return nil }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        return stream
    }

    static func stopStream(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
#endif
