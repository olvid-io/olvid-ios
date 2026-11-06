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
import ObvComposition
import CoreData
import OSLog
import ObvUICoreData
import ObvAppTypes
import ObvAppCoreConstants
import ObvMediaTranscoding
import OlvidUtils
import ObvTypes


final class ComposeViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var composeViewDataSourceModelStreamManagerForStreamUUID = [UUID: ComposeViewDataSourceModelStreamManager]()
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ComposeViewAppDataSource")
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
}


extension ComposeViewAppDataSource: ComposeViewDataSource {
    
    @MainActor
    func getInitialComposeViewDataSourceModel(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) -> ComposeViewDataSourceModel? {
        if let persistedDraft = try? PersistedDraft.getPersistedDraft(discussionIdentifier: discussionIdentifier, within: viewContext),
            let model = try? ComposeViewDataSourceModel(persistedDraft: persistedDraft) {
            return model
        } else {
            return nil
        }
        
    }
    
    func getAsyncStreamOfComposeViewDataSourceModel(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ComposeViewDataSourceModel>) {
        let manager = try await ComposeViewDataSourceModelStreamManager(discussionIdentifier: discussionIdentifier, context: backgroundContext)
        composeViewDataSourceModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfComposeViewDataSourceModel(_ view: ComposeView, streamUUID: UUID) {
        guard let manager = composeViewDataSourceModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }


    /// A discussion with no draft yet has no export running, and its stream says so once and ends.
    @MainActor
    func getAsyncStreamOfTheProgressOfTheVideosBeingPrepared(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) -> AsyncStream<Double?> {
        guard let draftObjectID = (try? PersistedDraft.getPersistedDraft(discussionIdentifier: discussionIdentifier, within: viewContext))?.typedObjectID else {
            return AsyncStream { continuation in
                continuation.yield(nil)
                continuation.finish()
            }
        }
        return DraftVideoExportProgressStore.shared.progressUpdates(forDraft: draftObjectID)
            .atMostOneValue(every: 1.0)
    }

    
}

extension ComposeViewAppDataSource {
    
    /// **Three controllers, and the third is not optional.**
    ///
    /// The first two watch the draft and the discussion's local configuration. Neither of them sees a photograph's alternative sizes
    /// being written: a `PersistedDraftFyleJoinVariant` arriving updates a *join*, and a join is not a draft — so without the third
    /// controller nothing would ever tell the size menu that a weight it is waiting for is now known, and its rows would show a
    /// spinner for as long as the discussion stayed open.
    private final class ComposeViewDataSourceModelStreamManager: ObvDataSourceStreamManagerWithThreeFetchedResultsController<ComposeViewDataSourceModel, PersistedDraft, PersistedDiscussionLocalConfiguration, PersistedDraftFyleJoinVariant>, @unchecked Sendable {

        init(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, context: NSManagedObjectContext) async throws {

            let frc = try await PersistedDraft.getFetchedResultsControllerForPersistedDraft(discussionIdentifier: discussionIdentifier, within: context)
            let frcForLocalConfiguration = try await PersistedDiscussionLocalConfiguration.getFetchedResultsController(discussionIdentifier: discussionIdentifier, within: context)

            // Built from the draft itself rather than from the discussion, a variant belonging to a join belonging to a draft. A
            // discussion with no draft yields a controller that matches nothing, which is correct: there are then no photographs.
            let frcForPhotoSizes: NSFetchedResultsController<PersistedDraftFyleJoinVariant> = try await context.perform {
                let draftObjectID = try PersistedDraft.getPersistedDraft(discussionIdentifier: discussionIdentifier, within: context)?.typedObjectID
                return PersistedDraftFyleJoinVariant.getFetchedResultsControllerForAllVariantsOfDraft(withObjectID: draftObjectID, within: context)
            }

            super.init(frc1: frc, frc2: frcForLocalConfiguration, frc3: frcForPhotoSizes)

        }

