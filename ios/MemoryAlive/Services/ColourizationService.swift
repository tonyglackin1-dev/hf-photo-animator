import CoreImage
import CoreML
import UIKit

actor ColourizationService {
    func colourise(image: UIImage, context: CIContext) async throws -> UIImage {
        // Production target: compact semantic colourisation model distilled for mobile Core ML.
        // DeOldify is not the production dependency; it is only a historical benchmark.
        guard Bundle.main.url(forResource: "MemoryAliveColorizer", withExtension: "mlmodelc") != nil else {
            throw PipelineError.modelMissing("MemoryAliveColorizer")
        }
        return image
    }
}
