/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import os.log
import OlvidUtils
import ObvUICoreData


final class InsertPersistedMessageSystemIntoDiscussionOperation: ContextualOperationWithSpecificReasonForCancel<InsertPersistedMessageSystemIntoDiscussionOperationReasonForCancel> {

    private let persistedMessageSystemCategory: PersistedMessageSystem.Category
    private let persistedDiscussionProviderType: PersistedDiscussionProviderType
    private let optionalContactIdentityObjectID: NSManagedObjectID?
    private let optionalCallLogItemObjectID: TypeSafeManagedObjectID<PersistedCallLogItem>?
    private let messageUploadTimestampFromServer: Date?
    
    enum PersistedDiscussionProviderType {
        case persistedDiscussionObjectID(persistedDiscussionObjectID: NSManagedObjectID)
        case operationProvidingPersistedDiscussion(operationProvidingPersistedDiscussion: OperationProvidingPersistedDiscussion)
    }
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: InsertPersistedMessageSystemIntoDiscussionOperation.self))

    init(persistedMessageSystemCategory: PersistedMessageSystem.Category,
         persistedDiscussionObjectID: NSManagedObjectID,
         optionalContactIdentityObjectID: NSManagedObjectID?,
         optionalCallLogItemObjectID: TypeSafeManagedObjectID<PersistedCallLogItem>?,
         messageUploadTimestampFromServer: Date? = nil) {
        self.persistedMessageSystemCategory = persistedMessageSystemCategory
        self.persistedDiscussionProviderType = .persistedDiscussionObjectID(persistedDiscussionObjectID: persistedDiscussionObjectID)
        self.optionalContactIdentityObjectID = optionalContactIdentityObjectID
        self.optionalCallLogItemObjectID = optionalCallLogItemObjectID
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        super.init()
    }

    
    init(persistedMessageSystemCategory: PersistedMessageSystem.Category,
         operationProvidingPersistedDiscussion: OperationProvidingPersistedDiscussion,
         optionalContactIdentityObjectID: NSManagedObjectID?,
         optionalCallLogItemObjectID: TypeSafeManagedObjectID<PersistedCallLogItem>?,
         messageUploadTimestampFromServer: Date? = nil) {
        self.persistedMessageSystemCategory = persistedMessageSystemCategory
        self.persistedDiscussionProviderType = .operationProvidingPersistedDiscussion(operationProvidingPersistedDiscussion: operationProvidingPersistedDiscussion)
        self.optionalContactIdentityObjectID = optionalContactIdentityObjectID
        self.optionalCallLogItemObjectID = optionalCallLogItemObjectID
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        super.init()
    }

    

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let persistedDiscussionObjectID: NSManagedObjectID
        
        switch persistedDiscussionProviderType {
        case .persistedDiscussionObjectID(persistedDiscussionObjectID: let objectID):
            persistedDiscussionObjectID = objectID
        case .operationProvidingPersistedDiscussion(operationProvidingPersistedDiscussion: let operation):
            assert(operation.isFinished)
            guard let objectID = operation.persistedDiscussionObjectID else {
                return cancel(withReason: .discussionObjectIDWasNotProvided)
            }
            persistedDiscussionObjectID = objectID.objectID
        }
        
        do {
            
            guard let discussion = try PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindPersistedDiscussionInDatabase)
            }
            
            switch persistedMessageSystemCategory {
            case .ownedIdentityIsPartOfGroupV2Admins:
                guard let groupV2Discussion = discussion as? PersistedGroupV2Discussion else {
                    return cancel(withReason: .inappropriatePersistedMessageSystemCategoryForGivenDiscussion(persistedMessageSystemCategory: persistedMessageSystemCategory))
                }
                _ = try? PersistedMessageSystem.insertOwnedIdentityIsPartOfGroupV2AdminsMessage(within: groupV2Discussion)
            case .ownedIdentityIsNoLongerPartOfGroupV2Admins:
                guard let groupV2Discussion = discussion as? PersistedGroupV2Discussion else {
                    return cancel(withReason: .inappropriatePersistedMessageSystemCategoryForGivenDiscussion(persistedMessageSystemCategory: persistedMessageSystemCategory))
                }
                _ = try? PersistedMessageSystem.insertOwnedIdentityIsNoLongerPartOfGroupV2AdminsMessage(within: groupV2Discussion)
            case .membersOfGroupV2WereUpdated:
                guard let groupV2Discussion = discussion as? PersistedGroupV2Discussion else {
                    return cancel(withReason: .inappropriatePersistedMessageSystemCategoryForGivenDiscussion(persistedMessageSystemCategory: persistedMessageSystemCategory))
                }
                _ = try? PersistedMessageSystem.insertMembersOfGroupV2WereUpdatedSystemMessage(within: groupV2Discussion)
            case .contactJoinedGroup,
                    .contactLeftGroup:
                guard let contactIdentityObjectID = self.optionalContactIdentityObjectID else {
                    return cancel(withReason: .noContactIdentityObjectIDAlthoughItIsRequired(persistedMessageSystemCategory: persistedMessageSystemCategory))
                }
                let contactIdentity = try PersistedObvContactIdentity.get(objectID: contactIdentityObjectID, within: obvContext.context)
                switch try? discussion.kind {
                case .oneToOne, .none:
                    return cancel(withReason: .inappropriatePersistedMessageSystemCategoryForGivenDiscussion(persistedMessageSystemCategory: persistedMessageSystemCategory))
                case .groupV1, .groupV2:
                    break
                }
                _ = try PersistedMessageSystem(persistedMessageSystemCategory, optionalContactIdentity: contactIdentity, optionalOwnedCryptoId: nil, optionalCallLogItem: nil, discussion: discussion, timestamp: Date())
            case .contactRevokedByIdentityProvider:
                // We do not need to pass the optional identity, as it is obvious in this case. And we prevent merge conflicts by doing so.
                _ = try PersistedMessageSystem(persistedMessageSystemCategory, optionalContactIdentity: nil, optionalOwnedCryptoId: nil, optionalCallLogItem: nil, discussion: discussion, timestamp: Date())
            case .callLogItem:
                guard let callLogItemObjectID = self.optionalCallLogItemObjectID else {
                    return cancel(withReason: .noCallLogItemObjectIDAlthoughItIsRequired)
                }
                
                guard let item = try PersistedCallLogItem.get(objectID: callLogItemObjectID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedObvContactIdentityInDatabase)
                }
                _ = try PersistedMessageSystem(persistedMessageSystemCategory, optionalContactIdentity: nil, optionalOwnedCryptoId: nil, optionalCallLogItem: item, discussion: discussion, timestamp: Date())
            case .numberOfNewMessages:
                assertionFailure("Not implemented")
            case .discussionIsEndToEndEncrypted:
                assertionFailure("Not implemented")
            case .contactWasDeleted:
                assertionFailure("Not implemented")
            case .updatedDiscussionSharedSettings:
                assertionFailure("Not implemented")
            case .notPartOfTheGroupAnymore:
                assertionFailure("Not implemented")
            case .rejoinedGroup:
                assertionFailure("Not implemented")
            case .contactIsOneToOneAgain:
                assertionFailure("Not implemented")
            case .ownedIdentityDidCaptureSensitiveMessages:
                assertionFailure("Not implemented")
            case .contactIdentityDidCaptureSensitiveMessages:
                assertionFailure("Not implemented")
            case .contactWasIntroducedToAnotherContact:
                assertionFailure("Not implemented")
            case .discussionWasRemotelyWiped:
                switch discussion.status {
                case .active:
                    break
                case .preDiscussion, .locked:
                    return cancel(withReason: .inappropriatePersistedMessageSystemCategoryForGivenDiscussion(persistedMessageSystemCategory: persistedMessageSystemCategory))
                }
                guard let contactIdentityObjectID = optionalContactIdentityObjectID else {
                    return cancel(withReason: .noContactIdentityObjectIDAlthoughItIsRequired(persistedMessageSystemCategory: persistedMessageSystemCategory))
                }
                guard let contactIdentity = try PersistedObvContactIdentity.get(objectID: contactIdentityObjectID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedObvContactIdentityInDatabase)
                }
                assert(messageUploadTimestampFromServer != nil)
                try discussion.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: false, messageTimestamp: Date())
                try PersistedMessageSystem.insertDiscussionWasRemotelyWipedSystemMessage(within: discussion, byContact: contactIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
}


