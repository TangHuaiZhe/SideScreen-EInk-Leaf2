import Foundation
import CoreVideo

enum EInkModeProfile {
    static let displayRefreshRate = 30
    static let frameRate = 15
    static let bitrateMbps = 20
    static let quality = "high"
}

/// Produces an independent monochrome NV12 frame for the hardware encoder.
/// The luma plane is copied unchanged so text edges remain intact; neutral
/// chroma removes color without an RGB conversion or contrast clipping.
final class EInkFrameProcessor {
    private var pool: CVPixelBufferPool?
    private var poolWidth = 0
    private var poolHeight = 0
    private var poolPixelFormat: OSType = 0
    private let lock = NSLock()

    func process(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let pixelFormat = CVPixelBufferGetPixelFormatType(source)
        guard pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(source) == 2 else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard let pool = pixelBufferPool(width: width, height: height, pixelFormat: pixelFormat) else {
            return nil
        }

        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination) == kCVReturnSuccess,
              let destination else {
            return nil
        }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        copyLuma(from: source, to: destination)
        neutralizeChroma(in: destination)
        return destination
    }

    private func pixelBufferPool(width: Int, height: Int, pixelFormat: OSType) -> CVPixelBufferPool? {
        if width == poolWidth, height == poolHeight, pixelFormat == poolPixelFormat, let pool {
            return pool
        }

        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
        ]
        var newPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            nil,
            attributes as CFDictionary,
            &newPool
        )
        guard status == kCVReturnSuccess else { return nil }

        pool = newPool
        poolWidth = width
        poolHeight = height
        poolPixelFormat = pixelFormat
        return newPool
    }

    private func copyLuma(from source: CVPixelBuffer, to destination: CVPixelBuffer) {
        guard let sourceBase = CVPixelBufferGetBaseAddressOfPlane(source, 0),
              let destinationBase = CVPixelBufferGetBaseAddressOfPlane(destination, 0) else {
            return
        }

        let sourceBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(source, 0)
        let destinationBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(destination, 0)
        let rowBytes = min(sourceBytesPerRow, destinationBytesPerRow)
        let rowCount = min(
            CVPixelBufferGetHeightOfPlane(source, 0),
            CVPixelBufferGetHeightOfPlane(destination, 0)
        )

        for row in 0..<rowCount {
            memcpy(
                destinationBase.advanced(by: row * destinationBytesPerRow),
                sourceBase.advanced(by: row * sourceBytesPerRow),
                rowBytes
            )
        }
    }

    private func neutralizeChroma(in pixelBuffer: CVPixelBuffer) {
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else { return }
        let byteCount = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            * CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        baseAddress.initializeMemory(as: UInt8.self, repeating: 128, count: byteCount)
    }
}
