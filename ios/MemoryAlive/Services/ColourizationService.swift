import Accelerate
import CoreImage
import CoreML
import UIKit

actor ColourizationService {
    func colourise(image: UIImage, context: CIContext) async throws -> UIImage {
        guard let modelURL = Bundle.main.url(forResource: "DDColor_Tiny", withExtension: "mlmodelc") else {
            throw PipelineError.modelMissing("DDColor_Tiny")
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)

        guard let cgImage = image.cgImage else {
            throw PipelineError.invalidImage
        }

        let originalWidth = cgImage.width
        let originalHeight = cgImage.height
        let originalLAB = rgbToLAB(cgImage: cgImage)
        let originalL = extractL(lab: originalLAB, width: originalWidth, height: originalHeight)

        let resized = resizeCGImage(cgImage, width: 512, height: 512)
        let grayRGB = createGrayRGB(cgImage: resized)

        let inputArray = try MLMultiArray(shape: [1, 3, 512, 512], dataType: .float32)
        for index in 0..<grayRGB.count {
            inputArray[index] = NSNumber(value: grayRGB[index])
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(multiArray: inputArray)
        ])
        let prediction = try model.prediction(from: provider)
        guard let abArray = prediction.featureValue(for: "ab_channels")?.multiArrayValue else {
            throw PipelineError.processingFailed("DDColor returned no colour channels.")
        }

        var ab512 = [Float](repeating: 0, count: abArray.count)
        for index in 0..<abArray.count {
            ab512[index] = abArray[index].floatValue
        }

        let abOriginal = resizeAB(
            ab512,
            fromWidth: 512,
            fromHeight: 512,
            toWidth: originalWidth,
            toHeight: originalHeight
        )

        return labToRGB(
            l: originalL,
            ab: abOriginal,
            width: originalWidth,
            height: originalHeight
        )
    }

    private func rgbToLAB(cgImage: CGImage) -> [Float] {
        let width = cgImage.width
        let height = cgImage.height
        let pixels = extractRGBPixels(cgImage: cgImage)
        var lab = [Float](repeating: 0, count: width * height * 3)

        for index in 0..<(width * height) {
            let (l, a, b) = srgbToLab(
                r: pixels[index * 3],
                g: pixels[index * 3 + 1],
                b: pixels[index * 3 + 2]
            )
            lab[index * 3] = l
            lab[index * 3 + 1] = a
            lab[index * 3 + 2] = b
        }
        return lab
    }

    private func extractL(lab: [Float], width: Int, height: Int) -> [Float] {
        var l = [Float](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            l[index] = lab[index * 3]
        }
        return l
    }

    private func createGrayRGB(cgImage: CGImage) -> [Float] {
        let width = cgImage.width
        let height = cgImage.height
        let pixels = extractRGBPixels(cgImage: cgImage)
        var result = [Float](repeating: 0, count: 3 * width * height)

        for index in 0..<(width * height) {
            let (l, _, _) = srgbToLab(
                r: pixels[index * 3],
                g: pixels[index * 3 + 1],
                b: pixels[index * 3 + 2]
            )
            let (r, g, b) = labToSrgb(l: l, a: 0, b: 0)
            result[index] = r
            result[width * height + index] = g
            result[2 * width * height + index] = b
        }
        return result
    }

    private func extractRGBPixels(cgImage: CGImage) -> [Float] {
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let bitmap = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colourSpace,
            bitmapInfo: bitmapInfo
        ) else { return [] }

        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var result = [Float](repeating: 0, count: width * height * 3)
        for index in 0..<(width * height) {
            result[index * 3] = Float(bytes[index * 4]) / 255
            result[index * 3 + 1] = Float(bytes[index * 4 + 1]) / 255
            result[index * 3 + 2] = Float(bytes[index * 4 + 2]) / 255
        }
        return result
    }

    private func resizeCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage {
        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bitmap = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colourSpace,
            bitmapInfo: bitmapInfo
        )!
        bitmap.interpolationQuality = .high
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bitmap.makeImage()!
    }

    private func resizeAB(
        _ ab: [Float],
        fromWidth: Int,
        fromHeight: Int,
        toWidth: Int,
        toHeight: Int
    ) -> [Float] {
        let sourceCount = fromWidth * fromHeight
        let destinationCount = toWidth * toHeight
        var result = [Float](repeating: 0, count: 2 * destinationCount)

        result.withUnsafeMutableBufferPointer { destination in
            ab.withUnsafeBufferPointer { source in
                for channel in 0..<2 {
                    var src = vImage_Buffer(
                        data: UnsafeMutablePointer(mutating: source.baseAddress!.advanced(by: channel * sourceCount)),
                        height: vImagePixelCount(fromHeight),
                        width: vImagePixelCount(fromWidth),
                        rowBytes: fromWidth * MemoryLayout<Float>.stride
                    )
                    var dst = vImage_Buffer(
                        data: destination.baseAddress!.advanced(by: channel * destinationCount),
                        height: vImagePixelCount(toHeight),
                        width: vImagePixelCount(toWidth),
                        rowBytes: toWidth * MemoryLayout<Float>.stride
                    )
                    vImageScale_PlanarF(&src, &dst, nil, vImage_Flags(kvImageHighQualityResampling))
                }
            }
        }
        return result
    }

    private func labToRGB(l: [Float], ab: [Float], width: Int, height: Int) -> UIImage {
        let count = width * height
        var pixels = [UInt8](repeating: 255, count: count * 4)

        for index in 0..<count {
            let (r, g, b) = labToSrgb(l: l[index], a: ab[index], b: ab[count + index])
            pixels[index * 4] = UInt8(clamping: Int(r * 255))
            pixels[index * 4 + 1] = UInt8(clamping: Int(g * 255))
            pixels[index * 4 + 2] = UInt8(clamping: Int(b * 255))
        }

        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bitmap = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colourSpace,
            bitmapInfo: bitmapInfo
        )!
        return UIImage(cgImage: bitmap.makeImage()!)
    }

    private func srgbToLab(r: Float, g: Float, b: Float) -> (Float, Float, Float) {
        func linear(_ value: Float) -> Float {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        let rl = linear(r)
        let gl = linear(g)
        let bl = linear(b)
        var x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375
        var y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750
        var z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041
        x /= 0.95047
        z /= 1.08883

        func f(_ value: Float) -> Float {
            value > 0.008856 ? pow(value, 1 / 3) : 7.787 * value + 16 / 116
        }

        let fx = f(x)
        let fy = f(y)
        let fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    private func labToSrgb(l: Float, a: Float, b: Float) -> (Float, Float, Float) {
        let fy = (l + 16) / 116
        let fx = a / 500 + fy
        let fz = fy - b / 200

        func inverse(_ value: Float) -> Float {
            let cube = value * value * value
            return cube > 0.008856 ? cube : (value - 16 / 116) / 7.787
        }

        let x = inverse(fx) * 0.95047
        let y = inverse(fy)
        let z = inverse(fz) * 1.08883
        let linearR = x * 3.2404542 + y * -1.5371385 + z * -0.4985314
        let linearG = x * -0.9692660 + y * 1.8760108 + z * 0.0415560
        let linearB = x * 0.0556434 + y * -0.2040259 + z * 1.0572252

        func srgb(_ value: Float) -> Float {
            let clamped = max(0, min(1, value))
            return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }

        return (srgb(linearR), srgb(linearG), srgb(linearB))
    }
}
