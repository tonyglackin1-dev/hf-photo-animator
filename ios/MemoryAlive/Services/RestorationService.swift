import CoreImage
import CoreML
import UIKit
import Vision

actor RestorationService {
    func restore(image: UIImage, faces: [VNFaceObservation], context: CIContext) async throws -> UIImage {
        // Production target:
        // 1) Real-ESRGAN general-x4v3 (or better mobile Core ML equivalent) for global cleanup.
        // 2) GFPGAN-style face restoration on detected face crops.
        // 3) Blend restored face crops back into the global result.
        //
        // The model adapters intentionally fail rather than silently applying a fake filter.
        guard Bundle.main.url(forResource: "RealESRGANGeneral", withExtension: "mlmodelc") != nil else {
            throw PipelineError.modelMissing("RealESRGANGeneral")
        }
        guard Bundle.main.url(forResource: "GFPGANFace", withExtension: "mlmodelc") != nil else {
            throw PipelineError.modelMissing("GFPGANFace")
        }
        return image
    }
}
