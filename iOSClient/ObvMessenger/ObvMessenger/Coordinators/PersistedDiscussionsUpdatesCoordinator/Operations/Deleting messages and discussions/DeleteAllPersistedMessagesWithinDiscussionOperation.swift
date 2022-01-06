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
        
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

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
                guard let discussion = try PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: obvContext.context) else { return }
                let sharedConfigurationToKeep = discussion.sharedConfiguration
                let localConfigurationToKeep = discussion.localConfiguration
                if let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion {
                    if let contactIdentity = oneToOneDiscussion.contactIdentity {
                        guard let newDiscussion = PersistedOneToOneDiscussion(contactIdentity: contactIdentity,
                                                                              insertDiscussionIsEndToEndEncryptedSystemMessage: false,
                                                                              sharedConfigurationToKeep: sharedConfigurationToKeep,
                                                                              localConfigurationToKeep: localConfigurationToKeep) else {
                            return cancel(withReason: .couldNotCreateNewDiscussion)
                        }
                        do {
                            try obvContext.context.obtainPermanentIDs(for: [newDiscussion])
                        } catch {
                            return cancel(withReason: .coreDataError(error: error))
                        }
                        assert(newDiscussionObjectID == nil)
                        newDiscussionObjectID = newDiscussion.objectID
                    }
                } else if let groupDiscussion = discussion as? PersistedGroupDiscussion {
                    if let contactGroup = groupDiscussion.contactGroup, let ownedIdentity = groupDiscussion.ownedIdentity {
                        let groupName = groupDiscussion.title
                        guard let newDiscussion = PersistedGroupDiscussion(contactGroup: contactGroup,
                                                                           groupName: groupName,
                                                                           ownedIdentity: ownedIdentity,
                                                                           insertDiscussionIsEndToEndEncryptedSystemMessage: false,
                                                                           sharedConfigurationToKeep: sharedConfigurationToKeep,
                                                                           localConfigurationToKeep: localConfigurationToKeep) else {
                            return cancel(withReason: .couldNotCreateNewDiscussion)
                        }
                        do {
                            try obvContext.context.obtainPermanentIDs(for: [newDiscussion])
                        } catch {
                            return cancel(withReason: .coreDataError(error: error))
                        }
                        assert(newDiscussionObjectID == nil)
                        newDiscussionObjectID = newDiscussion.objectID
                    }
                } else if discussion is PersistedDiscussionOneToOneLocked || discussion is PersistedDiscussionGroupLocked {
                    // This is ok
                } else {
                    return cancel(withReason: .unknownDiscussionType)
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
    
    case couldNotCreateNewDiscussion
    case unknownDiscussionType
    case coreDataError(error: Error)
    case contextIsNil
    
    var logType: OSLogType {
        switch self {
        case .couldNotCreateNewDiscussion,
             .unknownDiscussionType,
             .coreDataError,
             .contextIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .couldNotCreateNewDiscussion:
            return "Could create new discussion to replace the one to delete"
        case .unknownDiscussionType:
            return "Unknown discussion type"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
    
}