        override func createModel(fetchedObjects1: [PersistedDraft], fetchedObjects2: [PersistedDiscussionLocalConfiguration], fetchedObjects3: [PersistedDraftFyleJoinVariant]) throws -> ComposeViewDataSourceModel {
            assert(fetchedObjects1.count == 1)
            guard let persistedDraft = fetchedObjects1.first else { assertionFailure(); throw ObvError.couldNotCreateModel }
            readTheVideosTheSizeMenuNeeds(of: persistedDraft)
            // `fetchedObjects3` is not read: its whole purpose is to make this method run again when a size lands, and the model is
            // built from the draft's own relationships, which are then up to date.
            let model = try ComposeViewDataSourceModel(persistedDraft: persistedDraft, persistedDiscussionLocalConfiguration: fetchedObjects2.first)
            return model
        }

        /// Asks for each video that misses a size to be read, so that the size menu can estimate that size. The model is built again
        /// once the video is read.
        ///
        /// Only this stream can build the model again, so the reads are asked for here and not by the initial model.
        private func readTheVideosTheSizeMenuNeeds(of persistedDraft: PersistedDraft) {
            for video in persistedDraft.videoJoins where ObvMediaFormat.allCases.contains(where: { video.variant(for: $0) == nil }) {
                guard let sha256 = video.originalFyle?.sha256 else { continue }
                DraftVideoFactsStore.shared.readIfNeeded(clipWithSha256: sha256, attachedAs: video.typedObjectID) { [weak self] in
                    self?.createAndYieldModelIfNeeded()
                }
            }
        }

        private func createAndYieldModelIfNeeded() {
            let context = frc1.managedObjectContext
            context.perform { [weak self] in
                guard let self else { return }
                guard let fetchedObjects1 = self.frc1.fetchedObjects, let fetchedObjects2 = self.frc2.fetchedObjects, let fetchedObjects3 = self.frc3.fetchedObjects else { return }
                guard let model = try? createModel(fetchedObjects1: fetchedObjects1, fetchedObjects2: fetchedObjects2, fetchedObjects3: fetchedObjects3) else { assertionFailure(); return }
                self.yieldModelIfNeeded(model: model, within: context)
            }
        }

        enum ObvError: Error {
            case couldNotFetchObjects
            case couldNotCreateModel
        }
    }
}

extension ComposeViewDataSourceModel {
    
    init(persistedDraft: PersistedDraft, persistedDiscussionLocalConfiguration: PersistedDiscussionLocalConfiguration? = nil) throws {
        
        let emojiButtonSpecificToDiscussion = persistedDiscussionLocalConfiguration?.defaultEmoji
        
        let contactNameIfOneToOne: String?
        let isOneToOne: Bool
        let contactIdentifier: ObvContactIdentifier?
        
        guard let discussionIdentifier: ObvDiscussionIdentifier = try? persistedDraft.discussion.discussionIdentifier else {
            throw ObvError.couldNotDetermineDiscussionIdentifier
        }
        
        switch try? persistedDraft.discussion.kind {
        case .oneToOne(withContactIdentity: let contact):
            isOneToOne = true
            if let contact {
                contactNameIfOneToOne = contact.shortOriginalName
                try contactIdentifier = contact.obvContactIdentifier
            } else {
                contactNameIfOneToOne = nil
                contactIdentifier = nil
            }
        case .groupV1, .groupV2, .none:
            isOneToOne = false
            contactNameIfOneToOne = nil
            contactIdentifier = nil
        }
        
        let audioAttachment: ComposeAttachmentView.AttachmentIdentifier? = persistedDraft.fyleJoinsNotPreviews
            .compactMap { $0 as? PersistedDraftFyleJoin }
            .filter { $0.isAudioType }
            .map { .persistedDraftFyleJoinObjectID($0.typedObjectID.objectID) }
            .first

        let attachmentsObjectID: [ComposeAttachmentView.AttachmentIdentifier] = persistedDraft.fyleJoinsNotPreviews.reversed()
            .compactMap { $0 as? PersistedDraftFyleJoin }
            .map { .persistedDraftFyleJoinObjectID($0.typedObjectID.objectID) }
            .filter { $0 != audioAttachment }
        
        let linkPreview: ComposeAttachmentView.AttachmentIdentifier? = persistedDraft.fyleJoinsPreviews
            .compactMap { $0 as? PersistedDraftFyleJoin }
            .map { .persistedDraftFyleJoinObjectID($0.typedObjectID.objectID) }
            .first
        
        let replyTo: ObvAppTypes.ObvMessageAppIdentifier?
        if let messageAppIdentifier = try? persistedDraft.replyTo?.messageAppIdentifier {
            replyTo = messageAppIdentifier
        } else {
            replyTo = nil
        }
        
        self.init(discussionIdentifier: discussionIdentifier,
                  isDraftDeleted: persistedDraft.isDeleted,
                  hasSomeExpiration: persistedDraft.hasSomeExpiration,
                  isOneToOne: isOneToOne,
                  attributedText: persistedDraft.attributedBody ?? AttributedString(""),
                  emojiButtonSpecificToDiscussion: emojiButtonSpecificToDiscussion,
                  contactOriginalNameIfOneToOne: contactNameIfOneToOne,
                  contactIdentifier: contactIdentifier,
                  attachments: attachmentsObjectID,
                  linkPreview: linkPreview,
                  audio: audioAttachment,
                  replyTo: replyTo,
                  mediaFormatSelection: Self.mediaFormatSelection(for: persistedDraft))
    }


