#if os(macOS)
import SwiftUI

struct SuggestedRulesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var isScanning: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if isScanning {
                scanningState
            } else if visibleRules.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(visibleRules) { rule in
                        RuleRow(rule: rule) {
                            appState.addSuggestionToClaudeMd(rule)
                        } onDismiss: {
                            appState.dismissSuggestion(rule)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 560, idealWidth: 700, minHeight: 420, idealHeight: 560)
        .task {
            await refresh()
        }
    }

    private var visibleRules: [RuleSuggestion] {
        let dismissed = appState.dismissedSuggestionIDs
        return appState.suggestedRules.filter { !dismissed.contains($0.id) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggested Rules")
                    .font(.headline)
                Text("Repeated mid-session corrections worth promoting to CLAUDE.md.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isScanning)
            .help("Re-scan session logs")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No repeated corrections found yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Once you correct the model the same way across two or more sessions, suggestions appear here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning session logs…")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        await appState.refreshSuggestedRules()
    }
}

private struct RuleRow: View {
    let rule: RuleSuggestion
    let onAdd: () -> Void
    let onDismiss: () -> Void

    @State private var hover: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                badge
                Text(rule.text)
                    .font(.system(.body, design: .default))
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button("Add to CLAUDE.md", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(hover ? Color.gray.opacity(0.08) : Color.clear)
        .onHover { hover = $0 }
    }

    private var badge: some View {
        VStack(spacing: 2) {
            Text("\(rule.frequency)×")
                .font(.system(.caption, design: .rounded).bold())
                .monospacedDigit()
            Text("\(rule.sessionCount) sess")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 44)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
#endif
