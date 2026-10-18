import Foundation
import CoreGraphics
import ImageIO

@main struct TestSkyGIF {
    static func main() async throws {
        let gif = try await SkyGIFEncoder.encodeFrames { frame in
            let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 2560,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red: CGFloat(frame) / 50, green: 0.5, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: frame * 5 + 80, y: 160, width: 50, height: 50))
            return context.makeImage()!
        }
        defer { try? FileManager.default.removeItem(at: gif) }
        let source = CGImageSourceCreateWithURL(gif as CFURL, nil)!
        precondition(CGImageSourceGetCount(source) == 50)
        var total = 0.0
        for index in 0..<50 {
            let image = CGImageSourceCreateImageAtIndex(source, index, nil)!
            precondition(image.width == 480 && image.height == 480)
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil)! as NSDictionary
            let gifProps = props[kCGImagePropertyGIFDictionary] as! NSDictionary
            total += gifProps[kCGImagePropertyGIFDelayTime] as! Double
        }
        precondition(abs(total - 10) < 0.01)
        let props = CGImageSourceCopyProperties(source, nil)! as NSDictionary
        let gifProps = props[kCGImagePropertyGIFDictionary] as! NSDictionary
        precondition(gifProps[kCGImagePropertyGIFLoopCount] as! Int == 0)
        print("PASS: synthetic frame sequence → 50-frame 480×480 GIF, 10-second duration, infinite loop")
    }
}
