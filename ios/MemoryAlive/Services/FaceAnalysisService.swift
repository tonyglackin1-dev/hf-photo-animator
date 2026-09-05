import UIKit
import Vision

actor FaceAnalysisService {
    func faces(in image: UIImage) async throws -> [VNFaceObservation] {
        guard let cg = image.cgImage else { throw PipelineError.invalidImage }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        try handler.perform([request])
        return request.results ?? []
    }
}
