import MarkdownUI
import SwiftUI

// MARK: - Platform color helpers

private extension Color {
    static var platformControlBackground: Color {
        #if os(macOS)
        Color(.controlBackgroundColor)
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }

    static var platformSeparator: Color {
        #if os(macOS)
        Color(.separatorColor)
        #else
        Color(.separator)
        #endif
    }
}

// MARK: - Font size helpers for Dynamic Type

private var baseFontSize: CGFloat {
    #if os(macOS)
    return 16
    #else
    return 15
    #endif
}

private var headingScale: CGFloat {
    #if os(macOS)
    return 1.0
    #else
    return 0.9
    #endif
}

extension MarkdownUI.Theme {
    /// Custom theme optimized for reading AI memory files
    @MainActor static let memoryReader = Theme()
        // MARK: - Text
        .text {
            FontSize(baseFontSize)
            ForegroundColor(.primary)
        }
        // MARK: - Headings
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 28, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(32 * headingScale)
                    ForegroundColor(.primary)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 24, bottom: 12)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(26 * headingScale)
                    ForegroundColor(.primary)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 20, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(22 * headingScale)
                    ForegroundColor(.primary)
                }
        }
        .heading4 { configuration in
            configuration.label
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(18 * headingScale)
                    ForegroundColor(.primary)
                }
        }
        .heading5 { configuration in
            configuration.label
                .markdownMargin(top: 14, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.medium)
                    FontSize(16 * headingScale)
                    ForegroundColor(.primary)
                }
        }
        .heading6 { configuration in
            configuration.label
                .markdownMargin(top: 12, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.medium)
                    FontSize(14 * headingScale)
                    ForegroundColor(.secondary)
                }
        }
        // MARK: - Code
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(14)
            ForegroundColor(.pink)
            BackgroundColor(Color.platformControlBackground.opacity(0.6))
        }
        .codeBlock { configuration in
            VStack(alignment: .leading, spacing: 0) {
                if let language = configuration.language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(14)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
            .background(Color.platformControlBackground.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .markdownMargin(top: 8, bottom: 8)
        }
        // MARK: - Blockquote
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 4)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.secondary)
                        FontSize(baseFontSize - 1)
                    }
                    .padding(.leading, 12)
            }
            .markdownMargin(top: 8, bottom: 8)
        }
        // MARK: - Table
        .table { configuration in
            configuration.label
                .markdownTableBorderStyle(
                    TableBorderStyle(color: Color.platformSeparator)
                )
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clear, Color.platformControlBackground.opacity(0.3))
                )
                .markdownMargin(top: 8, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    FontSize(14)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        // MARK: - Paragraph
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 4, bottom: 10)
                .lineSpacing(6)
        }
        // MARK: - List
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        // MARK: - Thematic Break
        .thematicBreak {
            Divider()
                .markdownMargin(top: 16, bottom: 16)
        }
        // MARK: - Links
        .link {
            ForegroundColor(.accentColor)
        }
        // MARK: - Strong/Emphasis
        .strong {
            FontWeight(.bold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .strikethrough {
            StrikethroughStyle(.single)
        }
}
