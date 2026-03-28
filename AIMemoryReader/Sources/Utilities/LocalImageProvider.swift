#if os(macOS)
import MarkdownUI
import SwiftUI

/// Image provider that resolves local file paths (relative and absolute) for MarkdownUI.
/// Relative paths are resolved against the markdown file's parent directory.
struct LocalImageProvider: ImageProvider {
    let baseURL: URL

    func makeImage(url: URL?) -> some View {
        LocalImageView(url: url, baseURL: baseURL)
    }
}

private struct LocalImageView: View {
    let url: URL?
    let baseURL: URL
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                ResizeToFitLayout {
                    Image(nsImage: nsImage)
                        .resizable()
                }
            } else if let url, url.scheme == "http" || url.scheme == "https" {
                // Fall back to AsyncImage for remote URLs
                ResizeToFitLayout {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadLocalImage()
        }
    }

    private func loadLocalImage() {
        guard let url else { return }

        // Already a remote URL — skip local loading
        if url.scheme == "http" || url.scheme == "https" { return }

        let resolvedURL: URL
        if url.scheme == "file" {
            resolvedURL = url
        } else {
            // Relative path — resolve against the markdown file's parent directory
            let path = url.path(percentEncoded: false)
            if path.hasPrefix("/") {
                resolvedURL = URL(fileURLWithPath: path)
            } else {
                resolvedURL = baseURL.appendingPathComponent(path)
            }
        }

        if let image = NSImage(contentsOf: resolvedURL) {
            self.nsImage = image
        }
    }
}

/// A layout that resizes content to fit the container only if wider than the container.
struct ResizeToFitLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        var size = view.sizeThatFits(.unspecified)
        if let width = proposal.width, size.width > width {
            let aspectRatio = size.width / size.height
            size.width = width
            size.height = width / aspectRatio
        }
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        view.place(at: bounds.origin, proposal: .init(bounds.size))
    }
}

extension ImageProvider where Self == LocalImageProvider {
    static func localFile(basePath: URL) -> LocalImageProvider {
        LocalImageProvider(baseURL: basePath)
    }
}
#endif
