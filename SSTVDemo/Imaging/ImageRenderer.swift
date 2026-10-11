import CoreGraphics
import Foundation
#if SWIFT_PACKAGE
import SSTVCore
#endif

enum ImageRenderer {
    static func image(from pixels: [UInt8]) -> CGImage? {
        guard pixels.count == Robot36.width * Robot36.height * 3,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: Robot36.width, height: Robot36.height,
                       bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: Robot36.width * 3,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
