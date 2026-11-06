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
import CoreData
import UniformTypeIdentifiers
import ObvAppTypes
@testable import ObvUICoreData


/// What a draft photograph's alternative sizes are, and what the join they hang off does when one of them is chosen.
///
/// The graph is built by inserting bare managed objects and wiring them with KVC, as `FetchedResultsControllerSortDescriptorTests`
/// does, and nothing is ever saved: building a *valid* `PersistedDraft` would mean building a discussion and an owned identity, and
/// none of the behaviour under test can tell the difference. The store is SQLite over `/dev/null` and not `NSInMemoryStoreType`,
/// which sorts in memory, where SQLite sorts in SQL, and so does not behave like the store the app uses.
final class PersistedDraftFyleJoinVariantTests: XCTestCase {

    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = try FetchedResultsControllerSortDescriptorTests.makeInMemoryObvMessengerContext()
    }

    override func tearDownWithError() throws {
        context = nil
    }


    // MARK: - Which attachments the size choice applies to

    /// An allowlist: every size below `max` is a JPEG, and a type that can carry transparency or animation would lose it. PNG is off the
    /// list, screenshots included, because an iPhone screenshot has transparent corners.
    func testOnlyAPhotographIsOfferedASize() throws {

        let eligible: [UTType] = [.jpeg, .heic, .heif, .rawImage, UTType("com.adobe.raw-image"), UTType("com.nikon.raw-image")].compactMap { $0 }
        for contentType in eligible {
            let join = try makeJoin(contentType: contentType)
            XCTAssertTrue(join.isPhotoEligibleForAFormatChoice, "\(contentType.identifier) should be offered a size")
        }

        let notEligible: [UTType] = [.png, .gif, .svg, .webP, .tiff, .bmp, UTType("public.heics"), UTType("public.avif"), .pdf, .mpeg4Movie, .zip, .olvidLinkPreview].compactMap { $0 }
        for contentType in notEligible {
            let join = try makeJoin(contentType: contentType)
            XCTAssertFalse(join.isPhotoEligibleForAFormatChoice, "\(contentType.identifier) should not be offered a size")
        }

    }


    /// The join's type becomes the chosen size's, a JPEG or an MP4, so eligibility is asked of the `max` variant's. Otherwise any file
    /// transcoded once would pass the list.
    func testEligibilityIsDecidedByTheOriginalsTypeAndNotByTheChosenSizes() throws {

        let png = try makeJoin(contentType: .png, fileName: "screenshot.png")
        try givePhotographItsOriginal(png)
        png.setValue(UTType.jpeg.identifier, forKey: "uti")
        XCTAssertFalse(png.isPhotoEligibleForAFormatChoice)

        let avi = try makeJoin(contentType: .avi, fileName: "clip.avi")
        try givePhotographItsOriginal(avi)
        avi.setValue(UTType.mpeg4Movie.identifier, forKey: "uti")
        XCTAssertFalse(avi.isVideoEligibleForAFormatChoice)

        let heic = try makeJoin(contentType: .heic)
        try givePhotographItsOriginal(heic)
        heic.setValue(UTType.jpeg.identifier, forKey: "uti")
        XCTAssertTrue(heic.isPhotoEligibleForAFormatChoice)

    }


    /// Everything the size choice does not apply to must be untouched by all of this — which is what makes files, audio and link previews
    /// behave exactly as they did before sizes existed.
    func testSomethingThatIsNeitherAPhotographNorAVideoHasNoSizesToWrite() throws {
        let join = try makeJoin(contentType: .pdf)
        XCTAssertTrue(join.photoFormatsWithoutAFile.isEmpty)
        XCTAssertTrue(join.videoFormatsWithoutAFile(whenSelectedFormatIs: .low).isEmpty)
        XCTAssertTrue(join.fyleForFormat.isEmpty)
    }


    /// **The audio half of this is the one worth having.** `public.mpeg-4` is on the list, and the question that follows is whether an `m4a`
    /// voice message is swept up by it. It is not: `com.apple.m4a-audio` and `public.mpeg-4-audio` do not conform to it. Were that ever to
    /// change, every voice message in a draft would be fed to an exporter, and this is what would say so.
    ///
    /// The other half: containers AVFoundation cannot read conform to `public.movie` and are not offered a size.
    func testOnlyAVideoIsOfferedASizeAndAVoiceMessageIsNot() throws {

        let eligible: [UTType] = [.quickTimeMovie, .mpeg4Movie, UTType("com.apple.m4v-video"), UTType("public.3gpp")].compactMap { $0 }
        for contentType in eligible {
            let join = try makeJoin(contentType: contentType)
            XCTAssertTrue(join.isVideoEligibleForAFormatChoice, "\(contentType.identifier) should be offered a size")
        }

        let notEligible: [UTType] = [.movie, .video, .avi, UTType("org.matroska.mkv"), UTType("org.webmproject.webm"),
                                     .m4a, .mpeg4Audio, .mp3, .audio, .jpeg, .gif, .pdf, .zip, .olvidLinkPreview].compactMap { $0 }
        for contentType in notEligible {
            let join = try makeJoin(contentType: contentType)
            XCTAssertFalse(join.isVideoEligibleForAFormatChoice, "\(contentType.identifier) should not be offered a size")
        }

    }


    /// **A video is offered two sizes and not four**, which is the whole difference between the two media: `max` costs nothing, the chosen
    /// size costs an export of tens of seconds, and the two that were not chosen are not made at all.
    func testAVideoIsOnlyEverGivenMaxAndTheSizeThatWasChosen() throws {

        let join = try makeJoin(contentType: .quickTimeMovie)

        XCTAssertEqual(join.videoFormatsWithoutAFile(whenSelectedFormatIs: .low), [.max, .low])
        XCTAssertEqual(join.videoFormatsWithoutAFile(whenSelectedFormatIs: .med), [.max, .med])

        // `max` chosen asks for one thing and not for the same thing twice.
        XCTAssertEqual(join.videoFormatsWithoutAFile(whenSelectedFormatIs: .max), [.max])

    }


    // MARK: - The sizes themselves

    func testAPhotographStartsWithNoSizeAndWantsAllFourLargestFirst() throws {
        let join = try makeJoin(contentType: .heic)
        XCTAssertEqual(join.photoFormatsWithoutAFile, [.max, .hi, .med, .low],
                       "Largest first, so that max is recorded before anything that points at it")
    }


    func testASizeThatHasBeenWrittenIsNoLongerWanted() throws {

        let join = try makeJoin(contentType: .heic)
        try givePhotographItsOriginal(join)

        XCTAssertEqual(join.photoFormatsWithoutAFile, [.hi, .med, .low])
        XCTAssertEqual(Set(join.fyleForFormat.keys), [.max])

        _ = try PersistedDraftFyleJoinVariant(draftFyleJoin: join,
                                              format: .med,
                                              fyle: try makeFyle(named: "hd"),
                                              fileName: "photo.jpeg",
                                              contentType: .jpeg,
                                              byteCount: 450_000,
                                              pixelWidth: 2_048,
                                              pixelHeight: 1_536)

        XCTAssertEqual(join.photoFormatsWithoutAFile, [.hi, .low])
        XCTAssertEqual(Set(join.fyleForFormat.keys), [.max, .med])

    }


    /// Asking twice for the same size is refused rather than silently making a second row, the writing pass being allowed to run again
    /// over a draft it has already served.
    func testASizeCannotBeWrittenTwice() throws {
        let join = try makeJoin(contentType: .heic)
        try givePhotographItsOriginal(join)
        XCTAssertThrowsError(try PersistedDraftFyleJoinVariant(draftFyleJoin: join,
                                                              format: .max,
                                                              fyle: try makeFyle(named: "again"),
                                                              fileName: "photo.heic",
                                                              contentType: .heic,
                                                              byteCount: 1,
                                                              pixelWidth: 1,
                                                              pixelHeight: 1))
        XCTAssertEqual(join.variants.count, 1)
    }


    /// A size the photograph is already within points at the original file, so several sizes share one `Fyle` and the menu shows the
    /// same weight for each of them. Resolved against the `max` variant and not against the join, which by then may have moved.
    func testASizeThatNeedsNoFileOfItsOwnPointsAtTheOriginal() throws {

        let join = try makeJoin(contentType: .heic, fileName: "small.heic")
        try givePhotographItsOriginal(join, byteCount: 120_000, pixelWidth: 800, pixelHeight: 600)

        for format in [ObvMediaFormat.hi, .med, .low] {
            try PersistedDraftFyleJoinVariant.createVariantPointingAtTheOriginal(of: join, format: format, byteCount: 120_000, pixelWidth: 800, pixelHeight: 600)
        }

        XCTAssertTrue(join.photoFormatsWithoutAFile.isEmpty)
        XCTAssertEqual(Set(join.fyleForFormat.values.map(\.objectID)).count, 1, "One photograph, one file, four rows")
        for variant in join.variants {
            XCTAssertEqual(variant.fileName, "small.heic")
            XCTAssertEqual(variant.contentType, .heic)
            XCTAssertEqual(variant.byteCount, 120_000)
        }

    }


    /// A size whose encode was no lighter than a larger transcoded size uses that size's file, with its name, type, weight and pixel size.
    func testASizeCanUseTheFileOfALargerSize() throws {

        let join = try makeJoin(contentType: .heic, fileName: "IMG_4021.HEIC")
        let original = try givePhotographItsOriginal(join)

        let medFyle = try makeFyle(named: "med")
        _ = try PersistedDraftFyleJoinVariant(draftFyleJoin: join, format: .med, fyle: medFyle, fileName: "IMG_4021.jpeg", contentType: .jpeg, byteCount: 450_000, pixelWidth: 2_048, pixelHeight: 1_536)

        try PersistedDraftFyleJoinVariant.createVariantPointingAtTheFileOf(try XCTUnwrap(join.variant(for: .med)), format: .low)

        let low = try XCTUnwrap(join.variant(for: .low))
        XCTAssertEqual(low.fyle?.objectID, medFyle.objectID)
        XCTAssertNotEqual(low.fyle?.objectID, original.objectID)
        XCTAssertEqual(low.fileName, "IMG_4021.jpeg")
        XCTAssertEqual(low.contentType, .jpeg)
        XCTAssertEqual(low.byteCount, 450_000)
        XCTAssertEqual(low.pixelWidth, 2_048)
        XCTAssertEqual(low.pixelHeight, 1_536)

        XCTAssertThrowsError(try PersistedDraftFyleJoinVariant.createVariantPointingAtTheFileOf(low, format: .low), "A size cannot be written twice")

    }


    // MARK: - Choosing a size

    /// The invariant the whole feature rests on: the join's `fyle`, `fileName` and `uti` mean *what will be sent*, so choosing a size
    /// rewrites all three. Nothing downstream of a draft needed changing because of it.
    func testChoosingASizePointsTheJoinAtThatFile() throws {

        let join = try makeJoin(contentType: .heic, fileName: "IMG_4021.HEIC")
        let original = try givePhotographItsOriginal(join)

        let hdFyle = try makeFyle(named: "hd")
        _ = try PersistedDraftFyleJoinVariant(draftFyleJoin: join, format: .med, fyle: hdFyle, fileName: "IMG_4021.jpeg", contentType: .jpeg, byteCount: 450_000, pixelWidth: 2_048, pixelHeight: 1_536)

        XCTAssertEqual(join.fyle?.objectID, original.objectID, "Nothing has been chosen yet")

        join.setSelectedFormat(.med)

        XCTAssertEqual(join.fyle?.objectID, hdFyle.objectID)
        XCTAssertEqual(join.fileName, "IMG_4021.jpeg")
        XCTAssertEqual(join.contentType, .jpeg)

        // And the original is still reachable, which is what the thumbnail and the QuickLook preview are built from.
        XCTAssertEqual(join.originalFyle?.objectID, original.objectID)

        join.setSelectedFormat(.max)

        XCTAssertEqual(join.fyle?.objectID, original.objectID)
        XCTAssertEqual(join.fileName, "IMG_4021.HEIC")
        XCTAssertEqual(join.contentType, .heic)

    }


    /// Choosing a size that has not been written yet is allowed — the menu never makes the reader wait, and the choice takes effect when
    /// the file lands. Meanwhile the join points at the nearest larger size with a file, here `max`.
    func testChoosingASizeThatDoesNotExistYetPointsAtTheOriginalWhenNothingElseExists() throws {

        let join = try makeJoin(contentType: .heic, fileName: "IMG_4021.HEIC")
        let original = try givePhotographItsOriginal(join)

        join.setSelectedFormat(.low)

        XCTAssertEqual(join.fyle?.objectID, original.objectID)
        XCTAssertEqual(join.fileName, "IMG_4021.HEIC")
        XCTAssertEqual(join.variantSent(whenSelectedFormatIs: .low)?.format, .max)

    }


    /// A chosen size with no file sends the nearest larger size that has one, **whatever was chosen before**: a clip exported at Hi and
    /// Med, whose Low export failed, goes out at Med whether the reader came to Low from Hi or from Max.
    func testChoosingASizeWithNoFileUsesTheNearestLargerSizeWhateverWasChosenBefore() throws {

        for previousChoice in [ObvMediaFormat.hi, .max] {

            let join = try makeJoin(contentType: .quickTimeMovie, fileName: "IMG_4022.MOV")
            let original = try givePhotographItsOriginal(join, byteCount: 30_000_000, pixelWidth: 3_840, pixelHeight: 2_160)
            let hiFyle = try makeFyle(named: "hi")
            let medFyle = try makeFyle(named: "med")
            _ = try PersistedDraftFyleJoinVariant(draftFyleJoin: join, format: .hi, fyle: hiFyle, fileName: "IMG_4022.mp4", contentType: .mpeg4Movie, byteCount: 9_000_000, pixelWidth: 1_920, pixelHeight: 1_080)
            _ = try PersistedDraftFyleJoinVariant(draftFyleJoin: join, format: .med, fyle: medFyle, fileName: "IMG_4022.mp4", contentType: .mpeg4Movie, byteCount: 4_000_000, pixelWidth: 1_280, pixelHeight: 720)

            join.setSelectedFormat(previousChoice)
            join.setSelectedFormat(.low)

            XCTAssertEqual(join.fyle?.objectID, medFyle.objectID, "Coming from \(previousChoice.rawValue)")
            XCTAssertNotEqual(join.fyle?.objectID, original.objectID)
            XCTAssertEqual(join.contentType, .mpeg4Movie)
            XCTAssertEqual(join.variantSent(whenSelectedFormatIs: .low)?.format, .med)

        }

    }


    /// Only larger sizes are fallen back to. A smaller one would send less than the reader asked for.
    func testChoosingASizeWithNoFileNeverFallsBackToASmallerOne() throws {

        let join = try makeJoin(contentType: .quickTimeMovie, fileName: "IMG_4022.MOV")
        let original = try givePhotographItsOriginal(join, byteCount: 30_000_000, pixelWidth: 3_840, pixelHeight: 2_160)
        _ = try PersistedDraftFyleJoinVariant(draftFyleJoin: join, format: .low, fyle: try makeFyle(named: "low"), fileName: "IMG_4022.mp4", contentType: .mpeg4Movie, byteCount: 1_000_000, pixelWidth: 640, pixelHeight: 480)

        join.setSelectedFormat(.low)
        join.setSelectedFormat(.hi)

        XCTAssertEqual(join.fyle?.objectID, original.objectID)
        XCTAssertEqual(join.variantSent(whenSelectedFormatIs: .hi)?.format, .max)

    }


    /// A join with no variants has nothing to fall back to and is sent as it is.
    func testAJoinWithNoSizesIsNotMovedByAChoice() throws {

        let join = try makeJoin(contentType: .heic, fileName: "IMG_4021.HEIC")
        let attached = try XCTUnwrap(join.fyle)

        join.setSelectedFormat(.low)

        XCTAssertEqual(join.fyle?.objectID, attached.objectID)
        XCTAssertNil(join.variantSent(whenSelectedFormatIs: .low))

    }


    /// A join with no variants at all — anything that is not a photograph, and a photograph attached by a build of Olvid from before
    /// sizes existed — answers with the file it has. That fallback is what lets such a draft go on sending its attachment unchanged.
    func testAJoinWithNoSizesStillKnowsItsOriginal() throws {
        let join = try makeJoin(contentType: .pdf)
        XCTAssertNotNil(join.originalFyle)
        XCTAssertEqual(join.originalFyle?.objectID, join.fyle?.objectID)
    }


    // MARK: - Deletion

    /// Removing an attachment must take its alternative sizes with it, or they are left with nothing pointing at them and nothing to
    /// find them by.
    ///
    /// The deletion rule is asserted on the model, not on the objects: deleting an object that was never saved un-inserts it without
    /// propagating anything, so `isDeleted` stays false on every row of this unsaved graph. What is observable is asserted too: after the
    /// join goes, no size still claims to belong to it.
    func testRemovingTheAttachmentRemovesItsSizes() throws {

        let model = try XCTUnwrap(context.persistentStoreCoordinator?.managedObjectModel)
        let variantEntity = try XCTUnwrap(model.entitiesByName[PersistedDraftFyleJoinVariant.entityName])

        let relationshipsIntoAVariant = model.entities
            .flatMap { entity in entity.relationshipsByName.map { (owner: entity.name ?? "?", name: $0.key, relationship: $0.value) } }
            .filter { $0.relationship.destinationEntity == variantEntity }

        XCTAssertFalse(relationshipsIntoAVariant.isEmpty)

        for relationship in relationshipsIntoAVariant {
            XCTAssertEqual(
                relationship.relationship.deleteRule,
                .cascadeDeleteRule,
                """
                \(relationship.owner).\(relationship.name) does not cascade, so a size could outlive what owns it — an orphan row \
                naming a file, with nothing left to find either by.
                """)
        }

        let join = try makeJoin(contentType: .heic)
        try givePhotographItsOriginal(join)
        _ = try PersistedDraftFyleJoinVariant(draftFyleJoin: join, format: .med, fyle: try makeFyle(named: "hd"), fileName: "a.jpeg", contentType: .jpeg, byteCount: 1, pixelWidth: 1, pixelHeight: 1)

        let variants = Array(join.variants)
        XCTAssertEqual(variants.count, 2)

        context.delete(join)
        context.processPendingChanges()

        for variant in variants {
            XCTAssertNil(variant.draftFyleJoin, "A size must not go on naming an attachment that has been removed")
        }

    }


    // MARK: - Fixtures

    // MARK: - What a draft answers about its own attachments

    /// **The exact chain the exporting pass reads**, asserted in one place: a draft, the joins it holds, which of them it calls videos,
    /// and which sizes each is going to be given. Written while chasing a composition bar that appeared to do nothing when the size was
    /// changed — a failure here accuses the model, a pass here moves the search into the actor and the wiring above it.
    func testADraftSeparatesItsVideosFromItsPhotographsAndAsksForTheRightSizes() throws {

        let draft = try makeDraft()
        let photograph = try makeJoin(contentType: .jpeg, fileName: "IMG_4021.jpeg")
        let clip = try makeJoin(contentType: .quickTimeMovie, fileName: "IMG_4022.MOV")
        photograph.setValue(draft, forKey: "draft")
        clip.setValue(draft, forKey: "draft")

        XCTAssertEqual(draft.photoJoins.count, 1)
        XCTAssertEqual(draft.videoJoins.count, 1)
        XCTAssertTrue(draft.hasAtLeastOneMediaWithAFormatChoice)

        draft.setSelectedMediaFormat(.low)
        XCTAssertEqual(draft.selectedMediaFormat, .low)

        // The photograph wants all four; the clip wants `max` and the one that was chosen, and nothing else.
        XCTAssertEqual(Set(draft.photoJoins[0].photoFormatsWithoutAFile), Set(ObvMediaFormat.allCases))
        XCTAssertEqual(draft.videoJoins[0].videoFormatsWithoutAFile(whenSelectedFormatIs: draft.selectedMediaFormat), [.max, .low])

        // And changing the choice is what makes a size that was not wanted a moment ago become wanted. This is the step the composition
        // bar's menu performs, and the one that must leave the pass with something to do.
        draft.setSelectedMediaFormat(.med)
        XCTAssertEqual(draft.videoJoins[0].videoFormatsWithoutAFile(whenSelectedFormatIs: draft.selectedMediaFormat), [.max, .med])

    }


    /// A draft, inserted directly rather than through `PersistedDraft(within:)`, which would need a whole discussion behind it. Nothing
    /// here is ever saved, so the missing `discussion` relationship costs nothing: every property under test is computed.
    private func makeDraft() throws -> PersistedDraft {
        let draft = try XCTUnwrap(NSEntityDescription.insertNewObject(forEntityName: PersistedDraft.entityName, into: context) as? PersistedDraft)
        draft.setValue(UUID(), forKey: "permanentUUID")
        draft.setValue(false, forKey: "sendRequested")
        draft.setValue(false, forKey: "readOnce")
        return draft
    }


    private func makeJoin(contentType: UTType, fileName: String = "photo.heic") throws -> PersistedDraftFyleJoin {
        let join = try XCTUnwrap(NSEntityDescription.insertNewObject(forEntityName: PersistedDraftFyleJoin.entityName, into: context) as? PersistedDraftFyleJoin)
        join.setValue(fileName, forKey: "fileName")
        join.setValue(contentType.identifier, forKey: "uti")
        join.setValue(0, forKey: "index")
        join.setValue(UUID(), forKey: "permanentUUID")
        join.setValue(try makeFyle(named: "original-\(UUID().uuidString)"), forKey: "fyle")
        return join
    }


    /// Records that `max` is the file the join was created with — what the writing pass does on its first visit to a photograph.
    ///
    /// The original variant takes its name and type from the join, which at this point has never been repointed, so they are still the
    /// photograph's own. Asserted here rather than in a test of its own, every caller depending on it.
    @discardableResult
    private func givePhotographItsOriginal(_ join: PersistedDraftFyleJoin, byteCount: Int64 = 2_400_000, pixelWidth: Int = 4_032, pixelHeight: Int = 3_024) throws -> Fyle {
        let original = try XCTUnwrap(join.fyle)
        try PersistedDraftFyleJoinVariant.createVariantPointingAtTheOriginal(of: join, format: .max, byteCount: byteCount, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        XCTAssertEqual(join.variant(for: .max)?.fileName, join.fileName)
        XCTAssertEqual(join.variant(for: .max)?.fyle?.objectID, original.objectID)
        return original
    }


    private func makeFyle(named seed: String) throws -> Fyle {
        // A distinct sha256 per file, since `Fyle` is content-addressed and two rows sharing one would *be* one row.
        var bytes = Data(seed.utf8)
        bytes.append(Data(repeating: 0, count: max(0, 32 - bytes.count)))
        return try Fyle.getOrCreate(sha256: Data(bytes.prefix(32)), within: context)
    }

}


