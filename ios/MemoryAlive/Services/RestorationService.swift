import CoreImage
import CoreML
import UIKit
import Vision

actor RestorationService {
    private let modelBaseName = "RealESRGAN_general_522_fp16"
    private let modelSize = 522
    private let contentSize = 512
    private let scale = 4

    func restore(image: UIImage, faces: [VNFaceObservation], context: CIContext) async throws -> UIImage {
        let model = try loadModel()
        let prepared = try prepare(image)
        let input = try makeInputArray(from: prepared.image)

        guard let inputName = model.modelDescription.inputDescriptionsByName.keys.first else {
            throw PipelineError.processingFailed("Real-ESRGAN has no input tensor.")
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: input)])
        let prediction = try await model.prediction(from: provider)

        guard let outputName = model.modelDescription.outputDescriptionsByName.keys.first,
              let output = prediction.featureValue(for: outputName)?.multiArrayValue else {
            throw PipelineError.processingFailed("Real-ESRGAN returned no output tensor.")
        }

        let fullOutput = try makeUIImage(from: output)
        let crop = CGRect(
            x: prepared.drawRect.origin.x * CGFloat(scale),
            y: prepared.drawRect.origin.y * CGFloat(scale),
            width: prepared.drawRect.width * CGFloat(scale),
            height: prepared.drawRect.height * CGFloat(scale)
        ).integral

        guard let cg = fullOutput.cgImage?.cropping(to: crop) else {
            throw PipelineError.processingFailed("Could not crop restored image.")
        }

        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }

    private func loadModel() throws -> MLModel {
        guard let url = Bundle.main.url(forResource: modelBaseName, withExtension: "mlmodelc") else {
            throw PipelineError.modelMissing(modelBaseName)
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        return try MLModel(contentsOf: url, configuration: config)
    }

    private func prepare(_ source: UIImage) throws -> (image: UIImage, drawRect: CGRect) {
        guard source.size.width > 0, source.size.height > 0 else {
            throw PipelineError.processingFailed("Invalid source image.")
        }

        let maxSide = CGFloat(contentSize)
        let ratio = min(maxSide / source.size.width, maxSide / source.size.height)
        let fitted = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
        let origin = CGPoint(x: (CGFloat(modelSize) - fitted.width) / 2,
                             y: (CGFloat(modelSize) - fitted.height) / 2)
        let rect = CGRect(origin: origin, size: fitted)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: modelSize, height: modelSize), format: format)
        let image = renderer.image { rendererContext in
            UIColor.black.setFill()
            rendererContext.fill(CGRect(x: 0, y: 0, width: modelSize, height: modelSize))
            source.draw(in: rect)
        }
        return (image, rect)
    }

    private func makeInputArray(from image: UIImage) throws -> MLMultiArray {
        guard let cg = image.cgImage else {
            throw PipelineError.processingFailed("Could not read image pixels.")
        }

        let width = modelSize
        let height = modelSize
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let bitmap = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PipelineError.processingFailed("Could not create input bitmap.")
        }

        bitmap.translateBy(x: 0, y: CGFloat(height))
        bitmap.scaleBy(x: 1, y: -1)
        bitmap.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: height), NSNumber(value: width)], dataType: .float32)
        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: 3 * width * height)
        let plane = width * height

        for y in 0..<height {
            for x in 0..<width {
                let pixel = (y * width + x) * 4
                let index = y * width + x
                ptr[index] = Float32(rgba[pixel]) / 255.0
                ptr[plane + index] = Float32(rgba[pixel + 1]) / 255.0
                ptr[2 * plane + index] = Float32(rgba[pixel + 2]) / 255.0
            }
        }
        return array
    }

    private func makeUIImage(from array: MLMultiArray) throws -> UIImage {
        let dimensions = array.shape.map { $0.intValue }
        guard dimensions.count == 4, dimensions[0] == 1, dimensions[1] == 3 else {
            throw PipelineError.processingFailed("Unexpected Real-ESRGAN output shape: \(dimensions)")
        }

        let height = dimensions[2]
        let width = dimensions[3]
        let plane = width * height
        var rgba = [UInt8](repeating: 255, count: width * height * 4)

        func clampByte(_ value: Float32) -> UInt8 {
            UInt8(max(0, min(255, Int((value * 255.0).rounded()))))
        }

        if array.dataType == .float32 {
            let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: plane * 3)
            for i in 0..<plane {
                rgba[i * 4] = clampByte(ptr[i])
                rgba[i * 4 + 1] = clampByte(ptr[plane + i])
                rgba[i * 4 + 2] = clampByte(ptr[2 * plane + i])
            }
        } else if array.dataType == .float16 {
            let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: plane * 3)
            for i in 0..<plane {
                rgba[i * 4] = clampByte(Float32(ptr[i]))
                rgba[i * 4 + 1] = clampByte(Float32(ptr[plane + i]))
                rgba[i * 4 + 2] = clampByte(Float32(ptr[2 * plane + i]))
            }
        } else {
            throw PipelineError.processingFailed("Unsupported Real-ESRGAN output data type.")
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cg = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw PipelineError.processingFailed("Could not create restored image.")
        }

        return UIImage(cgImage: cg)
    }
}
