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


protocol DraftVideoVariantsMakerDelegate: AnyObject {

    /// Saves freshly exported clips into the database. In practice the coordinator, which alone owns `coordinatorsQueue`.
    func draftVideoVariantsMaker(_ maker: DraftVideoVariantsMaker, wantsToSave variantsToCreate: [CreateDraftFyleJoinVariantsOperation.VariantToCreate], forDraft draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async

}


/// Exports each video of a draft at the size it will be sent at, so that sending rarely has to wait.
///
/// Shaped like ``DraftPhotoVariantsMaker``, for the same reasons. The difference is what it makes: an export takes tens of seconds, so a
/// clip only gets ``ObvMediaFormat/max``, which points at the original, and the size currently chosen. A size exported earlier is kept,
/// so going back to it is instant.
///
/// The export starts when the clip is attached, so that it overlaps the typing. Sending waits for it, through
/// ``finishPendingWork(forDraft:)``.
///
/// - **Idempotent** and **one pass per draft at a time**, like its sibling.
/// - **A failed export is not retried until the next launch**: it would fail again, and this is asked on every attachment and every
///   change of size.
/// - **Nothing is left on disk**: a file written but not recorded is trashed by the operation, the only one that knows its path.
actor DraftVideoVariantsMaker {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "DraftVideoVariantsMaker")

    private weak var delegate: DraftVideoVariantsMakerDelegate?

    /// The pass running for each draft, if any, and which pass it is.
    ///
    /// Numbered because a cancelled pass unwinds after its replacement has started. Clearing the entry without checking whose it is would
    /// leave the new pass untracked: ``finishPendingWork(forDraft:)`` would not wait for it, so a clip could be sent at the wrong size, and
    /// ``ensureVariantsExist(draftObjectID:)`` could start a third pass beside it.
    private var taskForDraft = [TypeSafeManagedObjectID<PersistedDraft>: RunningPass]()

    /// A pass and the number that says which one it is. See ``taskForDraft``.
    private struct RunningPass {
        let number: Int
        let task: Task<Void, Never>
    }

    /// Numbers the passes, so that one unwinding after it was cancelled can tell whether the entry on record is still its own.
    ///
    /// Not ``generationCounter``, which numbers *exports* so that a progress report can be told from a later export's. Two different questions
    /// about two different things, deliberately not sharing a counter.
    private var passCounter = 0

    /// The drafts somebody has asked about and whose pass has not started, or has started and may not have seen everything.
    private var draftsNeedingAPass = Set<TypeSafeManagedObjectID<PersistedDraft>>()

    /// The exports that have already failed once during this run of the app, and are not to be attempted again.
    ///
    /// Held for the life of the process and no longer: an export can fail for a reason that *is* temporary — the device out of space,
    /// the encoder busy with something else — so refusing for ever would be wrong, where refusing until the next launch costs the reader
    /// nothing they will notice.
    private var exportsThatFailed = Set<ExportThatFailed>()

    private struct ExportThatFailed: Hashable {
        let joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>
        let format: ObvMediaFormat
    }

    /// Numbers each export, so that a progress report can be told apart from a *later* export's.
    private var generationCounter = 0

    /// Drops progress reports older than the latest one about the same attachment. Reports reach this actor out of order, each through a
    /// `Task` of its own, and a cancelled pass reports after the pass that replaced it has started.
    private var reportFilter = ExportProgressReportFilter<TypeSafeManagedObjectID<PersistedDraftFyleJoin>>()

    /// The store the composition bar's tiles read the progress from.
    private let progressStore: DraftVideoExportProgressStore

    /// The clips each draft's pass is exporting, over which the draft's own fraction is computed.
    ///
    /// **Belongs to the pass that wrote it**, for the reason ``taskForDraft`` gives: a cancelled pass unwinds after the pass that replaced it
    /// has started, and must neither mark clips of the new pass as finished nor clear its entry.
    private var exportsOfTheDraft = [TypeSafeManagedObjectID<PersistedDraft>: ExportsOfADraft]()

