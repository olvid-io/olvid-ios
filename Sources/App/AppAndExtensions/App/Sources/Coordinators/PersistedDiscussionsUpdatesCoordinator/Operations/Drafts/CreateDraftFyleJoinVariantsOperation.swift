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

import Foundation
import CoreData
import OSLog
import ObvAppCoreConstants
import ObvAppTypes
import ObvMediaTranscoding
import ObvUICoreData
import OlvidUtils


/// Records, in the database, sizes of a draft's photos and videos that have already been written to disk.
///
/// It does no encoding: the sizes makers encode away from every context's queue, `coordinatorsQueue` being serial. What is left here is
/// short: get or create the `Fyle`, move the file into the store, insert the rows.
///
/// It ends by re-applying the draft's chosen size, which may have been chosen before its file existed.
final class CreateDraftFyleJoinVariantsOperation: ContextualOperationWithSpecificReasonForCancel<CreateDraftFyleJoinVariantsOperationReasonForCancel>, @unchecked Sendable {

    /// One photo or video of a draft, written at one size, ready to be recorded.
    struct VariantToCreate: Sendable {

        let joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>
        let format: ObvMediaFormat
        let file: File

        enum File: Sendable {
            /// This size needs no file of its own — see `PersistedDraftFyleJoinVariant.createVariantPointingAtTheOriginal(of:format:byteCount:pixelWidth:pixelHeight:)`.
            case theOriginal(byteCount: Int64, pixelWidth: Int, pixelHeight: Int)
            /// This size was written to `file.temporaryURL`, which this operation owns and must either move or trash.
            ///
            /// **One case for both media.** A downscaled photograph and an exported clip differ in everything about how they are made and
            /// in nothing about what has to be done with them, so `ObvTranscodedFile` is what both transcoders hand back and this is the
            /// only place that has to know it.
            case transcoded(file: ObvTranscodedFile)
            /// This size uses the file of `format`, a larger size of the same photo, because encoding it gave a file no lighter than that
            /// one. `format`'s variant must already exist, or come earlier in the same list.
            case sameFileAs(format: ObvMediaFormat)
        }

    }

    enum ObvError: Error {
        case noVariantToShareTheFileOf(format: ObvMediaFormat)
    }

