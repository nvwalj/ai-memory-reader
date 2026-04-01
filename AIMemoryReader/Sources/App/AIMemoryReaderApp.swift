import SwiftUI

extension Notification.Name {
    static let editorManualSave = Notification.Name("editorManualSave")
    static let exportPDF = Notification.Name("exportPDF")
    static let openFileFromSystem = Notification.Name("openFileFromSystem")
}

#if os(macOS)
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Hold URLs that arrive before SwiftUI view is mounted (cold start)
    static var pendingFileURLs: [URL] = []
    private static var viewReady = false

    static func markViewReady() {
        viewReady = true
        // Flush any URLs that arrived before the view was ready
        for url in pendingFileURLs {
            NotificationCenter.default.post(name: .openFileFromSystem, object: url)
        }
        pendingFileURLs.removeAll()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL {
            if AppDelegate.viewReady {
                NotificationCenter.default.post(name: .openFileFromSystem, object: url)
            } else {
                AppDelegate.pendingFileURLs.append(url)
            }
        }
    }
}
#endif

@main
struct AIMemoryReaderApp: App {
    @State private var appState = AppState()

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onOpenURL { url in
                    if url.isFileURL {
                        appState.openSingleFile(url)
                    } else {
                        appState.handleURL(url)
                    }
                }
                #if os(macOS)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onReceive(NotificationCenter.default.publisher(for: .openFileFromSystem)) { notification in
                    if let fileURL = notification.object as? URL {
                        appState.openSingleFile(fileURL)
                    }
                }
                .onAppear {
                    AppDelegate.markViewReady()
                }
                #endif
        }
        #if os(macOS)
        .handlesExternalEvents(matching: ["*"])
        #endif
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open File or Folder…") {
                    appState.openFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    appState.focusSearch = true
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .editorManualSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Divider()

                Button("Export PDF…") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            CommandGroup(after: .sidebar) {
                Button("OpenClaw Source") {
                    if let source = appState.availableSources.first(where: { $0.id == "openclaw" }) {
                        appState.selectSource(source)
                    }
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Open Local Files…") {
                    appState.openFolder()
                }
                .keyboardShortcut("2", modifiers: .command)
            }
        }
        #endif
    }
}
