import CoreImage
import CoreML
import UIKit
import Vision

actor PortraitAnimationService {
    func previewFrame(image: UIImage, face: VNFaceObservation, context: CIContext) async throws -> UIImage {
        // Production target: a MobilePortrait-style lightweight neural head animation model,
        // converted and profiled for Core ML / Neural Engine execution on iPhone.
        // LivePortrait is the quality/control benchmark, not the default shipped runtime.
        guard Bundle.main.url(forResource: "MobilePortraitCore", withExtension: "mlmodelc") != nil else {
            throw PipelineError.modelMissing("MobilePortraitCore")
        }
        return image
    }
}
