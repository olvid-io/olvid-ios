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
import ObvSettings
import ObvUICoreData
import OlvidUtils


protocol DraftPhotoVariantsMakerDelegate: AnyObject {

    /// Saves freshly written photos into the database. In practice the coordinator, which alone owns `coordinatorsQueue`.
    func draftPhotoVariantsMaker(_ maker: DraftPhotoVariantsMaker, wantsToSave variantsToCreate: [CreateDraftFyleJoinVariantsOperation.VariantToCreate], forDraft draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async

}


/// Writes each photo of a draft at every size it may be sent at, so that switching sizes is instant and the menu can show each weight.
///
/// An actor rather than an operation: `coordinatorsQueue` is serial, and encoding there would hold up everything else done to drafts.
/// Only the short database write goes back to it, through `CreateDraftFyleJoinVariantsOperation`.
///
/// - **Idempotent**: it asks the database what is missing first, so it can be called as often as needed. That is how drafts from older
///   builds are caught up at launch.
/// - **One pass per draft at a time**: a request arriving during a pass is taken by that pass rather than lost.
/// - **Nothing is left on disk**: a file written but not recorded is trashed by the operation, the only one that knows its path.
actor DraftPhotoVariantsMaker {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "DraftPhotoVariantsMaker")

    private weak var delegate: DraftPhotoVariantsMakerDelegate?

    /// The pass running for each draft, if any, and which pass it is.
    ///
    /// Numbered because a cancelled pass unwinds after its replacement has started. Clearing the entry without checking whose it is would
    /// leave the new pass untracked: ``finishPendingWork(forDraft:)`` would not wait for it, and ``ensureVariantsExist(draftObjectID:)``
    /// could start a third beside it.
    private var taskForDraft = [TypeSafeManagedObjectID<PersistedDraft>: RunningPass]()

    /// A pass and the number that says which one it is. See ``taskForDraft``.
    private struct RunningPass {
        let number: Int
        let task: Task<Void, Never>
    }

    /// Numbers the passes, so that one unwinding after it was cancelled can tell whether the entry on record is still its own.
    private var passCounter = 0

    /// The drafts somebody has asked about and whose pass has not started, or has started and may not have seen everything.
    private var draftsNeedingAPass = Set<TypeSafeManagedObjectID<PersistedDraft>>()

    func setDelegate(to delegate: DraftPhotoVariantsMakerDelegate) {
        self.delegate = delegate
    }


