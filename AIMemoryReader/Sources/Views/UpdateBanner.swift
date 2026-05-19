import SwiftUI

#if os(macOS)
import AppKit

/// Banner shown above the main split view when `UpdateChecker` has detected
/// a newer GitHub release. "Download" opens the release page in the user's
/// browser (we don't do in-app updates — too much complexity for ~3 releases/yr).
struct UpdateBanner: View {
    let version: String
    let tag: String
    let url: URL
    let notes: String

    @State private var showNotes = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("AI Memory Reader \(version) is available")
                    .font(.headline)
                Text("You're on \(currentVersion). Open the release page to grab the new build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !notes.isEmpty {
                    DisclosureGroup(isExpanded: $showNotes) {
                        ScrollView {
                            Text(notes)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 140)
                    } label: {
                        Text(showNotes ? "Hide release notes" : "Show release notes")
                            .font(.caption)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Download") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)

                Button("Skip This Version") {
                    UpdateChecker.shared.skipVersion(tag: tag)
                }
                .controlSize(.small)

                Button("Later") {
                    UpdateChecker.shared.dismissThisSession()
                }
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
#endif
