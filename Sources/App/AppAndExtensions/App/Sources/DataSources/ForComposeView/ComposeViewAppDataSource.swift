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
    
    
}

extension ComposeViewAppDataSource {
    
    private final class ComposeViewDataSourceModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ComposeViewDataSourceModel, PersistedDraft, PersistedDiscussionLocalConfiguration>, @unchecked Sendable {
        
        init(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, context: NSManagedObjectContext) async throws {

            let frc = try await PersistedDraft.getFetchedResultsControllerForPersistedDraft(discussionIdentifier: discussionIdentifier, within: context)
            let frcForLocalConfiguration = try await PersistedDiscussionLocalConfiguration.getFetchedResultsController(discussionIdentifier: discussionIdentifier, within: context)

            super.init(frc1: frc, frc2: frcForLocalConfiguration)

        }
        
        override func createModel(fetchedObjects1: [PersistedDraft], fetchedObjects2: [PersistedDiscussionLocalConfiguration]) throws -> ComposeViewDataSourceModel {
            assert(fetchedObjects1.count == 1)
            guard let persistedDraft = fetchedObjects1.first else { assertionFailure(); throw ObvError.couldNotCreateModel }
            let model = try ComposeViewDataSourceModel(persistedDraft: persistedDraft, persistedDiscussionLocalConfiguration: fetchedObjects2.first)
            return model
        }
        
        private func createAndYieldModelIfNeeded() {
            let context = frc1.managedObjectContext
            context.perform { [weak self] in
                guard let self else { return }
                guard let fetchedObjects1 = self.frc1.fetchedObjects, let fetchedObjects2 = self.frc2.fetchedObjects else { return }
                guard let model = try? createModel(fetchedObjects1: fetchedObjects1, fetchedObjects2: fetchedObjects2) else { assertionFailure(); return }
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
                  replyTo: replyTo)
    }
    
    enum ObvError: Error {
        case couldNotDetermineDiscussionIdentifier
    }
    
}
