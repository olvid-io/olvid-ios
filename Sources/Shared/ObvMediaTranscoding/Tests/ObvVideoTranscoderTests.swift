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
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers
import ObvAppTypes
@testable import ObvMediaTranscoding


/// What `ObvVideoTranscoder` does to a clip, and what it declines to do to one.
///
/// The fixtures are generated rather than checked in, so that each clip's size and bitrate are visible in the test. They are filled with
/// noise, a flat colour encoding so small that most questions below would answer the same whatever the code does.
final class ObvVideoTranscoderTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }


    // MARK: - Reading a clip

    func testThePixelSizeOfAClipIsRead() async throws {
        let url = try await makeClip(width: 1920, height: 1080)
        let pixelSize = await ObvVideoTranscoder.pixelSize(ofVideoAt: url)
        let size = try XCTUnwrap(pixelSize)
        XCTAssertEqual(size.width, 1920)
        XCTAssertEqual(size.height, 1080)
    }


    /// A file with no video track at all must answer nil rather than being fed to an exporter. This is the guard that keeps an audio
    /// file that somehow reached here from being treated as a clip.
    func testThePixelSizeOfSomethingThatIsNotAClipCannotBeRead() async throws {
        let url = directory.appendingPathComponent("not-a-clip.mp4")
        try Data("this is not a video".utf8).write(to: url)
        let size = await ObvVideoTranscoder.pixelSize(ofVideoAt: url)
        XCTAssertNil(size)
    }


    /// AVFoundation refuses a file without an extension, as a `Fyle` is, which is why `DraftVideoVariantsMaker` goes through a hardlink.
    /// The same bytes are read under two names, and the one without an extension is asserted unreadable: if that ever changes, this test
    /// fails so that someone looks. The control shows the name is the only difference.
    func testAClipIsUnreadableWithoutAnExtensionWhichIsWhyTheMakerUsesAHardlink() async throws {

        let withExtension = try await makeClip(width: 1920, height: 1080)

        let withoutExtension = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: withExtension, to: withoutExtension)

        let readWithTheExtension = await ObvVideoTranscoder.pixelSize(ofVideoAt: withExtension)
        let readWithoutIt = await ObvVideoTranscoder.pixelSize(ofVideoAt: withoutExtension)

        XCTAssertEqual(readWithTheExtension?.width, 1_920, "the control must be readable, or this measures nothing")
        XCTAssertEqual(readWithTheExtension?.height, 1_080)
        XCTAssertNil(readWithoutIt, "measured on 2026-09-14: the same bytes under a name with no extension cannot be read at all")

    }


    // MARK: - Whether an export is worth doing

    /// **The question the whole feature turns on.** A heavy 1080p clip must be recognised as worth exporting at Low — if this answers
    /// false, the size points at the original, no export ever runs, and the composition bar does nothing whatever the reader picks.
    func testAHeavyClipIsWorthExportingAtASmallerSize() async throws {
        let url = try await makeClip(width: 1920, height: 1080, bitrate: 20_000_000)
        let worthIt = await ObvVideoTranscoder.transcodingWouldReduce(videoAt: url, to: .low)
        XCTAssertTrue(worthIt, "a 20 Mb/s 1080p clip must be worth exporting at Low")
    }


    /// The estimate is what answers that question, so it must be a number and it must be smaller than the file. Asserted separately
    /// from the question above so that a failure says which of the two is wrong.
    func testWhatAnExportWouldWeighIsEstimatedWithoutEncodingAnything() async throws {
        let url = try await makeClip(width: 1920, height: 1080, bitrate: 20_000_000)
        let attached = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
        let factsRead = await ObvVideoTranscoder.facts(ofVideoAt: url)
        let facts = try XCTUnwrap(factsRead)
        let estimate = try XCTUnwrap(ObvVideoTranscoder.estimatedByteCount(of: facts, to: .low))
        XCTAssertGreaterThan(estimate, 0)
        XCTAssertLessThan(estimate, attached)
    }


    /// `max` is the clip itself and is never an export, whatever it weighs.
    func testMaxIsNeverAnExport() async throws {
        let url = try await makeClip(width: 1920, height: 1080, bitrate: 20_000_000)
        let worthIt = await ObvVideoTranscoder.transcodingWouldReduce(videoAt: url, to: .max)
        XCTAssertFalse(worthIt)
        let factsRead = await ObvVideoTranscoder.facts(ofVideoAt: url)
        let facts = try XCTUnwrap(factsRead)
        XCTAssertNil(ObvVideoTranscoder.estimatedByteCount(of: facts, to: .max))
    }


    /// A clip that is already small enough must be left alone. A cap is a ceiling and never a target, so the answer here is what makes
    /// a small clip's size point at the original rather than being re-encoded into something larger.
    ///
    /// Filled with one grey rather than with noise: on noise the encoder does not hold 200 kb/s, and the clip came out between 0.4 and
    /// 3.5 MB from one run to the next, against an export estimated at 1.29 MB.
    func testAClipThatIsAlreadyLightIsNotWorthExporting() async throws {
        let url = try await makeClip(width: 640, height: 480, bitrate: 200_000, filledWithNoise: false)
        let worthIt = await ObvVideoTranscoder.transcodingWouldReduce(videoAt: url, to: .hi)
        XCTAssertFalse(worthIt, "a small, already-compressed clip must not be exported at Hi")
    }


    // MARK: - What the size menu shows

    func testTheFactsOfAClipAreRead() async throws {
        let withSound = try await makeClip(width: 640, height: 360, seconds: 2, withSound: true)
        let withoutSound = try await makeClip(width: 640, height: 360, seconds: 2)
        let readWithSound = await ObvVideoTranscoder.facts(ofVideoAt: withSound)
        let readWithoutSound = await ObvVideoTranscoder.facts(ofVideoAt: withoutSound)
        let factsWithSound = try XCTUnwrap(readWithSound)
        let factsWithoutSound = try XCTUnwrap(readWithoutSound)
        XCTAssertEqual(factsWithSound.durationInSeconds, 2, accuracy: 0.1)
        XCTAssertEqual(factsWithSound.channelsOfTheSound, 1, "the fixture's sound is mono")
        XCTAssertEqual(factsWithoutSound.channelsOfTheSound, 0)
    }


    func testSomethingThatIsNotAClipHasNoFacts() async throws {
        let url = directory.appendingPathComponent("not-a-clip.mp4")
        try Data("this is not a video".utf8).write(to: url)
        let facts = await ObvVideoTranscoder.facts(ofVideoAt: url)
        XCTAssertNil(facts)
    }


    /// The writer encodes the sound at 64 kb/s per channel at most, so the estimate must too. Compared as ratios against a clip without
    /// sound, so that the encoder's overshoot cancels out.
    func testTheSoundIsEstimatedAtTheBitrateTheWriterGivesIt() throws {

        let silent = ObvVideoTranscoder.ClipFacts(durationInSeconds: 60, channelsOfTheSound: 0)
        let mono = ObvVideoTranscoder.ClipFacts(durationInSeconds: 60, channelsOfTheSound: 1)
        let stereo = ObvVideoTranscoder.ClipFacts(durationInSeconds: 60, channelsOfTheSound: 2)

        func ratio(_ facts: ObvVideoTranscoder.ClipFacts, at format: ObvMediaFormat) throws -> Double {
            let withSound = try XCTUnwrap(ObvVideoTranscoder.estimatedByteCount(of: facts, to: format))
            let withoutSound = try XCTUnwrap(ObvVideoTranscoder.estimatedByteCount(of: silent, to: format))
            return Double(withSound) / Double(withoutSound)
        }

        let low = try XCTUnwrap(ObvMediaFormat.low.videoBitRate)
        let med = try XCTUnwrap(ObvMediaFormat.med.videoBitRate)

        XCTAssertEqual(try ratio(mono, at: .low), Double(low + 64_000) / Double(low), accuracy: 1e-6)
        XCTAssertEqual(try ratio(stereo, at: .low), Double(low + 96_000) / Double(low), accuracy: 1e-6)
        XCTAssertEqual(try ratio(mono, at: .med), Double(med + 64_000) / Double(med), accuracy: 1e-6)
        XCTAssertEqual(try ratio(stereo, at: .med), Double(med + 128_000) / Double(med), accuracy: 1e-6)

    }


    /// The menu shows the estimate only when the maker would export. Otherwise the size uses the file of a larger one, and the menu
    /// shows that file's weight, which is exact.
    func testTheWeightIfChosenIsTheEstimateOnlyWhenTheExportWouldBeMade() throws {

        let facts = ObvVideoTranscoder.ClipFacts(durationInSeconds: 60, channelsOfTheSound: 2)
        let estimate = try XCTUnwrap(ObvVideoTranscoder.estimatedByteCount(of: facts, to: .low))

        let wellBelowTheCeiling = ObvVideoTranscoder.weightIfChosen(.low, ofAClipWith: facts, belowACeilingOf: estimate * 10)
        XCTAssertEqual(wellBelowTheCeiling.byteCount, estimate)
        XCTAssertTrue(wellBelowTheCeiling.isAnEstimate)

        // A saving of 4 %, under the 5 % an export must save.
        let ceilingBarelyAbove = Int64(Double(estimate) / 0.96)
        let barelyBelowTheCeiling = ObvVideoTranscoder.weightIfChosen(.low, ofAClipWith: facts, belowACeilingOf: ceilingBarelyAbove)
        XCTAssertEqual(barelyBelowTheCeiling.byteCount, ceilingBarelyAbove)
        XCTAssertFalse(barelyBelowTheCeiling.isAnEstimate)

        let unreadable = ObvVideoTranscoder.weightIfChosen(.low, ofAClipWith: nil, belowACeilingOf: 123_456)
        XCTAssertEqual(unreadable.byteCount, 123_456, "a clip that cannot be read is never exported")
        XCTAssertFalse(unreadable.isAnEstimate)

        let atMax = ObvVideoTranscoder.weightIfChosen(.max, ofAClipWith: facts, belowACeilingOf: 123_456)
        XCTAssertEqual(atMax.byteCount, 123_456, "max is never an export")
        XCTAssertFalse(atMax.isAnEstimate)

    }


    /// **What the feature rests on.** If the menu and the maker disagree, the reader picks a size shown at one weight and gets another.
    /// Asked on both sides of the 5 % threshold, and of a ceiling lighter than the export.
    func testTheMenuAndTheMakerGiveTheSameAnswer() async throws {

        let url = try await makeClip(width: 1920, height: 1080, bitrate: 20_000_000, withSound: true)
        let factsRead = await ObvVideoTranscoder.facts(ofVideoAt: url)
        let facts = try XCTUnwrap(factsRead)
        let estimate = try XCTUnwrap(ObvVideoTranscoder.estimatedByteCount(of: facts, to: .low))

        let ceilings = [estimate / 2, estimate, Int64(Double(estimate) / 0.96), Int64(Double(estimate) / 0.94), estimate * 2]

        for ceiling in ceilings {
            let theMakerWouldExport = await ObvVideoTranscoder.transcodingWouldReduce(videoAt: url, to: .low, belowACeilingOf: ceiling)
            let theMenuShowsAnEstimate = ObvVideoTranscoder.weightIfChosen(.low, ofAClipWith: facts, belowACeilingOf: ceiling).isAnEstimate
            XCTAssertEqual(theMenuShowsAnEstimate, theMakerWouldExport, "a ceiling of \(ceiling) bytes against an estimate of \(estimate)")
        }

    }


    // MARK: - The export under a ceiling

    func testAnExportLighterThanTheCeilingIsKept() async throws {
        let url = try await makeClip(width: 1920, height: 1080, bitrate: 20_000_000)
        let outcome = try await ObvVideoTranscoder.transcode(videoAt: url, named: "IMG_4021.MOV", to: .low, inDirectory: directory, onlyIfLighterThan: .max)
        guard case .written(let exported) = outcome else {
            return XCTFail("Expected the export to be kept, got \(outcome)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.temporaryURL.path))
    }


    func testAnExportNotLighterThanTheCeilingIsRefusedAndItsFileDeleted() async throws {
        let url = try await makeClip(width: 1920, height: 1080, bitrate: 20_000_000)
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        let outcome = try await ObvVideoTranscoder.transcode(videoAt: url, named: "IMG_4021.MOV", to: .low, inDirectory: directory, onlyIfLighterThan: 1)

        guard case .notLighterThanTheCeiling(let byteCount) = outcome else {
            return XCTFail("Expected the export to be refused, got \(outcome)")
        }
        XCTAssertGreaterThan(byteCount, 0)
        let filesAfter = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(Set(filesAfter), Set(filesBefore), "A refused export must leave nothing on disk")
    }


    // MARK: - The export itself

    /// **The end-to-end question.** What comes out must be smaller, must be inside the frame the size names, and must be an MP4 — the
    /// container being what a recipient on Android or on a desktop has to be able to open.
    func testExportingAtASizeProducesASmallerClipInsideThatFrame() async throws {

        let url = try await makeClip(width: 1920, height: 1080, bitrate: 20_000_000)
        let attached = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)

        let exported = try await ObvVideoTranscoder.transcode(videoAt: url, named: "IMG_4021.MOV", to: .low, inDirectory: directory)

        XCTAssertLessThan(exported.byteCount, attached)
        XCTAssertLessThanOrEqual(max(exported.pixelWidth, exported.pixelHeight), 1_280)
        XCTAssertLessThanOrEqual(min(exported.pixelWidth, exported.pixelHeight), 720)
        XCTAssertEqual(exported.contentType, .mpeg4Movie)
        XCTAssertEqual(exported.fileName, "IMG_4021.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.temporaryURL.path))
    }


    /// The progress must actually be reported, and must end at 1. A ring that never moves is indistinguishable from an export that has
    /// hung, which is the single thing a reader watching one is most likely to conclude.
    func testAnExportReportsItsProgressAndEndsAtOne() async throws {

        let url = try await makeClip(width: 1920, height: 1080, bitrate: 20_000_000, seconds: 4)

        let reports = ReportedFractions()
        _ = try await ObvVideoTranscoder.transcode(videoAt: url, named: "clip.mov", to: .low, inDirectory: directory) { fraction in
            reports.append(fraction)
        }

        let seen = reports.all
        XCTAssertFalse(seen.isEmpty, "the export must report its progress at least once")
        XCTAssertEqual(seen.last, 1.0, "the last thing an export says must be that it is finished")
    }


    /// A clip above 30 frames per second comes out at 30: a 120 fps iPhone clip exported at its own rate weighed as much at 720p as the
    /// phone's 1080p original.
    func testAClipAboveThirtyFramesPerSecondComesOutAtThirty() async throws {
        let url = try await makeClip(width: 1280, height: 720, seconds: 2, framesPerSecond: 60)
        let exported = try await ObvVideoTranscoder.transcode(videoAt: url, named: "clip.mov", to: .low, inDirectory: directory)
        let framesPerSecond = try await nominalFrameRate(ofVideoAt: exported.temporaryURL)
        XCTAssertEqual(framesPerSecond, 30, accuracy: 0.5)
    }


    /// The cap is a ceiling, not a target: a clip at 30 frames per second or less keeps its own rate.
    func testAClipAtOrBelowThirtyFramesPerSecondKeepsItsOwn() async throws {
        let url = try await makeClip(width: 1280, height: 720, seconds: 2, framesPerSecond: 24)
        let exported = try await ObvVideoTranscoder.transcode(videoAt: url, named: "clip.mov", to: .low, inDirectory: directory)
        let framesPerSecond = try await nominalFrameRate(ofVideoAt: exported.temporaryURL)
        XCTAssertEqual(framesPerSecond, 24, accuracy: 0.5)
    }


    /// A size that does not transcode is refused rather than quietly handed back a copy of the original, for the same reason its
    /// photographic sibling refuses it: a caller that has not asked whether the export is worth doing is a caller that is about to write
    /// a file and call it a smaller one.
    func testMaxIsRefusedRatherThanCopied() async throws {
        let url = try await makeClip(width: 1920, height: 1080)
        do {
            _ = try await ObvVideoTranscoder.transcode(videoAt: url, named: "clip.mov", to: .max, inDirectory: directory)
            XCTFail("exporting at max should throw")
        } catch ObvVideoTranscoder.ObvError.thisFormatDoesNotTranscode {
            // Expected.
        }
    }


    /// A file no exporter can read must throw rather than write something.
    func testSomethingThatCannotBeReadThrowsRatherThanWritingAnything() async throws {
        let url = directory.appendingPathComponent("not-a-clip.mov")
        try Data("this is not a video".utf8).write(to: url)
        do {
            _ = try await ObvVideoTranscoder.transcode(videoAt: url, named: "clip.mov", to: .low, inDirectory: directory)
            XCTFail("exporting something unreadable should throw")
        } catch {
            // Expected. Which error it is does not matter; that nothing was written does.
            let leftBehind = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertEqual(leftBehind, ["not-a-clip.mov"], "nothing but the source must be left in the directory")
        }
    }


    // MARK: - The sound

    /// A clip with two enabled sound tracks, the first silent and the second carrying the tone, must come out with the tone: a player
    /// plays every enabled track, and so must the export. Keeping the first track alone sent such clips mute.
    ///
    /// The fixture's second track is measured before the export, so that a reader that answered silence for everything could not pass
    /// this test by reading the output; the tone is ``SoundForTheFixture/toneAmplitude`` of full scale and AAC brings it back within a
    /// few percent.
    func testASilentFirstSoundTrackDoesNotMuteTheSecond() async throws {

        let url = try await makeClip(width: 640, height: 360, seconds: 2, withSound: true, withASilentSoundTrackFirst: true)

        let sourceTracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        XCTAssertEqual(sourceTracks.count, 2, "the fixture must have two sound tracks, or this tests nothing")
        for track in sourceTracks {
            let isEnabled = try await track.load(.isEnabled)
            XCTAssertTrue(isEnabled, "both sound tracks of the fixture must be enabled, or this tests nothing")
        }
        let silentPeak = try await peakLevel(ofTheSoundAt: url, track: 0)
        let tonePeak = try await peakLevel(ofTheSoundAt: url, track: 1)
        XCTAssertEqual(silentPeak, 0, accuracy: 0.001, "the fixture's first track must be silent")
        XCTAssertEqual(tonePeak, SoundForTheFixture.toneAmplitude, accuracy: 0.03, "the fixture's second track must carry the tone")

        let transcoded = try await ObvVideoTranscoder.transcode(videoAt: url, named: "clip.mov", to: .low, inDirectory: directory)

        let outputTracks = try await AVURLAsset(url: transcoded.temporaryURL).loadTracks(withMediaType: .audio)
        XCTAssertEqual(outputTracks.count, 1, "the export writes one sound track")
        let outputPeak = try await peakLevel(ofTheSoundAt: transcoded.temporaryURL)
        XCTAssertEqual(outputPeak, SoundForTheFixture.toneAmplitude, accuracy: 0.03, "the tone of the second track must survive the export")

    }


    // MARK: - A writer that fails

    /// The writer fails on the picture's side while the clip also has sound: the export must still end, with an error, and leave nothing
    /// behind.
    ///
    /// The picture's pump sees its own append fail and stops. The sound's pump stops only if its block runs again, which AVFoundation
    /// documents for an input that *becomes ready for more media data again*, and does not document for a writer that has failed. The
    /// export runs in a task of its own and the test waits with a timeout: an export stuck on a continuation cannot be cancelled, so
    /// awaiting it directly would hang the suite rather than fail this test.
    func testAnExportWhoseWriterFailsEndsWithAnErrorAndLeavesNothingBehind() async throws {

        let url = try await makeClip(width: 640, height: 360, seconds: 2, withSound: true)
        let soundTracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        XCTAssertEqual(soundTracks.count, 1, "without a sound track there is no second pump to be left waiting, and this tests nothing")

        let directory = self.directory!
        let outcome = ExportOutcome()
        let exportHasEnded = expectation(description: "the export has ended")
        let start = ContinuousClock.now
        Task {
            do {
                _ = try await ObvVideoTranscoder.transcode(videoAt: url, named: "clip.mov", to: .low, inDirectory: directory, onProgress: nil, appendingAPictureOutOfOrderAfter: 10)
                outcome.set(.completed)
            } catch {
                outcome.set(.threw(error))
            }
            exportHasEnded.fulfill()
        }

        await fulfillment(of: [exportHasEnded], timeout: 30)
        let elapsed = ContinuousClock.now - start

        switch outcome.value {
        case .none:
            XCTFail("the export has not ended after \(elapsed)")
        case .completed:
            XCTFail("the export completed although its writer was made to fail")
        case .threw(let error):
            guard case ObvVideoTranscoder.ObvError.exportDidNotComplete = error else {
                XCTFail("expected exportDidNotComplete, got \(error)")
                return
            }
            let leftBehind = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertEqual(leftBehind, [url.lastPathComponent], "nothing but the source must be left in the directory")
        }

    }


    // MARK: - Cancelling

    /// Cancelled while it runs, an export must end with `exportWasCancelled` and leave nothing behind, thirty times over, the cancel
    /// landing at a different point each time.
    ///
    /// Cancelling used to call `cancelReading()` from another thread while a pump could be inside `copyNextSampleBuffer()`, which
    /// crashed the app now and then. One cancel rarely lands in that window, hence the repetitions. Each export is waited for with a
    /// timeout, so that one that never ends fails the test rather than hanging the suite.
    func testAnExportCancelledWhileItRunsEndsAsCancelledAndLeavesNothingBehind() async throws {

        let url = try await makeClip(width: 640, height: 360, seconds: 6, withSound: true)
        let directory = self.directory!

        for attempt in 0..<30 {

            // From 0% to 45%.
            let cancelsAt = Double(attempt % 10) / 20
            let canceller = CancelsOnAReport(atOrAfter: cancelsAt)
            let outcome = ExportOutcome()
            let exportHasEnded = expectation(description: "attempt \(attempt): the export has ended")

            let export = Task {
                do {
                    _ = try await ObvVideoTranscoder.transcode(videoAt: url, named: "clip.mov", to: .low, inDirectory: directory, onProgress: { canceller.report($0) })
                    outcome.set(.completed)
                } catch {
                    outcome.set(.threw(error))
                }
                exportHasEnded.fulfill()
            }
            canceller.setTask(export)

            await fulfillment(of: [exportHasEnded], timeout: 30)

            switch outcome.value {
            case .none:
                XCTFail("attempt \(attempt): the export has not ended after it was cancelled at \(cancelsAt)")
                return
            case .completed:
                XCTFail("attempt \(attempt): the export completed although it was cancelled at \(cancelsAt)")
                return
            case .threw(let error):
                guard case ObvVideoTranscoder.ObvError.exportWasCancelled = error else {
                    XCTFail("attempt \(attempt): expected exportWasCancelled, got \(error)")
                    return
                }
            }

            let leftBehind = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertEqual(leftBehind, [url.lastPathComponent], "attempt \(attempt): nothing but the source must be left in the directory")

        }

    }


    // MARK: - Fixtures

    /// Cancels an export's task on the first progress report at or after a fraction, whichever of the report and the task comes first.
    ///
    /// **From another thread**, as the app does. A report is made on the picture's queue, between two reads, so cancelling from it would
    /// never overlap a read, and that overlap is what is being tested.
    private final class CancelsOnAReport: @unchecked Sendable {
        private let fraction: Double
        private let lock = NSLock()
        private var task: Task<Void, Never>?
        private var isDue = false
        init(atOrAfter fraction: Double) {
            self.fraction = fraction
        }
        func report(_ reported: Double) {
            guard reported >= fraction else { return }
            lock.lock(); defer { lock.unlock() }
            guard !isDue else { return }
            isDue = true
            if let task { Self.cancelFromAnotherThread(task) }
        }
        func setTask(_ task: Task<Void, Never>) {
            lock.lock(); defer { lock.unlock() }
            self.task = task
            if isDue { Self.cancelFromAnotherThread(task) }
        }
        private static func cancelFromAnotherThread(_ task: Task<Void, Never>) {
            DispatchQueue.global(qos: .userInitiated).async { task.cancel() }
        }
    }

    /// How an export run in a task of its own ended, read once that task has said so.
    private final class ExportOutcome: @unchecked Sendable {
        enum Value {
            case completed
            case threw(Error)
        }
        private let lock = NSLock()
        private var stored: Value?
        func set(_ value: Value) {
            lock.lock(); defer { lock.unlock() }
            stored = value
        }
        var value: Value? {
            lock.lock(); defer { lock.unlock() }
            return stored
        }
    }

    /// Collects the fractions an export reports, from whatever thread it reports them on.
    private final class ReportedFractions: @unchecked Sendable {
        private let lock = NSLock()
        private var fractions = [Double]()
        func append(_ fraction: Double) {
            lock.lock(); defer { lock.unlock() }
            fractions.append(fraction)
        }
        var all: [Double] {
            lock.lock(); defer { lock.unlock() }
            return fractions
        }
    }


    /// Writes a clip of the given frame, bitrate, length and frame rate, filled with noise, or with one grey when `filledWithNoise` is
    /// false, and with a mono sound track carrying a tone when `withSound` is true — preceded by a silent one, both enabled, when
    /// `withASilentSoundTrackFirst` is true as well.
    ///
    /// **The noise is load-bearing.** An encoder handed a flat colour produces a file of a few kilobytes whatever bitrate it is asked
    /// for, and every question this file asks about weights would then answer the same way whatever the code under test did. The grey
    /// is for the one test that needs a clip to be light.
    private func makeClip(width: Int, height: Int, bitrate: Int = 20_000_000, seconds: Int = 2, framesPerSecond: Int = 30, filledWithNoise: Bool = true, withSound: Bool = false, withASilentSoundTrackFirst: Bool = false) async throws -> URL {

        let url = directory.appendingPathComponent("\(UUID().uuidString).mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)

        // In the order the tracks will have in the file: the silent one first, when asked for.
        var sounds = [SoundForTheFixture]()
        if withSound {
            if withASilentSoundTrackFirst {
                sounds.append(try SoundForTheFixture(framesPerSecond: framesPerSecond, silent: true))
            }
            sounds.append(try SoundForTheFixture(framesPerSecond: framesPerSecond))
        }
        for sound in sounds {
            writer.add(sound.input)
        }

        // **Checked, because an `AVAssetWriter` that fails writes nothing and says nothing.** These tests share one hardware encoder
        // with whatever else the suite is running, and a fixture that came out empty used to arrive at the assertions as a clip with no
        // tracks — which fails somewhere else entirely, with a message about weights. `testAClipThatIsAlreadyLightIsNotWorthExporting`
        // failed exactly once that way, and passed on every run since; whatever it was, it must not be diagnosed twice.
        guard writer.startWriting() else {
            throw ObvError.couldNotWriteTheFixture(status: writer.status.rawValue, error: writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        func picture(_ frameIndex: Int) -> CVPixelBuffer? {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            guard let pixelBuffer else { return nil }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let byteCount = CVPixelBufferGetBytesPerRow(pixelBuffer) * height
                if filledWithNoise {
                    let bytes = base.assumingMemoryBound(to: UInt8.self)
                    for offset in stride(from: 0, to: byteCount, by: 7) {
                        bytes[offset] = UInt8(truncatingIfNeeded: frameIndex &* 31 &+ offset)
                    }
                } else {
                    // Every byte, `CVPixelBufferCreate` not initialising the memory: whatever it held would be noise too.
                    memset(base, 0x80, byteCount)
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            return pixelBuffer
        }

        // **Whichever input is ready is fed, and neither is waited for alone.** With two inputs, the writer holds one back until the
        // other catches up, and waiting for the picture before appending more sound deadlocked this fixture, intermittently: the sound,
        // encoded in blocks, lags behind what was appended to it. Each input is marked finished as soon as it has nothing more.
        let frameCount = seconds * framesPerSecond
        var nextPicture = 0
        var nextSound = [Int](repeating: 0, count: sounds.count)
        while nextPicture < frameCount || nextSound.contains(where: { $0 < frameCount }) {
            var appended = false
            if nextPicture < frameCount, input.isReadyForMoreMediaData {
                if let pixelBuffer = picture(nextPicture) {
                    adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(nextPicture), timescale: CMTimeScale(framesPerSecond)))
                }
                nextPicture += 1
                if nextPicture == frameCount {
                    input.markAsFinished()
                }
                appended = true
            }
            for (index, sound) in sounds.enumerated() where nextSound[index] < frameCount && sound.input.isReadyForMoreMediaData {
                sound.input.append(try sound.samples(forFrame: nextSound[index]))
                nextSound[index] += 1
                if nextSound[index] == frameCount {
                    sound.input.markAsFinished()
                }
                appended = true
            }
            if !appended {
                try await Task.sleep(seconds: 0.005)
            }
        }

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw ObvError.couldNotWriteTheFixture(status: writer.status.rawValue, error: writer.error)
        }

        let byteCount = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
        guard let byteCount, byteCount > 0 else {
            throw ObvError.theFixtureIsEmpty
        }

        return url

    }


    /// A 440 Hz tone — or silence — mono, 48 kHz, 16-bit PCM encoded as AAC, cut into one sample buffer per picture.
    private struct SoundForTheFixture {

        static let sampleRate = 48_000

        /// The tone's amplitude as a fraction of full scale, which is what ``peakLevel(ofTheSoundAt:)`` reads back.
        static let toneAmplitude: Float = 8_000 / 32_768

        let input: AVAssetWriterInput
        private let format: CMAudioFormatDescription
        private let samplesPerFrame: Int
        private let silent: Bool

        init(framesPerSecond: Int, silent: Bool = false) throws {
            self.silent = silent
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ])
            input.expectsMediaDataInRealTime = false
            var description = AudioStreamBasicDescription(mSampleRate: Float64(Self.sampleRate),
                                                          mFormatID: kAudioFormatLinearPCM,
                                                          mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                                          mBytesPerPacket: 2,
                                                          mFramesPerPacket: 1,
                                                          mBytesPerFrame: 2,
                                                          mChannelsPerFrame: 1,
                                                          mBitsPerChannel: 16,
                                                          mReserved: 0)
            var format: CMAudioFormatDescription?
            let status = CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
            guard status == noErr, let format else { throw ObvError.couldNotMakeTheSound(status: status) }
            self.format = format
            self.samplesPerFrame = Self.sampleRate / framesPerSecond
        }

        func samples(forFrame frameIndex: Int) throws -> CMSampleBuffer {
            let firstSample = frameIndex * samplesPerFrame
            var pcm = [Int16](repeating: 0, count: samplesPerFrame)
            if !silent {
                for index in 0..<samplesPerFrame {
                    let time = Double(firstSample + index) / Double(Self.sampleRate)
                    pcm[index] = Int16(8_000 * sin(2 * .pi * 440 * time))
                }
            }
            let byteCount = samplesPerFrame * MemoryLayout<Int16>.size
            var block: CMBlockBuffer?
            var status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
            guard status == noErr, let block else { throw ObvError.couldNotMakeTheSound(status: status) }
            status = pcm.withUnsafeBytes { bytes in
                CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
            }
            guard status == noErr else { throw ObvError.couldNotMakeTheSound(status: status) }
            var sampleBuffer: CMSampleBuffer?
            status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil,
                                                                          dataBuffer: block,
                                                                          formatDescription: format,
                                                                          sampleCount: samplesPerFrame,
                                                                          presentationTimeStamp: CMTime(value: CMTimeValue(firstSample), timescale: CMTimeScale(Self.sampleRate)),
                                                                          packetDescriptions: nil,
                                                                          sampleBufferOut: &sampleBuffer)
            guard status == noErr, let sampleBuffer else { throw ObvError.couldNotMakeTheSound(status: status) }
            return sampleBuffer
        }

    }


    /// The loudest sample, as a fraction of full scale, of the sound track at `index` of the clip at `url`: 0 for silence, about
    /// ``SoundForTheFixture/toneAmplitude`` for the fixture's tone.
    private func peakLevel(ofTheSoundAt url: URL, track index: Int = 0) async throws -> Float {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.indices.contains(index) else { throw ObvError.theClipHasNoSuchSoundTrack(index: index, count: tracks.count) }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: tracks[index], outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw ObvError.couldNotReadTheSound(error: reader.error) }
        var peak: Float = 0
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0, count: byteCount / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: bytes.baseAddress!)
            }
            guard status == noErr else { throw ObvError.couldNotReadTheSound(error: nil) }
            for sample in samples {
                peak = max(peak, abs(sample))
            }
        }
        return peak
    }


    private func nominalFrameRate(ofVideoAt url: URL) async throws -> Float {
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        return try await track.load(.nominalFrameRate)
    }


    private enum ObvError: Error {
        case couldNotWriteTheFixture(status: Int, error: Error?)
        case theFixtureIsEmpty
        case couldNotMakeTheSound(status: OSStatus)
        case theClipHasNoSuchSoundTrack(index: Int, count: Int)
        case couldNotReadTheSound(error: Error?)
    }

}