/// That `Fyle.Predicate.isOrphaned` names **every** relationship into `Fyle`.
///
/// The sweep deletes every `Fyle` the predicate matches, so a relationship missing from it deletes files still in use, with their rows.
/// Read from the model rather than from a list written here, so that a relationship added to `Fyle` later fails this test until named.
final class FyleOrphanPredicateTests: XCTestCase {

    func testEveryRelationshipIntoAFyleIsNamedInTheOrphanPredicate() throws {

        let context = try FetchedResultsControllerSortDescriptorTests.makeInMemoryObvMessengerContext()
        let model = try XCTUnwrap(context.persistentStoreCoordinator?.managedObjectModel)
        let fyle = try XCTUnwrap(model.entitiesByName["Fyle"])

        let relationships = fyle.relationshipsByName.keys.sorted()
        XCTAssertFalse(relationships.isEmpty)

        let predicate = Fyle.Predicate.isOrphaned.predicateFormat

        for relationship in relationships {
            XCTAssertTrue(
                predicate.contains(relationship),
                """
                Fyle.\(relationship) is not named in Fyle.Predicate.isOrphaned, so a Fyle held only by that relationship would be \
                classed as orphaned and deleted — and the rows holding it would cascade away with the file. The predicate is: \(predicate)
                """)
        }

    }

}
