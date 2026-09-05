import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

actor PortraitAnimationService {
    func previewFrame(image: UIImage, face: VNFaceObservation, context: CIContext) async throws -> UIImage {
        guard var ciImage = CIImage(image: image) else {
            throw PipelineError.invalidImage
        }
        guard let landmarks = face.landmarks else {
            throw PipelineError.processingFailed("No facial landmarks were available for animation.")
        }

        let extent = ciImage.extent
        let faceRect = imageRect(for: face.boundingBox, in: extent)
        let faceWidth = faceRect.width

        if let leftEye = landmarks.leftEye {
            let center = averagePoint(of: leftEye, faceRect: faceRect)
            ciImage = applyBump(to: ciImage, center: center, radius: faceWidth * 0.12, scale: -0.035)
        }

        if let rightEye = landmarks.rightEye {
            let center = averagePoint(of: rightEye, faceRect: faceRect)
            ciImage = applyBump(to: ciImage, center: center, radius: faceWidth * 0.12, scale: -0.035)
        }

        if let outerLips = landmarks.outerLips {
            let center = averagePoint(of: outerLips, faceRect: faceRect)
            ciImage = applyBump(to: ciImage, center: CGPoint(x: center.x, y: center.y + faceWidth * 0.012), radius: faceWidth * 0.19, scale: 0.045)
        }

        let subtleHeadShift = CGAffineTransform(
            translationX: faceWidth * 0.006,
            y: faceWidth * 0.002
        ).rotated(by: 0.0025)

        let shifted = ciImage.transformed(by: subtleHeadShift)
        let crop = shifted.cropped(to: extent)

        guard let cgImage = context.createCGImage(crop, from: extent) else {
            throw PipelineError.processingFailed("Could not render the animated portrait frame.")
        }
        return UIImage(cgImage: cgImage)
    }

    private func applyBump(
        to image: CIImage,
        center: CGPoint,
        radius: CGFloat,
        scale: Float
    ) -> CIImage {
        let filter = CIFilter.bumpDistortion()
        filter.inputImage = image
        filter.center = center
        filter.radius = Float(radius)
        filter.scale = scale
        return filter.outputImage ?? image
    }

    private func imageRect(for normalizedFaceRect: CGRect, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + normalizedFaceRect.minX * extent.width,
            y: extent.minY + normalizedFaceRect.minY * extent.height,
            width: normalizedFaceRect.width * extent.width,
            height: normalizedFaceRect.height * extent.height
        )
    }

    private func averagePoint(of region: VNFaceLandmarkRegion2D, faceRect: CGRect) -> CGPoint {
        guard region.pointCount > 0 else {
            return CGPoint(x: faceRect.midX, y: faceRect.midY)
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        for point in region.normalizedPoints {
            x += faceRect.minX + CGFloat(point.x) * faceRect.width
            y += faceRect.minY + CGFloat(point.y) * faceRect.height
        }

        let count = CGFloat(region.pointCount)
        return CGPoint(x: x / count, y: y / count)
    }
}
