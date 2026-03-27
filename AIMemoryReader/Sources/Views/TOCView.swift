import SwiftUI

struct TOCEntry: Identifiable {
    let id = UUID()
    let level: Int  // 1, 2, or 3
    let title: String
    let anchor: String  // for scrolling
}

/// Extract H1-H3 headings from markdown text
enum TOCParser {
    static func parse(_ markdown: String) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        let lines = markdown.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("### ") && !trimmed.hasPrefix("#### ") {
                let title = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                entries.append(TOCEntry(level: 3, title: title, anchor: title))
            } else if trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ") {
                let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                entries.append(TOCEntry(level: 2, title: title, anchor: title))
            } else if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                entries.append(TOCEntry(level: 1, title: title, anchor: title))
            }
        }
        return entries
    }
}

struct TOCView: View {
    let entries: [TOCEntry]
    let onSelect: (TOCEntry) -> Void
    @State private var isExpanded = true

    var body: some View {
        if !entries.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entries) { entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            Text(entry.title)
                                .font(.system(size: entryFontSize(entry.level)))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, CGFloat((entry.level - 1) * 12))
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 11))
                    Text("Table of Contents")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func entryFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 13
        case 2: return 12
        default: return 11
        }
    }
}
