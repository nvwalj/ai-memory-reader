import SwiftUI

struct TOCEntry: Identifiable, Equatable {
    let id: String
    let level: Int  // 1, 2, or 3
    let title: String

    static func == (lhs: TOCEntry, rhs: TOCEntry) -> Bool {
        lhs.id == rhs.id
    }
}

/// Extract H1-H3 headings from markdown text
enum TOCParser {
    static func parse(_ markdown: String) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        let lines = markdown.components(separatedBy: .newlines)
        var counts: [String: Int] = [:]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var level: Int?
            var title: String?

            if trimmed.hasPrefix("### ") && !trimmed.hasPrefix("#### ") {
                level = 3
                title = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ") {
                level = 2
                title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                level = 1
                title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }

            if let level, let title, !title.isEmpty {
                // Generate unique ID based on title
                let baseID = title.lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                let count = counts[baseID, default: 0]
                counts[baseID] = count + 1
                let uniqueID = count == 0 ? "toc-\(baseID)" : "toc-\(baseID)-\(count)"
                entries.append(TOCEntry(id: uniqueID, level: level, title: title))
            }
        }
        return entries
    }
}

/// A markdown section: text from one heading to the next
struct MarkdownSection: Identifiable {
    let id: String  // matches TOCEntry.id, or "preamble" for text before first heading
    let content: String
}

/// Split markdown into sections by headings, each section gets the TOCEntry's ID
enum MarkdownSplitter {
    static func split(_ markdown: String, entries: [TOCEntry]) -> [MarkdownSection] {
        guard !entries.isEmpty else {
            return [MarkdownSection(id: "preamble", content: markdown)]
        }

        var sections: [MarkdownSection] = []
        let lines = markdown.components(separatedBy: .newlines)
        var currentLines: [String] = []
        var currentID = "preamble"
        var entryIndex = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check if this line is a heading that matches the next expected entry
            if entryIndex < entries.count {
                let entry = entries[entryIndex]
                var isHeading = false

                if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                    let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if title == entry.title && entry.level == 1 { isHeading = true }
                } else if trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ") {
                    let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    if title == entry.title && entry.level == 2 { isHeading = true }
                } else if trimmed.hasPrefix("### ") && !trimmed.hasPrefix("#### ") {
                    let title = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                    if title == entry.title && entry.level == 3 { isHeading = true }
                }

                if isHeading {
                    // Save previous section
                    let content = currentLines.joined(separator: "\n")
                    if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentID != "preamble" {
                        sections.append(MarkdownSection(id: currentID, content: content))
                    }
                    currentID = entry.id
                    currentLines = [line]
                    entryIndex += 1
                    continue
                }
            }

            currentLines.append(line)
        }

        // Don't forget the last section
        let content = currentLines.joined(separator: "\n")
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(MarkdownSection(id: currentID, content: content))
        }

        return sections
    }
}

// MARK: - TOC Sidebar View

struct TOCSidebarView: View {
    let entries: [TOCEntry]
    let activeEntryID: String?
    let onSelect: (TOCEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12))
                Text("Contents")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            HStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(activeEntryID == entry.id ? Color.accentColor : Color.clear)
                                    .frame(width: 3)
                                    .padding(.trailing, 8)

                                Text(entry.title)
                                    .font(.system(size: entryFontSize(entry.level), weight: activeEntryID == entry.id ? .medium : .regular))
                                    .foregroundColor(activeEntryID == entry.id ? .primary : .secondary)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.leading, CGFloat((entry.level - 1) * 10))
                            .padding(.vertical, 4)
                            .padding(.trailing, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(width: 200)
        .background(Color(.controlBackgroundColor).opacity(0.3))
    }

    private func entryFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 12
        case 2: return 11.5
        default: return 11
        }
    }
}
