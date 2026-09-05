import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

actor PhotoPipeline {
    private let context = CIContext(options: [.cacheIntermediates: true])
    private let faceService = FaceAnalysisService()
    private let restoration = RestorationService()
    private let colourizer = ColourizationService()
    private let animator = PortraitAnimationService()

    func restore(_ image: UIImage) async throws -> UIImage {
        let prepared = try normalized(image)
        let faces = try await faceService.faces(in: prepared)
        return try await restoration.restore(image: prepared, faces: faces, context: context)
    }

    func colourise(_ image: UIImage) async throws -> UIImage {
        let prepared = try normalized(image)
        return try await colourizer.colourise(image: prepared, context: context)
    }

    func preparePortraitAnimationPreview(_ image: UIImage) async throws -> UIImage {
        let prepared = try normalized(image)
        let faces = try await faceService.faces(in: prepared)
        guard let dominantFace = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            throw PipelineError.noFace
        }
        return try await animator.previewFrame(image: prepared, face: dominantFace, context: context)
    }

    private func normalized(_ image: UIImage) throws -> UIImage {
        guard let ci = CIImage(image: image) else { throw PipelineError.invalidImage }
        let maxSide: CGFloat = 1536
        let scale = min(1, maxSide / max(ci.extent.width, ci.extent.height))
        let resized = ci.transformed(by: .init(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(resized, from: resized.extent) else { throw PipelineError.invalidImage }
        return UIImage(cgImage: cg)
    }
}

enum PipelineError: LocalizedError {
    case invalidImage
    case noFace
    case modelMissing(String)
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "The photo could not be prepared."
        case .noFace: return "No clear portrait face was detected."
        case .modelMissing(let name): return "Native model \(name) has not been added to the Xcode target yet."
        case .processingFailed(let message): return message
        }
    }
}