    private struct ExportsOfADraft {
        let pass: Int
        let joins: [TypeSafeManagedObjectID<PersistedDraftFyleJoin>]
        var finished = Set<TypeSafeManagedObjectID<PersistedDraftFyleJoin>>()
        /// The last fraction reported for each clip. The nil that ends an export is not kept: the clip counts as finished once its pass
        /// says so, and counting it as 0 in between would move the bar backwards.
        var fractionForJoin = [TypeSafeManagedObjectID<PersistedDraftFyleJoin>: Double]()

        /// Each finished clip counts 1, the others the fraction reported for them, and every clip weighs the same. Weighting them by the
        /// estimated weight of their export was considered: the weight does not predict the time, a clip decoded from 4K taking longer
        /// than a heavier one decoded from 1080p.
        var fractionCompleted: Double {
            guard !joins.isEmpty else { return 1 }
            let completed = joins.reduce(0.0) { sum, join in
                sum + (finished.contains(join) ? 1 : min(max(fractionForJoin[join] ?? 0, 0), 1))
            }
            return completed / Double(joins.count)
        }
    }

    init(progressStore: DraftVideoExportProgressStore) {
        self.progressStore = progressStore
    }

    func setDelegate(to delegate: DraftVideoVariantsMakerDelegate) {
        self.delegate = delegate
    }


