import Foundation
import PhotosUI
import UIKit

@MainActor
final class MemoryAliveViewModel: ObservableObject {
    @Published var previewImage: UIImage?
    @Published var status = "Ready"
    @Published var isWorking = false

    private let pipeline = PhotoPipeline()

    func load(item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                status = "Could not read that image."
                return
            }
            previewImage = image
            status = "Photo loaded."
        } catch {
            status = error.localizedDescription
        }
    }

    func restore() {
        run { try await pipeline.restore($0) }
    }

    func colourise() {
        run { try await pipeline.colourise($0) }
    }

    func animatePortrait() {
        run { try await pipeline.preparePortraitAnimationPreview($0) }
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
