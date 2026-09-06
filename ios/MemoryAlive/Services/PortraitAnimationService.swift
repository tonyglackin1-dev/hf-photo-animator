import CoreImage
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

        let leftEyeCenter = landmarks.leftEye.map { averagePoint(of: $0, faceRect: faceRect) }
        let rightEyeCenter = landmarks.rightEye.map { averagePoint(of: $0, faceRect: faceRect) }
        let mouthCenter = landmarks.outerLips.map { averagePoint(of: $0, faceRect: faceRect) }

        var frames: [UIImage] = []
        frames.reserveCapacity(totalFrames)

        for frameIndex in 0..<totalFrames {
            let t = Double(frameIndex) / Double(fps)
            var ciImage = baseImage

            let blink = min(
                1.0,
                blinkAmount(t: t, center: 1.82, width: 0.18) +
                0.78 * blinkAmount(t: t, center: 4.42, width: 0.16)
            )

            let eyeDX = CGFloat(sin(t * .pi * 0.58)) * faceWidth * 0.0040
            let eyeDY = CGFloat(cos(t * .pi * 0.36)) * faceWidth * 0.0018
            let mouthPulse = CGFloat(sin(t * .pi * 0.46))
            let headX = CGFloat(sin(t * .pi * 0.24)) * faceWidth * 0.0065
            let headY = CGFloat(cos(t * .pi * 0.20)) * faceWidth * 0.0028
            let headRotation = CGFloat(sin(t * .pi * 0.22)) * 0.0048
            let breathe = CGFloat(sin(t * .pi * 0.30)) * faceWidth * 0.0012

            // Move the face as one softly blended region so the head feels structural,
            // while the background remains almost completely stable.
            ciImage = localAffineWarp(
                image: ciImage,
                center: CGPoint(x: faceRect.midX, y: faceRect.midY),
                radiusX: faceWidth * 0.58,
                radiusY: faceRect.height * 0.62,
                transform: CGAffineTransform(translationX: headX, y: headY + breathe)
                    .rotated(by: headRotation),
                feather: 0.34
            )

            // Blink by compressing each eye vertically around its own landmark center.
            // This is more controlled than radial bump distortion and avoids rubbery cheeks.
            let eyelidScale = max(0.22, 1.0 - CGFloat(blink) * 0.78)
            if let center = leftEyeCenter {
                ciImage = localAffineWarp(
                    image: ciImage,
                    center: CGPoint(x: center.x + eyeDX, y: center.y + eyeDY),
                    radiusX: faceWidth * 0.105,
                    radiusY: faceWidth * 0.060,
                    transform: CGAffineTransform(scaleX: 1.0, y: eyelidScale),
                    feather: 0.24
                )
            }

            if let center = rightEyeCenter {
                ciImage = localAffineWarp(
                    image: ciImage,
                    center: CGPoint(x: center.x + eyeDX, y: center.y + eyeDY),
                    radiusX: faceWidth * 0.105,
                    radiusY: faceWidth * 0.060,
                    transform: CGAffineTransform(scaleX: 1.0, y: eyelidScale),
                    feather: 0.24
                )
            }

            // Gently lift and soften the mouth region without inflating the whole lower face.
            if let center = mouthCenter {
                let smileLift = faceWidth * 0.0055 * mouthPulse
                let mouthScaleY = 1.0 + 0.025 * mouthPulse
                ciImage = localAffineWarp(
                    image: ciImage,
                    center: center,
                    radiusX: faceWidth * 0.155,
                    radiusY: faceWidth * 0.085,
                    transform: CGAffineTransform(translationX: faceWidth * 0.0012 * mouthPulse, y: smileLift)
                        .scaledBy(x: 1.0, y: mouthScaleY),
                    feather: 0.30
                )
            }

            let rendered = ciImage.cropped(to: extent)
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

    private func localAffineWarp(
        image: CIImage,
        center: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        transform: CGAffineTransform,
        feather: CGFloat
    ) -> CIImage {
        guard radiusX > 1, radiusY > 1 else { return image }

        let local = CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(transform)
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))

        let warped = image.transformed(by: local).cropped(to: image.extent)

        guard let gradient = CIFilter(name: "CIRadialGradient") else { return image }
        gradient.setValue(CIVector(cgPoint: center), forKey: "inputCenter")
        gradient.setValue(Float(min(radiusX, radiusY) * max(0.05, 1.0 - feather)), forKey: "inputRadius0")
        gradient.setValue(Float(max(radiusX, radiusY)), forKey: "inputRadius1")
        gradient.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
        gradient.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 1), forKey: "inputColor1")

        guard let radialMask = gradient.outputImage?.cropped(to: image.extent) else { return image }

        // Squash the circular mask into an ellipse that matches the landmark region.
        let maskScale = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: radiusX / max(radiusX, radiusY), y: radiusY / max(radiusX, radiusY))
            .translatedBy(x: -center.x, y: -center.y)
        let mask = radialMask.transformed(by: maskScale).cropped(to: image.extent)

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return image }
        blend.setValue(warped, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        return blend.outputImage ?? image
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