    /// Makes whatever sizes this draft's photos are missing, in the background. Returns immediately.
    func ensureVariantsExist(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {

        draftsNeedingAPass.insert(draftObjectID)

        guard taskForDraft[draftObjectID] == nil else {
            // A pass is already running and will take the request above before it finishes.
            return
        }

        passCounter += 1
        let thisPass = passCounter
        taskForDraft[draftObjectID] = .init(number: thisPass, task: Task { [weak self] in
            await self?.makeEverySizeStillMissing(draftObjectID: draftObjectID, pass: thisPass)
        })

    }


    /// Stops the pass running for this draft, if any. The photo being written when this is called is abandoned and its file trashed.
    ///
    /// Called when the draft is emptied — the attachments a pass was about to write are gone, and the encoding left to do is entirely
    /// wasted work on a device the reader is watching.
    func cancelWork(forDraft draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        draftsNeedingAPass.remove(draftObjectID)
        guard let pass = taskForDraft.removeValue(forKey: draftObjectID) else { return }
        Self.logger.info("📷 Cancelling the sizes still being written for a draft")
        pass.task.cancel()
    }


    /// Waits until this draft's photos have every size they are going to get.
    ///
    /// **Awaited before a draft is sent**, so that a message sent seconds after a photo was attached does not race the encoding and go
    /// out at whatever size happened to be ready. A size that still does not exist when this returns is one whose encoding failed; the
    /// attachment is then sent at the nearest larger size that has a file, and the caller says so out loud.
    func finishPendingWork(forDraft draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async {
        // A loop rather than a single await: the pass clears its own entry before returning, and a request that arrived while it ran
        // starts another. In practice at most one further pass, the composition bar refusing edition while a send is in flight.
        while let pass = taskForDraft[draftObjectID] {
            await pass.task.value
        }
    }


    // MARK: - The pass itself

    private func makeEverySizeStillMissing(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, pass: Int) async {

        // **Only if the entry is still this pass's own** — see ``taskForDraft``. A pass that was cancelled unwinds after its replacement has
        // been recorded, and clearing the entry then would leave the running pass untracked.
        defer {
            if taskForDraft[draftObjectID]?.number == pass {
                taskForDraft[draftObjectID] = nil
            }
        }

        while draftsNeedingAPass.remove(draftObjectID) != nil {

            guard !Task.isCancelled else { return }

            let photos: [PhotoAwaitingItsSizes]
            do {
                photos = try await photosAwaitingTheirSizes(draftObjectID: draftObjectID)
            } catch {
                Self.logger.fault("📷 Could not read which photos of the draft are missing a size: \(error.localizedDescription, privacy: .public)")
                assertionFailure()
                return
            }

            // Said unconditionally, and it is the line that distinguishes "there was nothing to do" from "this never ran" — two
            // outcomes that look identical from outside and that several of this feature's failure modes sit between.
            Self.logger.info("📷 \(photos.count, privacy: .public) photo(s) of this draft are missing at least one size")

            for photo in photos {

                guard !Task.isCancelled else { return }

                let variantsToCreate = await writeEverySizeOf(photo)

                guard !variantsToCreate.isEmpty else { continue }

                await delegate?.draftPhotoVariantsMaker(self, wantsToSave: variantsToCreate, forDraft: draftObjectID)

            }

        }

    }


    /// Writes each of the sizes this photo still lacks, and describes what to record for each.
    ///
    /// Sizes are written one at a time on purpose. ImageIO decodes at the target size rather than at the source's, so one encode costs
    /// the output and not the input — but three at once costs three outputs at once, and this runs beside a discussion the reader is
    /// looking at. There is also nothing to gain: the menu's rows settle from the top down either way.
    private func writeEverySizeOf(_ photo: PhotoAwaitingItsSizes) async -> [CreateDraftFyleJoinVariantsOperation.VariantToCreate] {

        var variantsToCreate = [CreateDraftFyleJoinVariantsOperation.VariantToCreate]()

        // The weight of every size decided so far, recorded or from this pass. Each size is encoded under the weight of the lightest
        // larger one, and sizes are decided largest first, so a smaller size never weighs more than a larger one. `max` is the original.
        var byteCountForFormat = photo.byteCountOfTheSizesAlreadyRecorded
        byteCountForFormat[.max] = photo.byteCount

        switch photo.everySizeIsTheOriginalBecause {
        case .aJPEGWouldLoseSomething:
            Self.logger.notice("📷 A photo of the draft has several frames or an alpha channel, so every size points at the original")
        case .itsPixelSizeCannotBeRead:
            Self.logger.notice("📷 Could not read the pixel size of a photo of the draft, so every size points at the original")
        case nil:
            break
        }

        for format in photo.formatsStillMissing {

            guard !Task.isCancelled else { break }

            // `max` is the photo itself, and so is any size whose cap this photo is already within, or that cannot be written (see
            // `everySizeIsTheOriginalBecause`). None writes a file: the size points at the original, which is why such a photo shows four
            // identical weights in the menu.
            guard format.isATranscode, photo.everySizeIsTheOriginalBecause == nil, ObvPhotoTranscoder.transcodingWouldReduce(photoAt: photo.originalURL, to: format) else {
                Self.logger.info("📷 \(format.rawValue, privacy: .public) points at the original (\(photo.pixelWidth, privacy: .public)×\(photo.pixelHeight, privacy: .public), \(photo.byteCount, privacy: .public) bytes)")
                variantsToCreate.append(.init(joinObjectID: photo.joinObjectID,
                                              format: format,
                                              file: .theOriginal(byteCount: photo.byteCount,
                                                                 pixelWidth: photo.pixelWidth,
                                                                 pixelHeight: photo.pixelHeight)))
                byteCountForFormat[format] = photo.byteCount
                continue
            }

            let ceiling = ObvMediaFormat.lightestSize(largerThan: format, among: byteCountForFormat) ?? (format: .max, byteCount: photo.byteCount)

            let originalURL = photo.originalURL
            let fileName = photo.fileName
            let directory = ObvUICoreDataConstants.ContainerURL.forTempFiles.url

            // Detached, at `.utility`: this is the only genuinely expensive thing the app does while a discussion is on screen, and it
            // has no business on the cooperative pool's higher priorities.
            let outcome: ObvPhotoTranscoder.TranscodingUnderACeiling?
            outcome = await Task.detached(priority: .utility) {
                do {
                    return try ObvPhotoTranscoder.transcode(photoAt: originalURL, named: fileName, to: format, inDirectory: directory, onlyIfLighterThan: ceiling.byteCount)
                } catch {
                    Self.logger.error("📷 Could not write \(format.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }.value

            /// Records the size as using the file of the lightest larger size, which is what would be sent without it.
            func useTheFileOfTheCeiling() {
                if ceiling.format == .max {
                    variantsToCreate.append(.init(joinObjectID: photo.joinObjectID,
                                                  format: format,
                                                  file: .theOriginal(byteCount: photo.byteCount,
                                                                     pixelWidth: photo.pixelWidth,
                                                                     pixelHeight: photo.pixelHeight)))
                } else {
                    variantsToCreate.append(.init(joinObjectID: photo.joinObjectID, format: format, file: .sameFileAs(format: ceiling.format)))
                }
                byteCountForFormat[format] = ceiling.byteCount
            }

            switch outcome {

            case nil:
                // Recorded rather than left missing: a size missing for one photo leaves its row of the menu without a weight for as long
                // as the draft exists, and the encode would be tried again on every pass.
                Self.logger.notice("📷 \(format.rawValue, privacy: .public) could not be written, so it uses the file of \(ceiling.format.rawValue, privacy: .public)")
                useTheFileOfTheCeiling()

            case .written(let transcoded):
                Self.logger.info("📷 \(format.rawValue, privacy: .public) written: \(transcoded.pixelWidth, privacy: .public)×\(transcoded.pixelHeight, privacy: .public), \(transcoded.byteCount, privacy: .public) bytes, from \(photo.pixelWidth, privacy: .public)×\(photo.pixelHeight, privacy: .public), \(photo.byteCount, privacy: .public) bytes")
                variantsToCreate.append(.init(joinObjectID: photo.joinObjectID, format: format, file: .transcoded(file: transcoded)))
                byteCountForFormat[format] = transcoded.byteCount

            case .notLighterThanTheCeiling(let byteCount):
                Self.logger.notice("📷 \(format.rawValue, privacy: .public) came out at \(byteCount, privacy: .public) bytes, not lighter than \(ceiling.format.rawValue, privacy: .public) at \(ceiling.byteCount, privacy: .public) bytes, so it uses the file of \(ceiling.format.rawValue, privacy: .public)")
                useTheFileOfTheCeiling()

            }

        }

        return variantsToCreate

    }


    // MARK: - Reading what is missing

    /// One photo of a draft, and the sizes it does not have yet.
    private struct PhotoAwaitingItsSizes: Sendable {

        let joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>
        /// The photo exactly as it was attached — what every size is made from.
        let originalURL: URL
        let fileName: String
        let byteCount: Int64
        let pixelWidth: Int
        /// 0, with `pixelWidth`, when the pixel size cannot be read.
        let pixelHeight: Int
        /// Why no smaller size is written, or nil when they may be. Every size then points at the original.
        let everySizeIsTheOriginalBecause: WhyEverySizeIsTheOriginal?
        /// Largest first, so `max` is recorded before anything that points at it.
        let formatsStillMissing: [ObvMediaFormat]
        /// The weight of each size this photo already has a variant for.
        let byteCountOfTheSizesAlreadyRecorded: [ObvMediaFormat: Int64]

        enum WhyEverySizeIsTheOriginal: Sendable {
            /// Several frames or an alpha channel, which a JPEG would lose.
            case aJPEGWouldLoseSomething
            /// ImageIO cannot read its pixel size, so it cannot be downsized either.
            case itsPixelSizeCannotBeRead
        }

    }


    private func photosAwaitingTheirSizes(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws -> [PhotoAwaitingItsSizes] {

        let context = ObvStack.shared.newBackgroundContext()

        return try await context.perform {

            guard let draft = try PersistedDraft.get(objectID: draftObjectID, within: context) else { return [] }

            return draft.photoJoins.compactMap { join -> PhotoAwaitingItsSizes? in

                let formatsStillMissing = join.photoFormatsWithoutAFile
                guard !formatsStillMissing.isEmpty else { return nil }

                guard let originalFyle = join.originalFyle else { return nil }
                let originalURL = originalFyle.url

                // The one measurement of the original everything else is decided from. Read once, here, rather than in each of the
                // three encodes — and its absence is how a photo whose file has gone is left alone instead of being fed to ImageIO.
                guard let byteCount = originalFyle.getFileSize() else {
                    Self.logger.error("📷 A photo of the draft has no file on disk, so no size can be made from it")
                    return nil
                }
                // A photo whose pixel size cannot be read is still recorded, every size pointing at the original. Skipping it would leave
                // it without sizes, and the menu preparing for good.
                let pixelSize = ObvPhotoTranscoder.pixelSize(ofPhotoAt: originalURL)
                let everySizeIsTheOriginalBecause: PhotoAwaitingItsSizes.WhyEverySizeIsTheOriginal?
                if pixelSize == nil {
                    everySizeIsTheOriginalBecause = .itsPixelSizeCannotBeRead
                } else if !ObvPhotoTranscoder.isOneOpaqueImage(photoAt: originalURL) {
                    everySizeIsTheOriginalBecause = .aJPEGWouldLoseSomething
                } else {
                    everySizeIsTheOriginalBecause = nil
                }

                return PhotoAwaitingItsSizes(joinObjectID: join.typedObjectID,
                                             originalURL: originalURL,
                                             fileName: join.variant(for: .max)?.fileName ?? join.fileName,
                                             byteCount: byteCount,
                                             pixelWidth: pixelSize?.width ?? 0,
                                             pixelHeight: pixelSize?.height ?? 0,
                                             everySizeIsTheOriginalBecause: everySizeIsTheOriginalBecause,
                                             formatsStillMissing: formatsStillMissing,
                                             byteCountOfTheSizesAlreadyRecorded: join.variants.reduce(into: [:]) { byteCountForFormat, variant in
                                                 guard let format = variant.format else { return }
                                                 byteCountForFormat[format] = variant.byteCount
                                             })

            }

        }

    }

}
