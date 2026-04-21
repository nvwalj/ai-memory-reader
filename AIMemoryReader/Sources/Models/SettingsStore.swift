import Foundation

/// A settings store that syncs to iCloud via NSUbiquitousKeyValueStore,
/// falling back to UserDefaults when iCloud is unavailable.
/// Observes iCloud changes and merges them locally.
/// Thread-safe: both UserDefaults and NSUbiquitousKeyValueStore are thread-safe.
final class SettingsStore: @unchecked Sendable {
    static let shared = SettingsStore()

    private let iCloud = NSUbiquitousKeyValueStore.default
    private let local = UserDefaults.standard

    // MARK: - Keys
    private enum Key {
        static let recentFolders = "recentFolders"
        static let customAISourcePaths = "customAISourcePaths"
        static let lastSelectedSourceID = "lastSelectedSourceID"
        static let lastLocalFolderPath = "lastLocalFolderPath"
        static let appTheme = "appTheme"
    }

    private init() {
        // Sync iCloud store on launch
        iCloud.synchronize()

        // Observe iCloud external changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloud
        )

        // On first launch, push local values to iCloud if iCloud is empty
        migrateLocalToiCloudIfNeeded()
    }

    // MARK: - Public API

    var recentFolders: [String] {
        get { stringArray(forKey: Key.recentFolders) ?? [] }
        set { set(newValue, forKey: Key.recentFolders) }
    }

    var customAISourcePaths: [String] {
        get { stringArray(forKey: Key.customAISourcePaths) ?? [] }
        set { set(newValue, forKey: Key.customAISourcePaths) }
    }

    var lastSelectedSourceID: String? {
        get { string(forKey: Key.lastSelectedSourceID) }
        set { set(newValue, forKey: Key.lastSelectedSourceID) }
    }

    var lastLocalFolderPath: String? {
        get { string(forKey: Key.lastLocalFolderPath) }
        set { set(newValue, forKey: Key.lastLocalFolderPath) }
    }

    var appThemeRaw: String? {
        get { string(forKey: Key.appTheme) }
        set { set(newValue, forKey: Key.appTheme) }
    }

    // MARK: - Private read/write helpers

    private func string(forKey key: String) -> String? {
        // Try iCloud first
        if let value = iCloud.string(forKey: key) {
            return value
        }
        // Fallback to local
        return local.string(forKey: key)
    }

    private func stringArray(forKey key: String) -> [String]? {
        // Try iCloud first
        if let value = iCloud.array(forKey: key) as? [String], !value.isEmpty {
            return value
        }
        // Fallback to local
        return local.stringArray(forKey: key)
    }

    private func set(_ value: Any?, forKey key: String) {
        // Write to both stores
        local.set(value, forKey: key)
        iCloud.set(value, forKey: key)
        iCloud.synchronize()
    }

    // MARK: - iCloud → Local sync

    @objc private func iCloudDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
              let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        else { return }

        // Only merge on server change or initial sync
        guard reason == NSUbiquitousKeyValueStoreServerChange ||
              reason == NSUbiquitousKeyValueStoreInitialSyncChange
        else { return }

        for key in changedKeys {
            let iCloudValue = iCloud.object(forKey: key)
            local.set(iCloudValue, forKey: key)
        }

        // Post notification so UI can react if needed
        NotificationCenter.default.post(name: .settingsDidSyncFromiCloud, object: nil, userInfo: ["changedKeys": changedKeys])
    }

    // MARK: - Migration

    /// On first use, push existing UserDefaults values to iCloud
    private func migrateLocalToiCloudIfNeeded() {
        let migrationKey = "settingsStore_migrated_v1"
        guard !local.bool(forKey: migrationKey) else { return }

        let keysToMigrate = [
            Key.recentFolders,
            Key.customAISourcePaths,
            Key.lastSelectedSourceID,
            Key.lastLocalFolderPath,
            Key.appTheme,
        ]

        for key in keysToMigrate {
            if let localValue = local.object(forKey: key), iCloud.object(forKey: key) == nil {
                iCloud.set(localValue, forKey: key)
            }
        }

        iCloud.synchronize()
        local.set(true, forKey: migrationKey)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let settingsDidSyncFromiCloud = Notification.Name("settingsDidSyncFromiCloud")
}
