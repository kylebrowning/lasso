import CoreGraphics
import Foundation
import ImageIO

// MARK: - DiffOutput

public struct DiffOutput: Sendable {
    public let pixelDiffPercent: Double
    public let perceptualDistance: Double
    public let diffImageData: Data

    public init(pixelDiffPercent: Double, perceptualDistance: Double, diffImageData: Data) {
        self.pixelDiffPercent = pixelDiffPercent
        self.perceptualDistance = perceptualDistance
        self.diffImageData = diffImageData
    }
}

// MARK: - ImageDiffer

public struct ImageDiffer: Sendable {
    public var compare: @Sendable (Data, Data) throws -> DiffOutput

    public init(compare: @escaping @Sendable (Data, Data) throws -> DiffOutput) {
        self.compare = compare
    }
}

// MARK: - Live

extension ImageDiffer {
    public static let live = ImageDiffer { baselineData, currentData in
        let baselineImage = try cgImage(from: baselineData)
        let currentImage = try cgImage(from: currentData)

        let bw = baselineImage.width, bh = baselineImage.height
        let cw = currentImage.width, ch = currentImage.height
        guard bw == cw && bh == ch else {
            throw LassoError.diffSizeMismatch(
                baseline: "\(bw)x\(bh)",
                current: "\(cw)x\(ch)"
            )
        }

        let width = bw
        let height = bh
        let totalPixels = width * height

        let baselinePixels = try renderRGBA(baselineImage, width: width, height: height)
        let currentPixels = try renderRGBA(currentImage, width: width, height: height)

        var diffPixels = [UInt8](repeating: 0, count: totalPixels * 4)
        var diffCount = 0
        var labDistanceSum = 0.0

        for i in 0..<totalPixels {
            let offset = i * 4
            let br = baselinePixels[offset]
            let bg = baselinePixels[offset + 1]
            let bb = baselinePixels[offset + 2]
            let cr = currentPixels[offset]
            let cg = currentPixels[offset + 1]
            let cb = currentPixels[offset + 2]

            let dr = abs(Int(cr) - Int(br))
            let dg = abs(Int(cg) - Int(bg))
            let db = abs(Int(cb) - Int(bb))

            if dr > 2 || dg > 2 || db > 2 {
                diffCount += 1
                let dist = cie76Distance(
                    r1: br, g1: bg, b1: bb,
                    r2: cr, g2: cg, b2: cb
                )
                labDistanceSum += dist
                // Red highlight for diff pixels
                diffPixels[offset] = 255
                diffPixels[offset + 1] = 0
                diffPixels[offset + 2] = 0
                diffPixels[offset + 3] = 255
            } else {
                // Dim matching pixels (50% opacity)
                diffPixels[offset] = cr
                diffPixels[offset + 1] = cg
                diffPixels[offset + 2] = cb
                diffPixels[offset + 3] = 128
            }
        }

        let pixelDiffPercent = Double(diffCount) / Double(totalPixels)
        let avgPerceptualDistance = diffCount > 0 ? labDistanceSum / Double(diffCount) : 0.0

        let diffImageData = try encodePNG(pixels: diffPixels, width: width, height: height)

        return DiffOutput(
            pixelDiffPercent: pixelDiffPercent,
            perceptualDistance: avgPerceptualDistance,
            diffImageData: diffImageData
        )
    }

    public static let failing = ImageDiffer { _, _ in
        throw LassoError.invalidImage
    }
}

// MARK: - Image Helpers

private func cgImage(from data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw LassoError.invalidImage
    }
    return image
}

private func renderRGBA(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw LassoError.invalidImage
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
}

private func encodePNG(pixels: [UInt8], width: Int, height: Int) throws -> Data {
    var mutablePixels = pixels
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &mutablePixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
    let cgImage = context.makeImage() else {
        throw LassoError.invalidImage
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
        throw LassoError.invalidImage
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw LassoError.invalidImage
    }
    return data as Data
}

// MARK: - CIE76 Color Distance

/// sRGB → linear RGB → XYZ (D65) → Lab → Euclidean distance
private func cie76Distance(r1: UInt8, g1: UInt8, b1: UInt8, r2: UInt8, g2: UInt8, b2: UInt8) -> Double {
    let lab1 = srgbToLab(r: r1, g: g1, b: b1)
    let lab2 = srgbToLab(r: r2, g: g2, b: b2)
    let dL = lab1.L - lab2.L
    let da = lab1.a - lab2.a
    let db = lab1.b - lab2.b
    return (dL * dL + da * da + db * db).squareRoot()
}

private func srgbToLab(r: UInt8, g: UInt8, b: UInt8) -> (L: Double, a: Double, b: Double) {
    // sRGB → linear
    let lr = inverseGamma(Double(r) / 255.0)
    let lg = inverseGamma(Double(g) / 255.0)
    let lb = inverseGamma(Double(b) / 255.0)

    // linear RGB → XYZ (D65)
    let x = 0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb
    let y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb
    let z = 0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb

    // D65 reference white
    let xn = 0.95047, yn = 1.0, zn = 1.08883
    let fx = labF(x / xn)
    let fy = labF(y / yn)
    let fz = labF(z / zn)

    let L = 116.0 * fy - 16.0
    let a = 500.0 * (fx - fy)
    let bVal = 200.0 * (fy - fz)
    return (L, a, bVal)
}

private func inverseGamma(_ c: Double) -> Double {
    c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

private func labF(_ t: Double) -> Double {
    t > 0.008856 ? pow(t, 1.0 / 3.0) : (903.3 * t + 16.0) / 116.0
}
