import XCTest
import CoreVideo
@testable import SideScreen

final class EInkModeTests: XCTestCase {
    func testReadingProfileUsesLeafFriendlyStreamingSettings() {
        XCTAssertEqual(EInkModeProfile.frameRate, 15)
        XCTAssertEqual(EInkModeProfile.bitrateMbps, 20)
        XCTAssertEqual(EInkModeProfile.quality, "high")
    }

    func testProcessorCopiesLumaAndNeutralizesChroma() throws {
        let source = try makeNV12Buffer(width: 4, height: 4)
        fill(source, luma: 96, chroma: 32)

        let result = try XCTUnwrap(EInkFrameProcessor().process(source))

        XCTAssertFalse(result === source)
        XCTAssertEqual(firstByte(in: result, plane: 0), 96)
        XCTAssertEqual(firstByte(in: result, plane: 1), 128)
    }

    private func makeNV12Buffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
        ] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            attributes,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(pixelBuffer)
    }

    private func fill(_ pixelBuffer: CVPixelBuffer, luma: UInt8, chroma: UInt8) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        fillPlane(pixelBuffer, plane: 0, value: luma)
        fillPlane(pixelBuffer, plane: 1, value: chroma)
    }

    private func fillPlane(_ pixelBuffer: CVPixelBuffer, plane: Int, value: UInt8) {
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
            XCTFail("Missing plane \(plane)")
            return
        }
        let byteCount = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
            * CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        baseAddress.initializeMemory(as: UInt8.self, repeating: value, count: byteCount)
    }

    private func firstByte(in pixelBuffer: CVPixelBuffer, plane: Int) -> UInt8 {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        return CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane)!
            .assumingMemoryBound(to: UInt8.self)
            .pointee
    }
}
