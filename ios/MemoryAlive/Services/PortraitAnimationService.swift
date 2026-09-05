import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

actor PortraitAnimationService {
    func previewFrames(image: UIImage, face: VNFaceObservation, context: CIContext) async throws -> [UIImage] {
        guard let baseImage = CIImage(image: image) else {
            throw PipelineError.invalidImage
        }
        guard let landmarks = face.landmarks else {
            throw PipelineError.processingFailed("No facial landmarks were available for animation.")
        }

        let extent = baseImage.extent
        let faceRect = imageRect(for: face.boundingBox, in: extent)
        let faceWidth = faceRect.width

        let phases: [CGFloat] = [0.0, 0.35, 0.7, 1.0, 0.7, 0.35, 0.0, -0.2]
        var frames: [UIImage] = []

        for phase in phases {
            var ciImage = baseImage

            if let leftEye = landmarks.leftEye {
                let center = averagePoint(of: leftEye, faceRect: faceRect)
                ciImage = applyBump(
                    to: ciImage,
                    center: CGPoint(x: center.x + faceWidth * 0.003 * phase, y: center.y),
                    radius: faceWidth * 0.12,
                    scale: Float(-0.020 * phase)
                )
            }

            if let rightEye = landmarks.rightEye {
                let center = averagePoint(of: rightEye, faceRect: faceRect)
                ciImage = applyBump(
                    to: ciImage,
                    center: CGPoint(x: center.x + faceWidth * 0.003 * phase, y: center.y),
                    radius: faceWidth * 0.12,
                    scale: Float(-0.020 * phase)
                )
            }

            if let outerLips = landmarks.outerLips {
                let center = averagePoint(of: outerLips, faceRect: faceRect)
                ciImage = applyBump(
                    to: ciImage,
                    center: CGPoint(x: center.x, y: center.y + faceWidth * 0.010 * phase),
                    radius: faceWidth * 0.18,
                    scale: Float(0.025 * phase)
                )
            }

            let transform = CGAffineTransform(
                translationX: faceWidth * 0.004 * phase,
                y: faceWidth * 0.0015 * phase
            ).rotated(by: 0.0018 * phase)

            let rendered = ciImage.transformed(by: transform).cropped(to: extent)
            guard let cgImage = context.createCGImage(rendered, from: extent) else {
                throw PipelineError.processingFailed("Could not render portrait animation frames.")
            }
            frames.append(UIImage(cgImage: cgImage))
        }

        return frames
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
