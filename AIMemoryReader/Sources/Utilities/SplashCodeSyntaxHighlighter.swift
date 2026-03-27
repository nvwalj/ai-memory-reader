import MarkdownUI
import Splash
import SwiftUI

/// Syntax highlighter using Splash for Swift-like code blocks.
/// Falls back to plain monospace text for unsupported languages.
struct SplashCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    private let syntaxHighlighter = SyntaxHighlighter(format: AttributedStringOutputFormat(theme: .presentation(withFont: .init(size: 14))))

    func highlightCode(_ code: String, language: String?) -> Text {
        guard let language = language?.lowercased(), isSwiftLike(language) else {
            // For non-Swift languages, apply basic keyword highlighting
            return basicHighlight(code, language: language)
        }

        // Splash is primarily a Swift highlighter
        let highlighted = syntaxHighlighter.highlight(code)
        return Text(highlighted)
    }

    private func isSwiftLike(_ language: String) -> Bool {
        ["swift", "swiftui"].contains(language)
    }

    /// Basic keyword highlighting for common languages
    private func basicHighlight(_ code: String, language: String?) -> Text {
        let keywords: Set<String>
        switch language {
        case "python", "py":
            keywords = ["def", "class", "import", "from", "return", "if", "else", "elif", "for",
                        "while", "try", "except", "with", "as", "in", "not", "and", "or", "True",
                        "False", "None", "self", "lambda", "yield", "async", "await", "pass", "break"]
        case "javascript", "js", "typescript", "ts":
            keywords = ["function", "const", "let", "var", "return", "if", "else", "for", "while",
                        "class", "import", "export", "from", "async", "await", "try", "catch",
                        "throw", "new", "this", "true", "false", "null", "undefined", "typeof"]
        case "json":
            keywords = ["true", "false", "null"]
        case "bash", "sh", "zsh", "shell":
            keywords = ["if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac",
                        "function", "return", "export", "local", "echo", "cd", "ls", "grep",
                        "awk", "sed", "cat", "rm", "mkdir", "chmod"]
        case "yaml", "yml":
            keywords = ["true", "false", "null", "yes", "no"]
        case "markdown", "md":
            return Text(code).font(.system(size: 14, design: .monospaced))
        default:
            return Text(code).font(.system(size: 14, design: .monospaced))
        }

        // Simple word-by-word highlighting
        var result = Text("")
        let lines = code.components(separatedBy: "\n")
        for (lineIdx, line) in lines.enumerated() {
            let isComment = line.trimmingCharacters(in: .whitespaces).hasPrefix("#") ||
                            line.trimmingCharacters(in: .whitespaces).hasPrefix("//")

            if isComment {
                result = result + Text(line)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                let words = tokenize(line)
                for word in words {
                    if keywords.contains(word) {
                        result = result + Text(word)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.accentColor)
                    } else if word.hasPrefix("\"") || word.hasPrefix("'") {
                        result = result + Text(word)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.red)
                    } else if Double(word) != nil {
                        result = result + Text(word)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.purple)
                    } else {
                        result = result + Text(word)
                            .font(.system(size: 14, design: .monospaced))
                    }
                }
            }
            if lineIdx < lines.count - 1 {
                result = result + Text("\n")
            }
        }
        return result
    }

    /// Simple tokenizer that preserves whitespace between words
    private func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inString = false
        var stringChar: Character = "\""

        for char in line {
            if inString {
                current.append(char)
                if char == stringChar {
                    tokens.append(current)
                    current = ""
                    inString = false
                }
            } else if char == "\"" || char == "'" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                inString = true
                stringChar = char
                current.append(char)
            } else if char.isWhitespace || char.isPunctuation && char != "_" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(char))
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

extension CodeSyntaxHighlighter where Self == SplashCodeSyntaxHighlighter {
    static var splash: SplashCodeSyntaxHighlighter { SplashCodeSyntaxHighlighter() }
}

// MARK: - Splash AttributedString output

struct AttributedStringOutputFormat: OutputFormat {
    let theme: Splash.Theme

    func makeBuilder() -> Builder {
        Builder(theme: theme)
    }

    struct Builder: OutputBuilder {
        let theme: Splash.Theme
        private var attributedString = AttributedString()

        init(theme: Splash.Theme) {
            self.theme = theme
        }

        mutating func addToken(_ token: String, ofType type: TokenType) {
            var attrs = AttributeContainer()
            attrs.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            if let color = theme.tokenColors[type] {
                attrs.foregroundColor = Color(nsColor: color)
            }
            attributedString.append(AttributedString(token, attributes: attrs))
        }

        mutating func addPlainText(_ text: String) {
            var attrs = AttributeContainer()
            attrs.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            attrs.foregroundColor = Color.primary
            attributedString.append(AttributedString(text, attributes: attrs))
        }

        mutating func addWhitespace(_ whitespace: String) {
            attributedString.append(AttributedString(whitespace))
        }

        func build() -> AttributedString {
            attributedString
        }
    }
}
#endif
