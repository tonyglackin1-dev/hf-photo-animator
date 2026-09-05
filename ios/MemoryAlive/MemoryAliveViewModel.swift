import Foundation
import UIKit

@MainActor
final class MemoryAliveViewModel: ObservableObject {
    @Published var previewImage: UIImage?
    @Published var status = "Ready"
    @Published var isWorking = false

    private let pipeline = PhotoPipeline()
    private var animationFrames: [UIImage] = []
    private var animationTask: Task<Void, Never>?

    deinit {
        animationTask?.cancel()
    }

    func load(image: UIImage) {
        stopAnimation()
        previewImage = image
        status = "Photo loaded."
    }

    func restore() {
        stopAnimation()
        run { [self] image in
            try await self.pipeline.restore(image)
        }
    }

    func colourise() {
        stopAnimation()
        run { [self] image in
            try await self.pipeline.colourise(image)
        }
    }

    func animatePortrait() {
        guard let input = previewImage, !isWorking else { return }
        stopAnimation()
        isWorking = true
        status = "Creating local portrait motion…"

        Task {
            do {
                let frames = try await self.pipeline.preparePortraitAnimationFrames(input)
                guard !frames.isEmpty else {
                    throw PipelineError.processingFailed("No animation frames were created.")
                }
                self.animationFrames = frames
                self.isWorking = false
                self.status = "Bring to Life preview — processed locally."
                self.startAnimationLoop()
            } catch {
                self.status = error.localizedDescription
                self.isWorking = false
            }
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

    private func startAnimationLoop() {
        animationTask?.cancel()
        let frames = animationFrames
        animationTask = Task { [weak self] in
            var index = 0
            while !Task.isCancelled, !frames.isEmpty {
                self?.previewImage = frames[index]
                index = (index + 1) % frames.count
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
        animationFrames.removeAll()
    }
}
