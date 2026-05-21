import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Persists security-scoped bookmarks so a sandboxed AIMR build can read AI source
/// folders (~/.claude/, ~/.codex/, project trees, etc.) across launches.
///
/// Bookmarks are device-local (they encode an opaque token issued by macOS bound to
/// the granting Mac), so this store deliberately uses **UserDefaults only** and does
/// not sync via iCloud. Trying to use a bookmark created on another device would
/// fail with `NSURLBookmarkResolutionWithSecurityScope`-time errors.
///
/// Direct-distribution builds (the GitHub release ZIP) ship unsandboxed and never
/// hit this code path; the `BookmarkStore.isSandboxed` flag short-circuits.
final class BookmarkStore: @unchecked Sendable {
    static let shared = BookmarkStore()

    /// True when the running process is inside an App Sandbox container.
    /// Apple guarantees this env var is set for sandboxed processes.
    static let isSandboxed: Bool = {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }()

    private let defaults = UserDefaults.standard
    private let storageKey = "securityScopedBookmarks_v1"

    /// In-memory map of resolved URLs that we have an active security scope on,
    /// keyed by the original on-disk path the bookmark was created for.
    /// Stopping accesses is handled by `stopAllAccess()` (typically at app shutdown).
    private var activeScopes: [String: URL] = [:]

    private init() {}

    // MARK: - Public API

    /// Prompts the user to grant access to a folder, stores the bookmark, starts a
    /// security scope on the resulting URL, and returns the (resolved) URL.
    /// Returns nil if the user cancelled the panel.
    @MainActor
    @discardableResult
    func requestAccess(
        prompt: String = "Grant access",
        message: String = "Pick your real home folder (/Users/<your-username>) so AI Memory Reader can read CLAUDE.md, AGENTS.md, and other AI agent memory files. AIMR only reads what's in this folder — it never sends anything off your Mac.",
        startAt: URL? = nil
    ) -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = prompt
        panel.message = message
        panel.prompt = "Grant"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        // Even when sandboxed, NSOpenPanel can navigate the real filesystem.
        // `homeDirectoryForCurrentUser` returns the sandbox container — useless
        // as a starting point. Use the real home directory instead.
        let realHome = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory())
        panel.directoryURL = startAt ?? realHome
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return persist(url: url) ? url : nil
        #else
        return nil
        #endif
    }

    /// Persists a bookmark for the given URL (which must currently be accessible —
    /// typically right after the user picked it in an NSOpenPanel) and starts a
    /// security scope on it for the rest of this process's lifetime.
    @discardableResult
    func persist(url: URL) -> Bool {
        let options: URL.BookmarkCreationOptions
        #if os(macOS)
        options = .withSecurityScope
        #else
        options = []
        #endif
        do {
            let data = try url.bookmarkData(
                options: options,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var stored = storedBookmarks
            stored[url.path(percentEncoded: false)] = data
            storedBookmarks = stored
            // Begin scope immediately so the rest of the session can read.
            startScope(for: url, at: url.path(percentEncoded: false))
            return true
        } catch {
            return false
        }
    }

    /// Resolve all persisted bookmarks at app launch. For each, begins a security
    /// scope and keeps the resolved URL in `activeScopes` so FileManager calls
    /// against descendant paths succeed.
    func restoreOnLaunch() {
        guard Self.isSandboxed else { return }
        for (path, data) in storedBookmarks {
            resolveAndStart(data: data, originalPath: path)
        }
    }

    /// Whether we have *any* active scope. The empty state in ContentView checks this
    /// to decide whether to show the "Grant access" prompt on first sandboxed launch.
    var hasAnyGrant: Bool { !activeScopes.isEmpty }

    /// The granted home-style URL to use as the base for relative AI source paths
    /// (`.claude`, `.codex`, etc.) when sandboxed. Picks the shortest-path active
    /// scope, which is typically `/Users/<name>`. Returns nil if no grant exists.
    ///
    /// Falls back to `FileManager.default.homeDirectoryForCurrentUser` for the
    /// caller — which inside the sandbox is the *container*, not the real home.
    var userHomeURL: URL? {
        activeScopes.values
            .sorted { $0.path(percentEncoded: false).count < $1.path(percentEncoded: false).count }
            .first
    }

    /// Drop the bookmark for the given on-disk path. Mostly for tests / debugging.
    func revoke(path: String) {
        if let url = activeScopes.removeValue(forKey: path) {
            url.stopAccessingSecurityScopedResource()
        }
        var stored = storedBookmarks
        stored.removeValue(forKey: path)
        storedBookmarks = stored
    }

    /// Stop every active security scope. Call at app termination.
    func stopAllAccess() {
        for url in activeScopes.values {
            url.stopAccessingSecurityScopedResource()
        }
        activeScopes.removeAll()
    }

    // MARK: - Private helpers

    private var storedBookmarks: [String: Data] {
        get {
            (defaults.dictionary(forKey: storageKey) as? [String: Data]) ?? [:]
        }
        set {
            defaults.set(newValue, forKey: storageKey)
        }
    }

    private func resolveAndStart(data: Data, originalPath: String) {
        var stale = false
        let resolveOptions: URL.BookmarkResolutionOptions
        #if os(macOS)
        resolveOptions = .withSecurityScope
        #else
        resolveOptions = []
        #endif
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: resolveOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            startScope(for: url, at: originalPath)
            if stale {
                // Refresh the stored bookmark so we don't carry forever-stale data.
                let refreshOptions: URL.BookmarkCreationOptions
                #if os(macOS)
                refreshOptions = .withSecurityScope
                #else
                refreshOptions = []
                #endif
                if let refreshed = try? url.bookmarkData(
                    options: refreshOptions,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    var stored = storedBookmarks
                    stored[originalPath] = refreshed
                    storedBookmarks = stored
                }
            }
        } catch {
            // Bookmark unrecoverable (e.g. user moved the folder, or rebooted into
            // a different account). Drop it; user can re-grant.
            var stored = storedBookmarks
            stored.removeValue(forKey: originalPath)
            storedBookmarks = stored
        }
    }

    private func startScope(for url: URL, at originalPath: String) {
        // If we already have a scope at this path, don't double-start.
        if activeScopes[originalPath] != nil { return }
        if url.startAccessingSecurityScopedResource() {
            activeScopes[originalPath] = url
        }
    }
}
