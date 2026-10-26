import CryptoKit
import Foundation

nonisolated enum CaptureDisplayError: Error, Equatable, Sendable {
    case standardAssetUnavailable(CaptureLogEncoding)
    case invalidFixture, digestMismatch, signalMismatch, alreadyConverted
    case unsupportedPixelFormat, renderFailed, staleContext, outOfOrder, stopped
}

/// Encoded, normalized BGRA technical drawing only. This cannot certify a Log to
/// Rec.709 transform. All cube bytes are supplied explicitly; no generated asset is
/// shipped, loaded from a manifest, or installed into the standard catalog.
nonisolated struct CaptureDisplayTransform: Sendable {
    let identifier: String
    let version: String
    let source: String
    let usage: String
    let sha256: String
    let inputSignal: CaptureNDSignal
    let dimension: Int
    let rgbaCube: Data

    init(technicalFixtureID: String, version: String, source: String, usage: String,
         inputSignal: CaptureNDSignal, dimension: Int, rgbaCube: Data, expectedSHA256: String) throws {
        guard [technicalFixtureID, version, source, usage].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              inputSignal == .sRGB || inputSignal == .rec709,
              (2...64).contains(dimension),
              rgbaCube.count == dimension * dimension * dimension * 4 * MemoryLayout<Float>.size else {
            throw CaptureDisplayError.invalidFixture
        }
        // CIColorCube uses native Float RGBA. Apple iOS targets are little endian.
        // The technical contract fixes the encoded numeric domain to [0, 1] and
        // opaque alpha. It deliberately defines no Log range, gamut or transfer.
        let valid = rgbaCube.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 4).allSatisfy { offset in
                let value = Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                return value.isFinite && (0...1).contains(value) && (offset / 4 % 4 != 3 || value == 1)
            }
        }
        guard valid else { throw CaptureDisplayError.invalidFixture }
        let digest = SHA256.hash(data: rgbaCube).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else { throw CaptureDisplayError.digestMismatch }
        identifier = technicalFixtureID; self.version = version; self.source = source; self.usage = usage
        sha256 = digest; self.inputSignal = inputSignal; self.dimension = dimension; self.rgbaCube = rgbaCube
    }
}

/// No accepted standard asset exists yet. Only a reviewed, source-controlled
/// integration can populate this table; fixture or manifest claims cannot do so.
/// Log 1 and Log 2 remain separate keys, with neither inferred from a 2020 matrix.
nonisolated struct CaptureDisplayTransformCatalog: Sendable {
    private let accepted: [CaptureLogEncoding: CaptureDisplayTransform] = [:]

    func standardTransform(for encoding: CaptureLogEncoding) throws -> CaptureDisplayTransform {
        guard let transform = accepted[encoding] else { throw CaptureDisplayError.standardAssetUnavailable(encoding) }
        return transform
    }
}
