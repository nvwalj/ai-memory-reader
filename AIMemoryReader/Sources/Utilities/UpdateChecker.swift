import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Polls GitHub /releases/latest, compares against the running build's
/// `CFBundleShortVersionString`, and exposes an `available` state that
/// the UI can render as a banner. Mac App Store builds (sandboxed) are
/// skipped — Apple handles updates for that channel.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, tag: String, url: URL, notes: String)
        case error(String)
    }

    private(set) var state: State = .idle

    private let owner = "nvwalj"
    private let repo = "ai-memory-reader"
    private let dismissedKey = "updateChecker.dismissedVersions"

    /// In-memory only: tracks whether we've already done a check in THIS app
    /// session. Persistent throttling caused a bug where multiple installs of
    /// AIMR sharing the same bundle ID would block each other from re-checking
    /// — so we now always check on each launch, but skip duplicate calls within
    /// the same process lifetime.
    private var checkedThisSession = false

    private init() {}

    /// Fire-and-forget startup probe. Runs on every launch (auto-check on
    /// each app start). De-duplicates within the same session.
    func checkIfDue() async {
        #if os(macOS)
        guard !BookmarkStore.isSandboxed else { return }
        #endif
        guard !checkedThisSession else { return }
        checkedThisSession = true
        await performCheck(manual: false)
    }

    /// Always-run check, used by the Help menu item. Bypasses the in-session
    /// dedupe. Shows feedback (alert) when up-to-date or errored so the user
    /// knows the click worked.
    func checkManually() async {
        await performCheck(manual: true)
        #if os(macOS)
        switch state {
        case .upToDate:
            showInfoAlert(
                title: "You're up to date",
                message: "AI Memory Reader \(currentVersion) is the latest version."
            )
        case .error(let msg):
            showInfoAlert(title: "Couldn't check for updates", message: msg)
        default:
            break // .available shows the banner; .checking shouldn't be terminal
        }
        #endif
    }

    /// User clicked "Skip This Version" — record the tag so we don't ask
    /// again about it. Future newer tags will still prompt.
    func skipVersion(tag: String) {
        var dismissed = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        if !dismissed.contains(tag) {
            dismissed.append(tag)
            UserDefaults.standard.set(dismissed, forKey: dismissedKey)
        }
        state = .idle
    }

    /// User clicked "Later" — just hide the banner this session.
    func dismissThisSession() {
        state = .idle
    }

    // MARK: - Internals

    private func performCheck(manual: Bool) async {
        state = .checking

        guard let endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            state = .error("Bad endpoint")
            return
        }

        var req = URLRequest(url: endpoint)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                state = manual ? .error("GitHub returned non-200") : .idle
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            handle(release: release, manual: manual)
        } catch {
            state = manual ? .error(error.localizedDescription) : .idle
        }
    }

    private func handle(release: GitHubRelease, manual: Bool) {
        let latestTag = release.tag_name
        let latestVersion = latestTag.hasPrefix("v") ? String(latestTag.dropFirst()) : latestTag
        let current = currentVersion

        if !versionIsNewer(latestVersion, than: current) {
            state = .upToDate
            return
        }

        let dismissed = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        if !manual, dismissed.contains(latestTag) {
            state = .idle
            return
        }

        let notes = (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pageURL = URL(string: "https://github.com/\(owner)/\(repo)/releases/tag/\(latestTag)")
            ?? URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
        state = .available(version: latestVersion, tag: latestTag, url: pageURL, notes: notes)
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Strict semver compare on dot-separated integer components.
    /// "0.4.10" > "0.4.2", "0.5.0" > "0.4.99", etc.
    private func versionIsNewer(_ candidate: String, than baseline: String) -> Bool {
        let lhs = candidate.split(separator: ".").compactMap { Int($0) }
        let rhs = baseline.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    #if os(macOS)
    private func showInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    #endif

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let body: String?
    }
}
