import Foundation
import UIKit

@MainActor
final class MemoryAliveViewModel: ObservableObject {
    @Published var previewImage: UIImage?
    @Published var status = "Ready"
    @Published var isWorking = false

    private let pipeline = PhotoPipeline()

    func load(image: UIImage) {
        previewImage = image
        status = "Photo loaded."
    }

    func restore() {
        run { [self] image in
            try await self.pipeline.restore(image)
        }
    }

    func colourise() {
        run { [self] image in
            try await self.pipeline.colourise(image)
        }
    }

    func animatePortrait() {
        run { [self] image in
            try await self.pipeline.preparePortraitAnimationPreview(image)
        }
    }

    private func run(_ operation: @escaping (UIImage) async throws -> UIImage) {
        guard let input = previewImage, !isWorking else { return }
        isWorking = true
        status = "Processing entirely on this iPhone…"

        Task {
            do {
                let output = try await operation(input)
                previewImage = output
                status = "Done — processed locally."
            } catch {
                status = error.localizedDescription
            }
            isWorking = false
        }
    }
}
