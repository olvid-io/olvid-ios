/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

/// This operation replaces the discussion (either one-to-one or group) by another empty discussion of the same type.
/// Before saving the context, this operation deletes the old discussion, which cascade deletes its messages.
/// If this operation finishes without cancelling, `newDiscussionObjectID` is set to the objectID of the new discussion if a new discussion was created during this operation.
final class DeleteAllPersistedMessagesWithinDiscussionOperation: ContextualOperationWithSpecificReasonForCancel<DeleteAllPersistedMessagesWithinDiscussionOperationReasonForCancel> {
        
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: DeleteAllPersistedMessagesWithinDiscussionOperation.self))

    private let persistedDiscussionObjectID: NSManagedObjectID
    
    init(persistedDiscussionObjectID: NSManagedObjectID) {
        self.persistedDiscussionObjectID = persistedDiscussionObjectID
        super.init()
    }
    
    private(set) var newDiscussionObjectID: NSManagedObjectID?
    private(set) var atLeastOneMessageWasDeleted = false
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
        
            do {
                guard let discussion = try PersistedDiscussion.get(objectID: persistedDiscussionObjectID,
                                                                   within: obvContext.context) else { return }
                // Deleting all messages is implemented as a deletion of a discussion.
                // If the deleted discussion is active, it is replaced by a new one with the same configuration.
                // In practice, this behavior allows to efficiently delete all messages.
                switch discussion.status {
                case .preDiscussion, .locked:
                    break
                case .active:
                    let sharedConfigurationToKeep = discussion.sharedConfiguration
                    let localConfigurationToKeep = discussion.localConfiguration
                    do {
                        switch try discussion.kind {
                        case .oneToOne(withContactIdentity: let contactIdentity):
                            if let contactIdentity = contactIdentity {
                                let newDiscussion = try PersistedOneToOneDiscussion(
                                    contactIdentity: contactIdentity,
                                    status: .active,
                                    insertDiscussionIsEndToEndEncryptedSystemMessage: false,
                                    sharedConfigurationToKeep: sharedConfigurationToKeep,
                                    localConfigurationToKeep: localConfigurationToKeep)
                                try obvContext.context.obtainPermanentIDs(for: [newDiscussion])
                                assert(newDiscussionObjectID == nil)
                                newDiscussionObjectID = newDiscussion.objectID
                            }
                        case .groupV1(withContactGroup: let contactGroup):
                            if let contactGroup = contactGroup, let ownedIdentity = discussion.ownedIdentity {
                                let groupName = discussion.title
                                let newDiscussion = try PersistedGroupDiscussion(
                                    contactGroup: contactGroup,
                                    groupName: groupName,
                                    ownedIdentity: ownedIdentity,
                                    status: .active,
                                    insertDiscussionIsEndToEndEncryptedSystemMessage: false,
                                    sharedConfigurationToKeep: sharedConfigurationToKeep,
                                    localConfigurationToKeep: localConfigurationToKeep)
                                try obvContext.context.obtainPermanentIDs(for: [newDiscussion])
                                assert(newDiscussionObjectID == nil)
                                newDiscussionObjectID = newDiscussion.objectID
                            }
                        }
                    } catch {
                        return cancel(withReason: .unknownDiscussionType)
                    }
                }
                atLeastOneMessageWasDeleted = !discussion.messages.isEmpty
                try discussion.delete()
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }
        
    }
    
}

enum DeleteAllPersistedMessagesWithinDiscussionOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case unknownDiscussionType
    case coreDataError(error: Error)
    case contextIsNil
    
    var logType: OSLogType {
        switch self {
        case .unknownDiscussionType,
             .coreDataError,
             .contextIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .unknownDiscussionType:
            return "Unknown discussion type"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
    
}