enum InsertPersistedMessageSystemIntoDiscussionOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case couldNotFindPersistedDiscussionInDatabase
    case noContactIdentityObjectIDAlthoughItIsRequired(persistedMessageSystemCategory: PersistedMessageSystem.Category)
    case noCallLogItemObjectIDAlthoughItIsRequired
    case couldNotFindPersistedObvContactIdentityInDatabase
    case inappropriatePersistedMessageSystemCategoryForGivenDiscussion(persistedMessageSystemCategory: PersistedMessageSystem.Category)
    case coreDataError(error: Error)
    case contextIsNil
    case discussionObjectIDWasNotProvided
    
    var logType: OSLogType {
        switch self {
        case .couldNotFindPersistedDiscussionInDatabase,
             .discussionObjectIDWasNotProvided,
             .couldNotFindPersistedObvContactIdentityInDatabase:
            return .error
        case .noContactIdentityObjectIDAlthoughItIsRequired,
             .noCallLogItemObjectIDAlthoughItIsRequired,
             .inappropriatePersistedMessageSystemCategoryForGivenDiscussion,
             .coreDataError,
             .contextIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .couldNotFindPersistedDiscussionInDatabase:
            return "Could not find persisted discussion in database"
        case .noCallLogItemObjectIDAlthoughItIsRequired:
            return "Could not find call log item database"
        case .noContactIdentityObjectIDAlthoughItIsRequired(persistedMessageSystemCategory: let persistedMessageSystemCategory):
            return "No contact identity ObjectID was provided although it is required for the category \(persistedMessageSystemCategory.description)"
        case .couldNotFindPersistedObvContactIdentityInDatabase:
            return "Could not find persisted contact identity in database"
        case .inappropriatePersistedMessageSystemCategoryForGivenDiscussion(persistedMessageSystemCategory: let persistedMessageSystemCategory):
            return "Inappropriate message system category \(persistedMessageSystemCategory.description) for the given discussion"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .contextIsNil:
            return "Context is nil"
        case .discussionObjectIDWasNotProvided:
            return "Discussion object ID was not provided"
        }
    }
    
}
