import AppKit
import CoreGraphics

enum ImageProcessing {
    static func removeGreenScreen(from image: NSImage) -> NSImage? {
        guard let input = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = input.width, height = input.height
        let bytesPerRow = width * 4
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo), let rawData = context.data else { return nil }
        context.draw(input, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = rawData.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        func smoothstep(_ low: Double, _ high: Double, _ value: Double) -> Double {
            let t = min(max((value - low) / (high - low), 0), 1)
            return t * t * (3 - 2 * t)
        }
        for offset in stride(from: 0, to: bytesPerRow * height, by: 4) {
            let oldAlpha = Double(pixels[offset + 3]) / 255
            guard oldAlpha > 0 else { continue }
            // CGContext bytes are premultiplied; key in straight color space, then premultiply again.
            let r = min(Double(pixels[offset]) / 255 / oldAlpha, 1)
            let g = min(Double(pixels[offset + 1]) / 255 / oldAlpha, 1)
            let b = min(Double(pixels[offset + 2]) / 255 / oldAlpha, 1)
            let dominance = g - max(r, b)
            let keyed = smoothstep(0.10, 0.60, dominance)
            guard keyed > 0 else { continue }
            let newAlpha = oldAlpha * (1 - keyed)
            // Pull green toward the other channels on translucent edge pixels to prevent a halo.
            let despilledGreen = min(g, max(r, b) + 0.035)
            let outputGreen = g * (1 - keyed) + despilledGreen * keyed
            pixels[offset] = UInt8(min(max(r * newAlpha, 0), 1) * 255)
            pixels[offset + 1] = UInt8(min(max(outputGreen * newAlpha, 0), 1) * 255)
            pixels[offset + 2] = UInt8(min(max(b * newAlpha, 0), 1) * 255)
            pixels[offset + 3] = UInt8(min(max(newAlpha, 0), 1) * 255)
            if newAlpha == 0 { pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0 }
        }
        guard let output = context.makeImage() else { return nil }
        return NSImage(cgImage: output, size: image.size)
    }

    static func featheredCrop(from image: NSImage, normalized rect: Rect4,
                              featherPixels: Int = 4) -> NSImage? {
        guard let input = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let x = max(0, Int(floor(rect.x * Double(input.width))))
        let top = max(0, Int(floor(rect.y * Double(input.height))))
        let width = min(input.width - x, max(1, Int(ceil(rect.width * Double(input.width)))))
        let height = min(input.height - top, max(1, Int(ceil(rect.height * Double(input.height)))))
        guard width > 0, height > 0 else { return nil }
        // CGImage cropping treats the first pixel row as y=0, matching rig top-left rectangles.
        let cropRect = CGRect(x: x, y: top, width: width, height: height)
        guard let crop = input.cropping(to: cropRect) else { return nil }
        let bytesPerRow = width * 4
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: info), let data = context.data else { return nil }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        let feather = max(1, featherPixels)
        for py in 0..<height {
            for px in 0..<width {
                let edgeDistance = min(px, py, width - 1 - px, height - 1 - py)
                let t = min(max(Double(edgeDistance) / Double(feather), 0), 1)
                let alphaFactor = t * t * (3 - 2 * t)
                let offset = py * bytesPerRow + px * 4
                // All channels are already premultiplied, so scale them together.
                for channel in 0..<4 {
                    pixels[offset + channel] = UInt8(Double(pixels[offset + channel]) * alphaFactor)
                }
            }
        }
        guard let output = context.makeImage() else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: width, height: height))
    }
}