    private let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    private let variantsToCreate: [VariantToCreate]

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: CreateDraftFyleJoinVariantsOperation.self))
    /// `Fyle.moveFileToPermanentURL(from:logTo:)` still takes an `OSLog`. Kept solely to bridge into it.
    private static let osLog = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: CreateDraftFyleJoinVariantsOperation.self))

    /// - Parameter variantsToCreate: expected largest size first, so that ``ObvMediaFormat/max`` is recorded before any size that points
    /// at it. Nothing breaks if it is not — the fallback reads the join — but only on the very first pass is the join still holding the
    /// original.
    init(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, variantsToCreate: [VariantToCreate]) {
        self.draftObjectID = draftObjectID
        self.variantsToCreate = variantsToCreate
        super.init()
    }


    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {

            guard let draft = try PersistedDraft.get(objectID: draftObjectID, within: obvContext.context) else {
                // Not a fault. The draft may have been sent, or the discussion deleted, while the photos were being written — which is
                // precisely the window this operation exists at the end of. The files are trashed below.
                Self.logger.info("The draft is gone, so \(self.variantsToCreate.count) freshly written photo(s) are being trashed")
                trashTheFilesWeWereHandedAndDidNotUse(variantsToCreate)
                return
            }

            for variantToCreate in variantsToCreate {

                guard let join = PersistedDraftFyleJoin.get(objectID: variantToCreate.joinObjectID, within: obvContext.context), !join.isDeleted else {
                    // The reader removed this attachment while its sizes were being written. Ordinary.
                    Self.logger.info("The attachment is gone, so its \(variantToCreate.format.rawValue, privacy: .public) file is being trashed")
                    trashTheFilesWeWereHandedAndDidNotUse([variantToCreate])
                    continue
                }

                guard join.variant(for: variantToCreate.format) == nil else {
                    // Another pass got there first. Expected rather than exceptional: the producer is allowed to run again over a draft
                    // it has already served, which is what makes it safe to call on every opening of a discussion.
                    Self.logger.info("A \(variantToCreate.format.rawValue, privacy: .public) variant already exists, so the one just written is being trashed")
                    trashTheFilesWeWereHandedAndDidNotUse([variantToCreate])
                    continue
                }

                switch variantToCreate.file {

                case .theOriginal(let byteCount, let pixelWidth, let pixelHeight):

                    try PersistedDraftFyleJoinVariant.createVariantPointingAtTheOriginal(of: join,
                                                                                         format: variantToCreate.format,
                                                                                         byteCount: byteCount,
                                                                                         pixelWidth: pixelWidth,
                                                                                         pixelHeight: pixelHeight)

                case .sameFileAs(let format):

                    // Falls back to the original if the larger size has no row, which keeps this size within `max`.
                    guard let variantToShare = join.variant(for: format) ?? join.variant(for: .max) else {
                        throw ObvError.noVariantToShareTheFileOf(format: format)
                    }
                    try PersistedDraftFyleJoinVariant.createVariantPointingAtTheFileOf(variantToShare, format: variantToCreate.format)

                case .transcoded(let transcodedFile):

                    let fyle = try Fyle.getOrCreate(sha256: transcodedFile.sha256, within: obvContext.context)

                    // Asked before the move, as there is no way to tell afterwards. When a variant throws, the context is rolled back and
                    // the rows this operation made disappear, but the files moved into the store remain. A file is ours to trash only if
                    // its row is new and the store did not already hold it: a row that existed before this operation survives the
                    // rollback, and its file must be kept.
                    let theRowIsOurs = fyle.isInserted
                    let theStoreAlreadyHeldTheFile = FileManager.default.fileExists(atPath: fyle.url.path)

                    // Leaves the source where it is when the destination already holds this content, `Fyle` being content-addressed —
                    // two photos whose downscales are byte-identical share one row and one file. The source is then trashed below
                    // rather than left behind.
                    try fyle.moveFileToPermanentURL(from: transcodedFile.temporaryURL, logTo: Self.osLog)
                    try? transcodedFile.temporaryURL.moveToTrash()

                    if theRowIsOurs && !theStoreAlreadyHeldTheFile {
                        filesThisOperationPutIntoTheFyleStore.append(fyle.url)
                    }

                    _ = try PersistedDraftFyleJoinVariant(draftFyleJoin: join,
                                                          format: variantToCreate.format,
                                                          fyle: fyle,
                                                          fileName: transcodedFile.fileName,
                                                          contentType: transcodedFile.contentType,
                                                          byteCount: transcodedFile.byteCount,
                                                          pixelWidth: transcodedFile.pixelWidth,
                                                          pixelHeight: transcodedFile.pixelHeight)

                }

            }

            // A size may have been chosen before its file existed. This is where that is made good, and it is a no-op whenever it is not
            // needed — `setSelectedFormat(_:)` writes nothing it does not have to.
            draft.applySelectedMediaFormatToAllMedia()

        } catch {
            Self.logger.fault("Could not record \(self.variantsToCreate.count) size(s) for a draft's media: \(error)")
            assertionFailure()
            trashTheFilesWeWereHandedAndDidNotUse(variantsToCreate)
            // Also trashes the files already moved into the store, which the line above cannot reach: for a variant handled before the
            // throw, there is nothing left at `temporaryURL`. Otherwise they would stay on disk until the sweep of the `Fyle` directory
            // at the next launch.
            trashTheFilesThisOperationPutIntoTheFyleStore()
            return cancel(withReason: .coreDataError(error: error))
        }

    }


    /// The files this operation moved into the `Fyle` store, for rows that did not exist before it ran.
    ///
    /// Held rather than recomputed because after the rollback there is nothing left to ask: the rows are gone, and a `sha256` no longer
    /// names anything this context knows about. See the `catch`.
    private var filesThisOperationPutIntoTheFyleStore = [URL]()


    /// Undoes what this operation put into the `Fyle` store, the rows that pointed at it having been rolled back.
    private func trashTheFilesThisOperationPutIntoTheFyleStore() {
        for url in filesThisOperationPutIntoTheFyleStore {
            try? url.moveToTrash()
        }
        filesThisOperationPutIntoTheFyleStore.removeAll()
    }


    /// A file this operation was handed and did not move into the `Fyle` store is this operation's to dispose of, and nobody else's:
    /// nothing else knows the path, so leaving it behind is a leak in the shared container that no sweep would ever find.
    private func trashTheFilesWeWereHandedAndDidNotUse(_ variantsToCreate: [VariantToCreate]) {
        for variantToCreate in variantsToCreate {
            guard case .transcoded(let transcodedFile) = variantToCreate.file else { continue }
            try? transcodedFile.temporaryURL.moveToTrash()
        }
    }

}


enum CreateDraftFyleJoinVariantsOperationReasonForCancel: LocalizedErrorWithLogType {

    case contextIsNil
    case coreDataError(error: Error)

    var logType: OSLogType {
        return .fault
    }

    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "The context is not set"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }

}
