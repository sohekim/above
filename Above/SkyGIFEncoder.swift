import Foundation
@preconcurrency import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// A silent ten-second loop, sampled at 5 fps and centered to match the round viewfinder.
enum SkyGIFEncoder {
    static let duration: Double = 10
    static let framesPerSecond = 5
    static let dimension = 480

    static func encode(movieURLs: [URL]) async throws -> URL {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var cursor = CMTime.zero
        for url in movieURLs {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let duration = try await asset.load(.duration)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
            if cursor == .zero { track.preferredTransform = try await source.load(.preferredTransform) }
            cursor = cursor + duration
        }
        return try await encode(asset: composition)
    }

    static func encode(movieURL: URL) async throws -> URL {
        try await encode(asset: AVURLAsset(url: movieURL))
    }

    private static func encode(asset: AVAsset) async throws -> URL {
        let duration = try await asset.load(.duration).seconds
        guard duration >= 9.5 else {
            throw NSError(domain: "Above.Capture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The recording ended early. Try another ten seconds."])
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        return try await encodeFrames { index in
            let time = CMTime(seconds: Double(index) / Double(framesPerSecond), preferredTimescale: 600)
            return try await generator.image(at: time).image
        }
    }

    static func encodeFrames(frameAt: (Int) async throws -> CGImage) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        let count = Int(Self.duration) * framesPerSecond
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        do {
            for index in 0..<count {
                try Task.checkCancellation()
                let frame = try await frameAt(index)
                let side = min(frame.width, frame.height)
                let cropRect = CGRect(x: (frame.width - side) / 2, y: (frame.height - side) / 2, width: side, height: side)
                guard let crop = frame.cropping(to: cropRect),
                      let context = CGContext(data: nil, width: dimension, height: dimension, bitsPerComponent: 8,
                                              bytesPerRow: dimension * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                context.interpolationQuality = .high
                context.draw(crop, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
                guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