    /// Exports whatever this draft's videos are missing at the size currently chosen, in the background. Returns immediately.
    func ensureVariantsExist(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {

        draftsNeedingAPass.insert(draftObjectID)

        guard taskForDraft[draftObjectID] == nil else {
            // A pass is already running and will take the request above before it finishes.
            Self.logger.notice("🎬 A pass was asked for, and one is already running for this draft; it will take the request")
            return
        }

        passCounter += 1
        let thisPass = passCounter
        Self.logger.notice("🎬 A pass was asked for, and is being started — pass \(thisPass, privacy: .public)")

        taskForDraft[draftObjectID] = .init(number: thisPass, task: Task { [weak self] in
            await self?.exportEverySizeStillMissing(draftObjectID: draftObjectID, pass: thisPass)
        })

    }


    /// Stops the pass running for this draft, if any. The export in flight is abandoned and its file trashed.
    ///
    /// Called when an attachment is removed and when the reader changes the size — in both cases what is being exported is either gone
    /// or no longer what will be sent, and an export is far too expensive to let run to the end for nothing.
    func cancelWork(forDraft draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        draftsNeedingAPass.remove(draftObjectID)
        guard let pass = taskForDraft.removeValue(forKey: draftObjectID) else {
            // Said out loud, because a guard that returns in silence cannot be told apart from a case that never arose.
            Self.logger.notice("🎬 Nothing to cancel for this draft: no pass is running")
            return
        }
        Self.logger.notice("🎬 Cancelling the export still running for a draft — pass \(pass.number, privacy: .public)")
        pass.task.cancel()
    }


    /// Waits until this draft's videos have every size they are going to get.
    ///
    /// **Awaited before a draft is sent.** For a photograph this is nearly always instant; for a clip it can be the better part of a
    /// minute, which is the one place this feature can make the reader wait for something they did not ask for. A size that still does
    /// not exist when this returns is one whose export failed, and the clip is then sent as it was attached.
    func finishPendingWork(forDraft draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async {
        // A loop rather than a single await, for the reason its sibling gives: the pass clears its own entry before returning, and a
        // request that arrived while it ran starts another.
        while let pass = taskForDraft[draftObjectID] {
            await pass.task.value
        }
    }


    // MARK: - The pass itself

    private func exportEverySizeStillMissing(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, pass: Int) async {

        // **Only if the entry is still this pass's own** — see ``taskForDraft``. A cancelled pass unwinds after its replacement has been
        // recorded, and clearing the entry then would leave the running pass untracked and a clip sent at the wrong size. Said out loud when it
        // declines, so that a pass standing aside can be told apart from one that never had to.
        defer {
            let whoseEntryItIsNow = taskForDraft[draftObjectID]?.number
            if whoseEntryItIsNow == pass {
                taskForDraft[draftObjectID] = nil
            } else if let whoseEntryItIsNow {
                Self.logger.notice("🎬 Pass \(pass, privacy: .public) has unwound and is leaving the entry alone: it belongs to pass \(whoseEntryItIsNow, privacy: .public)")
            } else {
                Self.logger.notice("🎬 Pass \(pass, privacy: .public) has unwound, and no pass is on record for this draft")
            }
        }

        /// The clips this pass reported as waiting to be encoded and has not yet reported as done, with the generation of that report. The
        /// final nil reuses it, so ``reportFilter`` drops that nil if another pass has reported on the clip since.
        ///
        /// **Every exit from this method goes through the one place that clears it**, which is why the loops below break rather than
        /// return. A clip left in here is a ring sitting at 0% over a tile that cannot be tapped, for ever — the cost of getting that
        /// wrong is not a cosmetic one.
        var waitingToBeEncoded = [TypeSafeManagedObjectID<PersistedDraftFyleJoin>: Int]()

        passes: while draftsNeedingAPass.remove(draftObjectID) != nil {

            if Task.isCancelled { break passes }

            let videos: [VideoAwaitingItsSize]
            do {
                videos = try await videosAwaitingTheirSize(draftObjectID: draftObjectID)
            } catch {
                Self.logger.fault("🎬 Could not read which videos of the draft are missing a size: \(error.localizedDescription, privacy: .public)")
                assertionFailure()
                break passes
            }

            // Said unconditionally, and it is the line that distinguishes "there was nothing to do" from "this never ran" — two outcomes
            // that look identical from outside and that several of this feature's failure modes sit between.
            Self.logger.notice("🎬 \(videos.count, privacy: .public) video(s) of this draft are missing a size")

            // **What each clip needs is decided for all of them before any of them is encoded**, and that ordering is the whole of what
            // lets a queued clip say so. Deciding costs an estimate and no encoding at all — measured at 25 ms for the first clip of a
            // process and 1 ms for every one after, against exports of seconds — so asking up front delays the first encode by nothing
            // anybody can see, and buys two things: the sizes that need no file at all are recorded at once rather than trickling in
            // behind unrelated encodes, and a clip that is *not* going to be encoded never draws a ring it would have to take away again.
            var plans = [PlannedWork]()
            for video in videos {
                if Task.isCancelled { break passes }
                plans.append(await planTheWork(for: video))
            }

            let needingNoFileOfTheirOwn = plans.flatMap(\.variantsNeedingNoFileOfTheirOwn)
            if !needingNoFileOfTheirOwn.isEmpty {
                await delegate?.draftVideoVariantsMaker(self, wantsToSave: needingNoFileOfTheirOwn, forDraft: draftObjectID)
            }

            let plansWithAnEncodeToDo = plans.filter { !$0.formatsToExport.isEmpty }

            // **Every clip that is going to be encoded says so now, before the first one starts.** Without this, a draft of three clips
            // shows one ring and two tiles that look finished, and the reader may tap or send against a clip whose export has not begun.
            // Reported at zero rather than as a state of its own: waiting and having just started are the same thing to somebody looking
            // at the bar, and giving them one number rather than two things to distinguish is what keeps the tile simple.
            for plan in plansWithAnEncodeToDo {
                let generation = nextGeneration()
                waitingToBeEncoded[plan.video.joinObjectID] = generation
                forwardExportProgress(0, forJoin: plan.video.joinObjectID, generation: generation)
            }
            if !plansWithAnEncodeToDo.isEmpty {
                exportsOfTheDraft[draftObjectID] = .init(pass: pass, joins: plansWithAnEncodeToDo.map(\.video.joinObjectID))
                recordTheProgressOfTheDraft(draftObjectID)
            }

            // One clip at a time. Exporting three at once was only 4–6% faster, measured on a Mac, whose encoder has more capacity than a
            // phone's, and it holds several exports in memory at once. Sending waits for every clip either way.
            for plan in plansWithAnEncodeToDo {

                if Task.isCancelled { break passes }

                let variantsToCreate = await runTheExports(of: plan)

                waitingToBeEncoded.removeValue(forKey: plan.video.joinObjectID)

                if exportsOfTheDraft[draftObjectID]?.pass == pass {
                    exportsOfTheDraft[draftObjectID]?.finished.insert(plan.video.joinObjectID)
                    recordTheProgressOfTheDraft(draftObjectID)
                }

                guard !variantsToCreate.isEmpty else { continue }

                await delegate?.draftVideoVariantsMaker(self, wantsToSave: variantsToCreate, forDraft: draftObjectID)

            }

        }

        // Finished, cancelled or failed alike, nothing is left saying it is waiting to be encoded.
        for (joinObjectID, generation) in waitingToBeEncoded {
            forwardExportProgress(nil, forJoin: joinObjectID, generation: generation)
        }

        if exportsOfTheDraft[draftObjectID]?.pass == pass {
            exportsOfTheDraft.removeValue(forKey: draftObjectID)
            progressStore.record(nil, forDraft: draftObjectID)
        }

    }


    /// What one clip needs, decided before anything is encoded.
    private struct PlannedWork {
        let video: VideoAwaitingItsSize
        /// The sizes that need a file of their own, in the order they are to be made.
        let formatsToExport: [ObvMediaFormat]
        /// The sizes that need no file of their own, ready to be recorded at once.
        let variantsNeedingNoFileOfTheirOwn: [CreateDraftFyleJoinVariantsOperation.VariantToCreate]
        /// The weight of every size known so far, recorded or decided by the plan. `max` is the original.
        let byteCountForFormat: [ObvMediaFormat: Int64]
    }


    /// Decides what each of this clip's missing sizes needs, **without encoding anything**.
    ///
    /// Each size is compared with a ceiling: the weight of the lightest larger size among those that have a row or have been decided,
    /// `max` being the original. A video only ever gets `max` and the size that is chosen, so a larger size that was never exported is
    /// not part of the comparison.
    private func planTheWork(for video: VideoAwaitingItsSize) async -> PlannedWork {

        var formatsToExport = [ObvMediaFormat]()
        var variantsNeedingNoFileOfTheirOwn = [CreateDraftFyleJoinVariantsOperation.VariantToCreate]()
        var byteCountForFormat = video.byteCountOfTheSizesAlreadyRecorded
        byteCountForFormat[.max] = video.byteCount

        if video.pixelSizeCannotBeRead {
            Self.logger.notice("🎬 Could not read the pixel size of a video of the draft, so \(video.formatsStillMissing.map(\.rawValue).joined(separator: ", "), privacy: .public) point at the original")
            return PlannedWork(video: video,
                               formatsToExport: [],
                               variantsNeedingNoFileOfTheirOwn: video.formatsStillMissing.map { Self.variant(for: $0, usingTheFileOf: .max, of: video) },
                               byteCountForFormat: byteCountForFormat)
        }

        for format in video.formatsStillMissing {

            guard !exportsThatFailed.contains(.init(joinObjectID: video.joinObjectID, format: format)) else {
                Self.logger.notice("🎬 \(format.rawValue, privacy: .public) failed earlier in this run of the app and is not being attempted again")
                continue
            }

            // `max` is the clip itself.
            guard format.isATranscode else {
                Self.logger.notice("🎬 \(format.rawValue, privacy: .public) points at the original (\(video.pixelWidth, privacy: .public)×\(video.pixelHeight, privacy: .public), \(video.byteCount, privacy: .public) bytes)")
                variantsNeedingNoFileOfTheirOwn.append(.init(joinObjectID: video.joinObjectID,
                                                             format: format,
                                                             file: .theOriginal(byteCount: video.byteCount,
                                                                                pixelWidth: video.pixelWidth,
                                                                                pixelHeight: video.pixelHeight)))
                continue
            }

            // Any other size uses the file of the size that sets its ceiling when exporting it would not make a lighter file — which for
            // a video is a question about *weight* and not about the frame, a clip inside the frame being able to weigh several times
            // what the export would. See `ObvVideoTranscoder.transcodingWouldReduce(videoAt:to:belowACeilingOf:)`.
            let ceiling = Self.ceiling(for: format, among: byteCountForFormat, of: video)
            guard await ObvVideoTranscoder.transcodingWouldReduce(videoAt: video.originalURL, to: format, belowACeilingOf: ceiling.byteCount) else {
                Self.logger.notice("🎬 \(format.rawValue, privacy: .public) would not be lighter than \(ceiling.format.rawValue, privacy: .public) at \(ceiling.byteCount, privacy: .public) bytes, so it uses the file of \(ceiling.format.rawValue, privacy: .public)")
                variantsNeedingNoFileOfTheirOwn.append(Self.variant(for: format, usingTheFileOf: ceiling.format, of: video))
                byteCountForFormat[format] = ceiling.byteCount
                continue
            }

            formatsToExport.append(format)

        }

        return PlannedWork(video: video,
                           formatsToExport: formatsToExport,
                           variantsNeedingNoFileOfTheirOwn: variantsNeedingNoFileOfTheirOwn,
                           byteCountForFormat: byteCountForFormat)

    }


    /// The lightest size larger than `format` among `byteCountForFormat`, falling back to `max`, which is the original.
    private static func ceiling(for format: ObvMediaFormat, among byteCountForFormat: [ObvMediaFormat: Int64], of video: VideoAwaitingItsSize) -> (format: ObvMediaFormat, byteCount: Int64) {
        ObvMediaFormat.lightestSize(largerThan: format, among: byteCountForFormat) ?? (format: .max, byteCount: video.byteCount)
    }


    /// Records `format` as using the file of `largerFormat`: the original when that is `max`, and that size's file otherwise.
    private static func variant(for format: ObvMediaFormat, usingTheFileOf largerFormat: ObvMediaFormat, of video: VideoAwaitingItsSize) -> CreateDraftFyleJoinVariantsOperation.VariantToCreate {
        guard largerFormat != .max else {
            return .init(joinObjectID: video.joinObjectID,
                         format: format,
                         file: .theOriginal(byteCount: video.byteCount, pixelWidth: video.pixelWidth, pixelHeight: video.pixelHeight))
        }
        return .init(joinObjectID: video.joinObjectID, format: format, file: .sameFileAs(format: largerFormat))
    }


    /// Encodes each of the sizes this clip was planned to be given, and describes what to record for each.
    private func runTheExports(of plan: PlannedWork) async -> [CreateDraftFyleJoinVariantsOperation.VariantToCreate] {

        let video = plan.video
        var variantsToCreate = [CreateDraftFyleJoinVariantsOperation.VariantToCreate]()
        var byteCountForFormat = plan.byteCountForFormat

        for format in plan.formatsToExport {

            guard !Task.isCancelled else { break }

            let ceiling = Self.ceiling(for: format, among: byteCountForFormat, of: video)

            guard let outcome = await export(video, to: format, onlyIfLighterThan: ceiling.byteCount) else {
                // **An abandoned export is not a failed one**, and telling them apart is what keeps the feature working when the reader
                // changes their mind. Cancelling is how a change of size stops the export of the size that was chosen before — so
                // recording that as a failure would refuse that size for the rest of the session, and a reader who went Low, then Med, then
                // back to Low would be left with a draft whose chosen size is never made.
                if Task.isCancelled { break }
                exportsThatFailed.insert(.init(joinObjectID: video.joinObjectID, format: format))
                // The size is simply not offered, and the clip is sent as it was attached. Not a fault to stop the pass on: the other
                // clips of the draft are still worth exporting.
                continue
            }

            // **The estimate was optimistic and reality was not.** The decision to export is made on an estimate, so a clip can come out
            // no lighter than the ceiling — at which point sending it would mean charging the reader as much data or more for the size
            // they asked in order to spend less. The export has been discarded and the size uses the file that set the ceiling, exactly
            // as if the estimate had said so in the first place.
            let exported: ObvTranscodedFile
            switch outcome {
            case .written(let transcoded):
                exported = transcoded
            case .notLighterThanTheCeiling(let byteCount):
                Self.logger.notice("🎬 \(format.rawValue, privacy: .public) came out at \(byteCount, privacy: .public) bytes, not lighter than \(ceiling.format.rawValue, privacy: .public) at \(ceiling.byteCount, privacy: .public) bytes, so it uses the file of \(ceiling.format.rawValue, privacy: .public)")
                variantsToCreate.append(Self.variant(for: format, usingTheFileOf: ceiling.format, of: video))
                byteCountForFormat[format] = ceiling.byteCount
                continue
            }

            Self.logger.notice("🎬 \(format.rawValue, privacy: .public) exported: \(exported.pixelWidth, privacy: .public)×\(exported.pixelHeight, privacy: .public), \(exported.byteCount, privacy: .public) bytes, from \(video.pixelWidth, privacy: .public)×\(video.pixelHeight, privacy: .public), \(video.byteCount, privacy: .public) bytes")

            variantsToCreate.append(.init(joinObjectID: video.joinObjectID, format: format, file: .transcoded(file: exported)))
            byteCountForFormat[format] = exported.byteCount

        }

        return variantsToCreate

    }


    /// Runs one export under `ceiling`, reporting how far it has got, and answers nil if it did not finish.
    ///
    /// The progress is reported from whatever thread the poller happens to be on and is forwarded to the store through a task of its
    /// own, so that a slow consumer cannot hold up the export. It is cleared on the way out **whatever happened** — that is what makes
    /// "there is nothing being exported for this attachment" a single thing for the composition bar to test, rather than something it
    /// has to infer from a number that stopped changing.
    private func export(_ video: VideoAwaitingItsSize, to format: ObvMediaFormat, onlyIfLighterThan ceiling: Int64) async -> ObvTranscodingUnderACeiling? {

        let joinObjectID = video.joinObjectID
        let originalURL = video.originalURL
        let fileName = video.fileName
        let directory = ObvUICoreDataConstants.ContainerURL.forTempFiles.url

        let generation = nextGeneration()

        let reportProgress: @Sendable (Double?) -> Void = { [weak self] fractionCompleted in
            Task { [weak self] in
                guard let self else { return }
                await self.forwardExportProgress(fractionCompleted, forJoin: joinObjectID, generation: generation)
            }
        }

        reportProgress(0)
        defer { reportProgress(nil) }

        // Detached, at `.utility`: this is by a wide margin the most expensive thing the app ever does while a discussion is on screen,
        // and it has no business on the cooperative pool's higher priorities.
        let exportTask = Task.detached(priority: .utility) {
            try await ObvVideoTranscoder.transcode(videoAt: originalURL,
                                                   named: fileName,
                                                   to: format,
                                                   inDirectory: directory,
                                                   onlyIfLighterThan: ceiling,
                                                   onProgress: { reportProgress($0) })
        }

        do {
            // **A detached task does not inherit its parent's cancellation**, which is the whole reason this is written out rather than
            // being a plain `await task.value`. Detaching is deliberate — the priority is what is wanted — and the cost of it is that
            // cancelling the pass would otherwise leave an export of tens of seconds running to the end for a size nobody is going to
            // send. The handler is what carries the cancellation across, and `ObvVideoTranscoder` turns it into a `cancelExport()`.
            return try await withTaskCancellationHandler {
                try await exportTask.value
            } onCancel: {
                exportTask.cancel()
            }
        } catch ObvVideoTranscoder.ObvError.exportWasCancelled {
            // Already logged, at `notice`, by the transcoder.
            return nil
        } catch {
            Self.logger.error("🎬 Could not export \(format.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

    }


    /// The next number identifying one stretch of reporting about a clip. See ``reportFilter``.
    private func nextGeneration() -> Int {
        generationCounter += 1
        return generationCounter
    }


    /// Writes the progress to the store, unless ``reportFilter`` drops it.
    private func forwardExportProgress(_ fractionCompleted: Double?, forJoin joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, generation: Int) {
        guard reportFilter.accepts(fractionCompleted, for: joinObjectID, generation: generation) else { return }
        progressStore.record(fractionCompleted, forJoin: joinObjectID)
        guard let fractionCompleted,
              let draftObjectID = exportsOfTheDraft.first(where: { $0.value.joins.contains(joinObjectID) })?.key
        else { return }
        exportsOfTheDraft[draftObjectID]?.fractionForJoin[joinObjectID] = fractionCompleted
        recordTheProgressOfTheDraft(draftObjectID)
    }


    private func recordTheProgressOfTheDraft(_ draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        guard let exports = exportsOfTheDraft[draftObjectID] else { return }
        progressStore.record(exports.fractionCompleted, forDraft: draftObjectID)
    }


    // MARK: - Reading what is missing

    /// One video of a draft, and the sizes it is going to be given.
    private struct VideoAwaitingItsSize: Sendable {

        let joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>
        /// The clip exactly as it was attached — what every size is made from.
        let originalURL: URL
        let fileName: String
        let byteCount: Int64
        let pixelWidth: Int
        /// 0, with `pixelWidth`, when the pixel size cannot be read.
        let pixelHeight: Int
        /// AVFoundation cannot read the clip's pixel size, so it cannot be exported either. Every size then points at the original.
        let pixelSizeCannotBeRead: Bool
        /// ``ObvMediaFormat/max`` first, then the size the draft is set to. At most two.
        let formatsStillMissing: [ObvMediaFormat]
        /// The weight of each size this clip already has a file for: ``PersistedDraftFyleJoin/byteCountForFormat``.
        let byteCountOfTheSizesAlreadyRecorded: [ObvMediaFormat: Int64]

    }


    /// Everything about a video of the draft that the database can answer.
    ///
    /// **Neither its pixel size nor the URL to read it at are among them**, and for two different reasons — see
    /// ``videosAwaitingTheirSize(draftObjectID:)``.
    private struct VideoAsTheDatabaseKnowsIt: Sendable {
        let joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>
        let fileName: String
        let byteCount: Int64
        let formatsStillMissing: [ObvMediaFormat]
        let byteCountOfTheSizesAlreadyRecorded: [ObvMediaFormat: Int64]
    }


    private func videosAwaitingTheirSize(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws -> [VideoAwaitingItsSize] {

        let context = ObvStack.shared.newBackgroundContext()

        let videos: [VideoAsTheDatabaseKnowsIt] = try await context.perform {

            guard let draft = try PersistedDraft.get(objectID: draftObjectID, within: context) else { return [] }

            let selectedFormat = draft.selectedMediaFormat

            // **The line that separates every theory about this from every other.** "Nothing to do", "nothing was recognised as a
            // video" and "the draft has gone" are three different faults that all look like the composition bar doing nothing, and only
            // the UTIs tell them apart — eligibility being decided by `ObvMediaFormat.videoTypesASizeMayBeChosenFor` on a type that is
            // whatever the picker happened to hand over.
            let everyJoin = draft.fyleJoins.map(\.uti).joined(separator: ", ")
            Self.logger.notice("🎬 The draft holds \(draft.fyleJoins.count, privacy: .public) attachment(s) [\(everyJoin, privacy: .public)], of which \(draft.videoJoins.count, privacy: .public) are recognised as videos; the size chosen is \(selectedFormat.rawValue, privacy: .public)")

            // **The row's order, which is the reverse of the order they were attached in.** `videoJoins` is sorted by `index` ascending —
            // oldest first — while the composition bar lists its attachments `reversed()`, so the newest sits leftmost. Exporting in the
            // database's order therefore started with the tile at the far *right* of the row, which reads as the app picking one at
            // random. The exports are serial, so which one goes first is the whole of what the reader sees for the first minute.
            //
            // Reversed here rather than in `videoJoins`, which several other things read and none of them for its order: making that
            // property disagree with its photographic twin, invisibly, to move a ring by three tiles is not a trade worth making.
            return draft.videoJoins.reversed().compactMap { join -> VideoAsTheDatabaseKnowsIt? in

                let formatsStillMissing = join.videoFormatsWithoutAFile(whenSelectedFormatIs: selectedFormat)
                guard !formatsStillMissing.isEmpty else {
                    Self.logger.notice("🎬 A video of the draft already has every size it is going to be given")
                    return nil
                }
                Self.logger.notice("🎬 A video of the draft is missing \(formatsStillMissing.map(\.rawValue).joined(separator: ", "), privacy: .public)")

                guard let originalFyle = join.originalFyle else { return nil }

                // The one measurement of the original everything else is decided from, and its absence is how a clip whose file has gone
                // is left alone rather than fed to an exporter.
                guard let byteCount = originalFyle.getFileSize() else {
                    Self.logger.error("🎬 A video of the draft has no file on disk, so no size can be made from it")
                    return nil
                }

                return VideoAsTheDatabaseKnowsIt(joinObjectID: join.typedObjectID,
                                                 fileName: join.variant(for: .max)?.fileName ?? join.fileName,
                                                 byteCount: byteCount,
                                                 formatsStillMissing: formatsStillMissing,
                                                 byteCountOfTheSizesAlreadyRecorded: join.byteCountForFormat)

            }

        }

        // Two things are done outside `context.perform`:
        // - The URL is a hardlink, because a `Fyle` is named by its sha256 with no extension, and AVFoundation refuses a file without
        //   one, without an error. The hardlink carries the attached file's name, such as `IMG_4022.MOV`.
        // - The pixel size, because reading a clip's means loading its tracks, which is asynchronous and would hold the context's queue.
        var result = [VideoAwaitingItsSize]()
        for video in videos {

            guard let urlOfTheAttachedFile = await Self.hardlinkURLOfTheAttachedFile(ofJoin: video.joinObjectID, within: context) else {
                Self.logger.error("🎬 Could not get a hardlink to a video of the draft, so no size can be made from it")
                continue
            }

            // A clip whose pixel size cannot be read is still recorded, its sizes pointing at the original. Skipping it would leave it
            // without sizes, and the menu preparing for good.
            let pixelSize = await ObvVideoTranscoder.pixelSize(ofVideoAt: urlOfTheAttachedFile)

            result.append(VideoAwaitingItsSize(joinObjectID: video.joinObjectID,
                                               originalURL: urlOfTheAttachedFile,
                                               fileName: video.fileName,
                                               byteCount: video.byteCount,
                                               pixelWidth: pixelSize?.width ?? 0,
                                               pixelHeight: pixelSize?.height ?? 0,
                                               pixelSizeCannotBeRead: pixelSize == nil,
                                               formatsStillMissing: video.formatsStillMissing,
                                               byteCountOfTheSizesAlreadyRecorded: video.byteCountOfTheSizesAlreadyRecorded))
        }

        return result

    }


    /// A URL AVFoundation can actually open for this attachment, naming the file **as it was attached**.
    ///
    /// `.asAttached` and not `.asItWillBeSent`: every size is made from the clip the reader added, and the file that will be sent is
    /// whichever size is currently chosen — which, halfway through a pass, is the one being made.
    ///
    /// Also used by ``DraftVideoFactsStore``, which reads the same clip for the size menu's estimates.
    static func hardlinkURLOfTheAttachedFile(ofJoin joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, within context: NSManagedObjectContext) async -> URL? {

        let fyleElement: FyleElement? = await context.perform {
            PersistedDraftFyleJoin.get(objectID: joinObjectID, within: context)?.fyleElement
        }

        guard let fyleElement else { return nil }

        let hardlink: HardLinkToFyle
        do {
            hardlink = try await withCheckedThrowingContinuation { continuation in
                HardLinksToFylesNotifications.requestHardLinkToFyle(fyleElement: fyleElement) { result in
                    switch result {
                    case .success(let hardlink):
                        continuation.resume(returning: hardlink)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }.postOnDispatchQueue()
            }
        } catch {
            Self.logger.error("🎬 Could not obtain a hardlink for a video of the draft: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        return hardlink.hardlinkURL

    }

}
