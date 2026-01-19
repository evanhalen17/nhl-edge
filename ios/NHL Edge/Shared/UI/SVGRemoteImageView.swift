import SwiftUI
import SVGKit

/// Renders a remote SVG into a UIImage via SVGKit, then displays it using UIImageView.
/// This avoids SVGKFastImageView sizing quirks and makes SwiftUI sizing predictable.
struct SVGRemoteImageView: UIViewRepresentable {
    let urlString: String?
    let boxSize: CGFloat  // e.g. 28

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.backgroundColor = .clear
        return iv
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        guard
            let urlString,
            let url = URL(string: urlString)
        else {
            uiView.image = nil
            context.coordinator.currentURL = nil
            return
        }

        if context.coordinator.currentURL == url,
           context.coordinator.currentBoxSize == boxSize {
            return
        }

        context.coordinator.currentURL = url
        context.coordinator.currentBoxSize = boxSize
        uiView.image = nil

        Task.detached(priority: .utility) {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return
                }

                guard let svg = SVGKImage(data: data) else { return }

                // Rasterize to a square target; UIImageView will aspect-fit within its bounds
                let target = CGSize(width: boxSize, height: boxSize)
                svg.scaleToFit(inside: target)

                // Render to UIImage
                guard let rendered = svg.uiImage else { return }

                await MainActor.run {
                    // Ensure we still want this URL/size
                    guard context.coordinator.currentURL == url,
                          context.coordinator.currentBoxSize == boxSize
                    else { return }

                    uiView.image = rendered
                }
            } catch {
                // silent fail
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var currentURL: URL?
        var currentBoxSize: CGFloat?
    }
}

private extension SVGKImage {
    /// Scales the SVG content proportionally to fit inside a given size.
    func scaleToFit(inside target: CGSize) {
        let ow = max(self.size.width, 1)
        let oh = max(self.size.height, 1)
        let scale = min(target.width / ow, target.height / oh)
        self.size = CGSize(width: ow * scale, height: oh * scale)
    }
}
