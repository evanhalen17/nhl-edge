import SwiftUI
import SVGKit

/// Renders a remote SVG into a UIImage via SVGKit, then displays it using UIImageView.
/// This avoids SVGKFastImageView sizing quirks and makes SwiftUI sizing predictable.
struct SVGRemoteImageView: UIViewRepresentable {
    let urlString: String?
    let boxSize: CGFloat  // e.g. 32

    /// Optional callback invoked on the main thread when the image is set.
    /// Use this for fade-in animations in SwiftUI (detail screens only).
    var onImageSet: (() -> Void)? = nil

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
            context.coordinator.currentBoxSize = nil
            context.coordinator.didFireCallback = false
            return
        }

        let isSameRequest =
            (context.coordinator.currentURL == url) &&
            (context.coordinator.currentBoxSize == boxSize)

        if isSameRequest { return }

        context.coordinator.currentURL = url
        context.coordinator.currentBoxSize = boxSize
        context.coordinator.didFireCallback = false

        uiView.image = nil

        Task.detached(priority: .utility) {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return
                }

                guard let svg = SVGKImage(data: data) else { return }

                let target = CGSize(width: boxSize, height: boxSize)
                svg.scaleToFit(inside: target)

                guard let rendered = svg.uiImage else { return }

                await MainActor.run {
                    guard context.coordinator.currentURL == url,
                          context.coordinator.currentBoxSize == boxSize
                    else { return }

                    uiView.image = rendered

                    if context.coordinator.didFireCallback == false {
                        context.coordinator.didFireCallback = true
                        onImageSet?()
                    }
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
        var didFireCallback: Bool = false
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
