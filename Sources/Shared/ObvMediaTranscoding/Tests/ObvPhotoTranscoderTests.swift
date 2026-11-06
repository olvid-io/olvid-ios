/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ObvAppTypes
@testable import ObvMediaTranscoding


/// What `ObvPhotoTranscoder` does to a photograph, and — as much as anything — what it declines to do to one.
///
/// The fixtures are written here rather than checked into the repository: a photograph of a known size, with a known EXIF
/// orientation, is three lines of ImageIO, and a binary fixture would be a file nobody can see the properties of when a test fails.
final class ObvPhotoTranscoderTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }


    // MARK: - Reading a photograph's size

    func testThePixelSizeOfAPhotographIsReadWithoutItsOrientation() throws {
        let url = try makePhotograph(width: 3000, height: 2000)
        let size = try XCTUnwrap(ObvPhotoTranscoder.pixelSize(ofPhotoAt: url))
        XCTAssertEqual(size.width, 3000)
        XCTAssertEqual(size.height, 2000)
    }


    /// A portrait photograph off an iPhone is stored as a landscape bitmap plus a tag saying to turn it. What is reported is what the
    /// reader sees, not what is on disk.
    func testThePixelSizeOfAPhotographTurnedByItsOrientationIsReportedTurned() throws {
        let url = try makePhotograph(width: 3000, height: 2000, orientation: 6)
        let size = try XCTUnwrap(ObvPhotoTranscoder.pixelSize(ofPhotoAt: url))
        XCTAssertEqual(size.width, 2000)
        XCTAssertEqual(size.height, 3000)
    }


    func testThePixelSizeOfSomethingThatIsNotAPhotographCannotBeRead() throws {
        let url = directory.appendingPathComponent("not-a-photograph.jpeg")
        try Data("this is not a photograph".utf8).write(to: url)
        XCTAssertNil(ObvPhotoTranscoder.pixelSize(ofPhotoAt: url))
    }


    // MARK: - Deciding whether a size is worth writing

    /// **A cap is a ceiling and never a target.** A photograph already within a size is not enlarged to meet it: doing so would hand the
    /// reader a *larger* file as the smaller option. This is the rule that makes a small photograph occupy one file on disk and show four
    /// identical weights in the menu.
    func testASizeThatWouldNotReduceThePhotographIsRefused() throws {

        let large = try makePhotograph(width: 3000, height: 2000)
        XCTAssertTrue(ObvPhotoTranscoder.transcodingWouldReduce(photoAt: large, to: .low))
        XCTAssertTrue(ObvPhotoTranscoder.transcodingWouldReduce(photoAt: large, to: .med))
        XCTAssertFalse(ObvPhotoTranscoder.transcodingWouldReduce(photoAt: large, to: .hi), "3000px is already within the 3840px cap")
        XCTAssertFalse(ObvPhotoTranscoder.transcodingWouldReduce(photoAt: large, to: .max), "max is the photograph itself")

        let small = try makePhotograph(width: 800, height: 600)
        for format in ObvMediaFormat.allCases {
            XCTAssertFalse(ObvPhotoTranscoder.transcodingWouldReduce(photoAt: small, to: format),
                           "\(format.rawValue) would not reduce an 800×600 photograph and must not be written")
        }

    }


    /// A photograph whose size cannot be read is left alone rather than fed to the encoder — a deletion or a decode fails towards doing
    /// nothing.
    func testAPhotographThatCannotBeReadIsNeverTranscoded() throws {
        let url = directory.appendingPathComponent("gone.jpeg")
        for format in ObvMediaFormat.allCases {
            XCTAssertFalse(ObvPhotoTranscoder.transcodingWouldReduce(photoAt: url, to: format))
        }
    }


    // MARK: - Writing a size

    func testEachSizeIsWrittenWithinItsCap() throws {

        let url = try makePhotograph(width: 3000, height: 2000)

        for (format, expectedLongestEdge) in [(ObvMediaFormat.low, 1_280), (.med, 2_048)] {

            let transcoded = try ObvPhotoTranscoder.transcode(photoAt: url, named: "IMG_4021.HEIC", to: format, inDirectory: directory)

            XCTAssertEqual(max(transcoded.pixelWidth, transcoded.pixelHeight), expectedLongestEdge)
            XCTAssertEqual(transcoded.contentType, .jpeg)
            XCTAssertEqual(transcoded.fileName, "IMG_4021.jpeg", "The name keeps its stem and states what the file now is")
            XCTAssertEqual(transcoded.sha256.count, 32)
            XCTAssertGreaterThan(transcoded.byteCount, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: transcoded.temporaryURL.path))

            // The size recorded must be the size of the file that was written, the menu stating it to the reader.
            let byteCountOnDisk = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: transcoded.temporaryURL.path)[.size] as? Int64)
            XCTAssertEqual(transcoded.byteCount, byteCountOnDisk)

            // And the aspect ratio survives, this being a downscale and not a crop.
            XCTAssertEqual(Double(transcoded.pixelWidth) / Double(transcoded.pixelHeight), 3000.0 / 2000.0, accuracy: 0.01)

        }

    }


    /// The orientation is baked into the pixels, so what is sent is upright to anybody whose viewer ignores the tag.
    func testTheOrientationIsBakedIntoTheWrittenPixels() throws {

        let url = try makePhotograph(width: 3000, height: 2000, orientation: 6)
        let transcoded = try ObvPhotoTranscoder.transcode(photoAt: url, named: "turned.heic", to: .low, inDirectory: directory)

        XCTAssertEqual(transcoded.pixelHeight, 1_280, "The long edge is the height once the photograph has been turned")
        XCTAssertLessThan(transcoded.pixelWidth, transcoded.pixelHeight)

        // And the file that was written carries no orientation of its own to apply a second time.
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(transcoded.temporaryURL as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        XCTAssertEqual(orientation, 1)

    }


    func testASizeThatDoesNotTranscodeIsRefusedRatherThanCopied() throws {
        let url = try makePhotograph(width: 3000, height: 2000)
        XCTAssertThrowsError(try ObvPhotoTranscoder.transcode(photoAt: url, named: "a.heic", to: .max, inDirectory: directory)) { error in
            guard case ObvPhotoTranscoder.ObvError.thisFormatDoesNotTranscode = error else {
                return XCTFail("Expected thisFormatDoesNotTranscode, got \(error)")
            }
        }
    }


    func testAPhotographThatCannotBeReadThrowsRatherThanWritingSomething() throws {
        let url = directory.appendingPathComponent("gone.jpeg")
        XCTAssertThrowsError(try ObvPhotoTranscoder.transcode(photoAt: url, named: "a.heic", to: .low, inDirectory: directory))
        let leftBehind = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(leftBehind.isEmpty, "A failed encode must leave nothing on disk")
    }


    /// **Two writes of the same photograph at the same size must hash alike**, and this is load-bearing rather than a curiosity: `Fyle` is
    /// content-addressed, so it is what makes two readers attaching the same picture — or the same picture attached twice — share one row
    /// and one file instead of accumulating copies.
    func testWritingTheSameSizeTwiceProducesTheSameBytes() throws {
        let url = try makePhotograph(width: 3000, height: 2000)
        let first = try ObvPhotoTranscoder.transcode(photoAt: url, named: "a.heic", to: .med, inDirectory: directory)
        let second = try ObvPhotoTranscoder.transcode(photoAt: url, named: "a.heic", to: .med, inDirectory: directory)
        XCTAssertEqual(first.sha256, second.sha256)
        XCTAssertNotEqual(first.temporaryURL, second.temporaryURL, "Each write gets a file of its own; only the bytes are the same")
    }


    func testTheWrittenFileTakesItsNameFromNothingTheCallerPassed() throws {
        // The name the *reader* sees is carried in `fileName`; the file on disk is named by a UUID, since it is about to be moved into a
        // content-addressed store where its name will be its hash.
        let url = try makePhotograph(width: 3000, height: 2000)
        let transcoded = try ObvPhotoTranscoder.transcode(photoAt: url, named: "holiday.HEIC", to: .low, inDirectory: directory)
        XCTAssertNotEqual(transcoded.temporaryURL.lastPathComponent, "holiday.jpeg")
        XCTAssertEqual(transcoded.temporaryURL.pathExtension, "jpeg")
    }


    // MARK: - Writing a size under a ceiling

    func testASizeLighterThanTheCeilingIsKept() throws {
        let url = try makePhotograph(width: 3000, height: 2000)
        let outcome = try ObvPhotoTranscoder.transcode(photoAt: url, named: "a.heic", to: .med, inDirectory: directory, onlyIfLighterThan: .max)
        guard case .written(let transcoded) = outcome else {
            return XCTFail("Expected the size to be kept, got \(outcome)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: transcoded.temporaryURL.path))
    }


    /// At equal weight the larger size is the better file for the same cost, so the smaller one is refused.
    func testASizeWeighingExactlyTheCeilingIsRefusedAndItsFileDeleted() throws {
        let url = try makePhotograph(width: 3000, height: 2000)
        let first = try ObvPhotoTranscoder.transcode(photoAt: url, named: "a.heic", to: .med, inDirectory: directory)
        try FileManager.default.removeItem(at: first.temporaryURL)
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        let outcome = try ObvPhotoTranscoder.transcode(photoAt: url, named: "a.heic", to: .med, inDirectory: directory, onlyIfLighterThan: first.byteCount)

        guard case .notLighterThanTheCeiling(let reported) = outcome else {
            return XCTFail("Expected the size to be refused, got \(outcome)")
        }
        XCTAssertEqual(reported, first.byteCount)
        let filesAfter = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(Set(filesAfter), Set(filesBefore), "A refused size must leave nothing on disk")
    }


    func testASizeOneByteUnderTheCeilingIsKept() throws {
        let url = try makePhotograph(width: 3000, height: 2000)
        let byteCount = try ObvPhotoTranscoder.transcode(photoAt: url, named: "a.heic", to: .med, inDirectory: directory).byteCount
        let outcome = try ObvPhotoTranscoder.transcode(photoAt: url, named: "a.heic", to: .med, inDirectory: directory, onlyIfLighterThan: byteCount + 1)
        guard case .written = outcome else {
            return XCTFail("Expected the size to be kept, got \(outcome)")
        }
    }


    // MARK: - What a JPEG can hold without loss

    func testAPhotographIsOneOpaqueImage() throws {
        let url = try makePhotograph(width: 800, height: 600)
        XCTAssertTrue(ObvPhotoTranscoder.isOneOpaqueImage(photoAt: url))
    }

    func testAnImageWithAnAlphaChannelIsNotOneOpaqueImage() throws {
        let url = try makeImage(type: .png, frames: 1, withAlpha: true)
        XCTAssertFalse(ObvPhotoTranscoder.isOneOpaqueImage(photoAt: url))
    }

    func testAnOpaquePNGIsOneOpaqueImage() throws {
        let url = try makeImage(type: .png, frames: 1, withAlpha: false)
        XCTAssertTrue(ObvPhotoTranscoder.isOneOpaqueImage(photoAt: url))
    }

    /// A HEIC with several frames is still `public.heic`, so only the file can say.
    func testAHEICWithTwoFramesIsNotOneOpaqueImage() throws {
        let url = try makeImage(type: .heic, frames: 2, withAlpha: false)
        XCTAssertFalse(ObvPhotoTranscoder.isOneOpaqueImage(photoAt: url))
    }

    func testSomethingThatIsNotAnImageIsNotOneOpaqueImage() throws {
        let url = directory.appendingPathComponent("not-an-image.jpeg")
        try Data("not an image".utf8).write(to: url)
        XCTAssertFalse(ObvPhotoTranscoder.isOneOpaqueImage(photoAt: url))
    }


    // MARK: - Fixtures

    /// Writes an image of `type` holding `frames` copies of one small picture, with or without an alpha channel in use.
    ///
    /// Skips the test when ImageIO cannot write `type` here, which is the case for HEIC on some simulators.
    private func makeImage(type: UTType, frames: Int, withAlpha: Bool) throws -> URL {

        let size = 64
        let context = try XCTUnwrap(CGContext(data: nil,
                                              width: size,
                                              height: size,
                                              bitsPerComponent: 8,
                                              bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: (withAlpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        if withAlpha {
            context.clear(CGRect(x: 0, y: 0, width: size / 2, height: size / 2))
        }
        let image = try XCTUnwrap(context.makeImage())

        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(type.preferredFilenameExtension ?? "img")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil) else {
            throw XCTSkip("ImageIO cannot write \(type.identifier) here")
        }
        for _ in 0..<frames {
            CGImageDestinationAddImage(destination, image, nil)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("ImageIO cannot write \(type.identifier) here")
        }

        return url

    }


    /// Writes a JPEG of the given size, optionally carrying an EXIF orientation.
    ///
    /// Deliberately not a flat colour: a photograph of one colour compresses to almost nothing and would make the byte counts above
    /// meaningless. A gradient gives the encoder something to do.
    private func makePhotograph(width: Int, height: Int, orientation: Int? = nil) throws -> URL {

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil,
                                              width: width,
                                              height: height,
                                              bitsPerComponent: 8,
                                              bytesPerRow: 0,
                                              space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))

        let gradient = try XCTUnwrap(CGGradient(colorsSpace: colorSpace,
                                                colors: [CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1),
                                                         CGColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1)] as CFArray,
                                                locations: [0, 1]))
        context.drawLinearGradient(gradient,
                                   start: .zero,
                                   end: CGPoint(x: width, y: height),
                                   options: [])

        let image = try XCTUnwrap(context.makeImage())

        let url = directory.appendingPathComponent("\(UUID().uuidString).jpeg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        return url

    }

}
