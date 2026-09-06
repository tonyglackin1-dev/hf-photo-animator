import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

actor PortraitAnimationService {
    private let fps = 18
    private let duration: Double = 6.0

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
        let totalFrames = Int(duration * Double(fps))
        var frames: [UIImage] = []
        frames.reserveCapacity(totalFrames)

        for frameIndex in 0..<totalFrames {
            let t = Double(frameIndex) / Double(fps)
            var ciImage = baseImage

            let blink = min(
                1.0,
                blinkAmount(t: t, center: 1.9, width: 0.15) +
                0.58 * blinkAmount(t: t, center: 4.55, width: 0.13)
            )

            let eyeDX = CGFloat(sin(t * .pi * 0.55)) * faceWidth * 0.0035
            let eyeDY = CGFloat(cos(t * .pi * 0.33)) * faceWidth * 0.0015
            let mouthPulse = CGFloat(sin(t * .pi * 0.42))
            let headX = CGFloat(sin(t * .pi * 0.22)) * faceWidth * 0.006
            let headY = CGFloat(cos(t * .pi * 0.18)) * faceWidth * 0.0025
            let headRotation = CGFloat(sin(t * .pi * 0.20)) * 0.0048

            if let leftEye = landmarks.leftEye {
                let center = averagePoint(of: leftEye, faceRect: faceRect)
                ciImage = applyBump(
                    to: ciImage,
                    center: CGPoint(x: center.x + eyeDX, y: center.y + eyeDY),
                    radius: faceWidth * 0.105,
                    scale: Float(-0.095 * blink)
                )
            }

            if let rightEye = landmarks.rightEye {
                let center = averagePoint(of: rightEye, faceRect: faceRect)
                ciImage = applyBump(
                    to: ciImage,
                    center: CGPoint(x: center.x + eyeDX, y: center.y + eyeDY),
                    radius: faceWidth * 0.105,
                    scale: Float(-0.095 * blink)
                )
            }

            if let outerLips = landmarks.outerLips {
                let center = averagePoint(of: outerLips, faceRect: faceRect)
                ciImage = applyBump(
                    to: ciImage,
                    center: CGPoint(
                        x: center.x,
                        y: center.y + faceWidth * 0.004 * mouthPulse
                    ),
                    radius: faceWidth * 0.16,
                    scale: Float(0.022 * mouthPulse)
                )
            }

            if let nose = landmarks.nose {
                let center = averagePoint(of: nose, faceRect: faceRect)
                let breath = CGFloat(sin(t * .pi * 0.30))
                ciImage = applyBump(
                    to: ciImage,
                    center: center,
                    radius: faceWidth * 0.24,
                    scale: Float(0.006 * breath)
                )
            }

            let pivot = CGPoint(x: faceRect.midX, y: faceRect.midY)
            let transform = CGAffineTransform(translationX: pivot.x, y: pivot.y)
                .rotated(by: headRotation)
                .translatedBy(x: -pivot.x + headX, y: -pivot.y + headY)

            let rendered = ciImage.transformed(by: transform).cropped(to: extent)
            guard let cgImage = context.createCGImage(rendered, from: extent) else {
                throw PipelineError.processingFailed("Could not render portrait animation frames.")
            }
            frames.append(UIImage(cgImage: cgImage))
        }

        return frames
    }

    private func blinkAmount(t: Double, center: Double, width: Double) -> Double {
        let x = (t - center) / width
        return exp(-x * x * 6.0)
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