    /// What the composition bar's size menu shows for this draft, or nil when it holds nothing the choice applies to and there is no menu.
    ///
    /// A size gets a weight only once every attachment of the draft has one at that size: a partial total would change as the rest
    /// arrived. Without a weight, the menu shows the row as being prepared, and it can still be picked.
    ///
    /// A photo has a weight once its file is written, all four sizes being written on attachment. A video is exported only at the size
    /// chosen, so its other sizes get an estimate instead, once the clip has been read.
    private static func mediaFormatSelection(for persistedDraft: PersistedDraft) -> ComposeViewDataSourceModel.MediaFormatSelection? {

        let photos = persistedDraft.photoJoins
        let videos = persistedDraft.videoJoins
        guard !photos.isEmpty || !videos.isEmpty else { return nil }

        var totalByteCountForFormat = [ObvMediaFormat: Int64]()
        var formatsWhoseWeightIsAnEstimate = Set<ObvMediaFormat>()

        formats: for format in ObvMediaFormat.allCases {
            var total: Int64 = 0
            var someWeightIsAnEstimate = false
            for photo in photos {
                guard let variant = photo.variant(for: format) else { continue formats }
                total += variant.byteCount
            }
            for video in videos {
                guard let weight = weight(of: video, ifChosen: format) else { continue formats }
                total += weight.byteCount
                someWeightIsAnEstimate = someWeightIsAnEstimate || weight.isAnEstimate
            }
            totalByteCountForFormat[format] = total
            if someWeightIsAnEstimate {
                formatsWhoseWeightIsAnEstimate.insert(format)
            }
        }

        return .init(selected: persistedDraft.selectedMediaFormat,
                     totalByteCountForFormat: totalByteCountForFormat,
                     formatsWhoseWeightIsAnEstimate: formatsWhoseWeightIsAnEstimate)

    }


    /// What this video would weigh if `format` were chosen now: the weight of its file at that size when it has one, and otherwise an
    /// estimate of what `DraftVideoVariantsMaker` would make. Nil until the clip has its `max` size and has been read.
    private static func weight(of video: PersistedDraftFyleJoin, ifChosen format: ObvMediaFormat) -> (byteCount: Int64, isAnEstimate: Bool)? {

        if let variant = video.variant(for: format) {
            return (byteCount: variant.byteCount, isAnEstimate: false)
        }

        // The ceiling the maker would compare an export with: the lightest larger size that has a file, `max` being the original. It is
        // never a size that is itself estimated, or picking a size could produce a weight other than the one shown.
        let byteCountOfTheSizesWithAFile = video.byteCountForFormat
        guard byteCountOfTheSizesWithAFile[.max] != nil,
              let ceiling = ObvMediaFormat.lightestSize(largerThan: format, among: byteCountOfTheSizesWithAFile) else { return nil }

        guard let sha256 = video.originalFyle?.sha256,
              let whatWasRead = DraftVideoFactsStore.shared.whatWasRead(fromClipWithSha256: sha256) else { return nil }

        let facts: ObvVideoTranscoder.ClipFacts?
        switch whatWasRead {
        case .facts(let factsRead):
            facts = factsRead
        case .nothing:
            facts = nil
        }

        return ObvVideoTranscoder.weightIfChosen(format, ofAClipWith: facts, belowACeilingOf: ceiling.byteCount)

    }
    
    enum ObvError: Error {
        case couldNotDetermineDiscussionIdentifier
    }
    
}
