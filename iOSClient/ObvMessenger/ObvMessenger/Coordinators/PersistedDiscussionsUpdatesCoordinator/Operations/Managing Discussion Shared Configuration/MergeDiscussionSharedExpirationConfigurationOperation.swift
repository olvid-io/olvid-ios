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
import ObvEngine
import OlvidUtils

/// When receiving a shared configuration for a discussion, we merge it with our own current configuration.
final class MergeDiscussionSharedExpirationConfigurationOperation: OperationWithSpecificReasonForCancel<MergeDiscussionSharedExpirationConfigurationOperationReasonForCancel> {
    
    let discussionSharedConfiguration: DiscussionSharedConfigurationJSON
    let fromContactIdentity: ObvContactIdentity
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    private(set) var updatedDiscussionObjectID: NSManagedObjectID? // Set if the operation changes something and finishes without cancelling
    
    init(discussionSharedConfiguration: DiscussionSharedConfigurationJSON, fromContactIdentity: ObvContactIdentity) {
        self.discussionSharedConfiguration = discussionSharedConfiguration
        self.fromContactIdentity = fromContactIdentity
        super.init()
    }
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            let persistedContact: PersistedObvContactIdentity
            do {
                guard let _contact = try PersistedObvContactIdentity.get(persisted: fromContactIdentity, within: context) else {
                    return cancel(withReason: .contactCannotBeFound)
                }
                persistedContact = _contact
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            if let groupId = discussionSharedConfiguration.groupId {
                // The configuration concerns a group discussion
                guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: fromContactIdentity.ownedIdentity, within: context) else {
                    return cancel(withReason: .couldNotFindPersistedOwnedIdentity)
                }
                let contactGroup: PersistedContactGroup
                do {
                    guard let _contactGroup = try PersistedContactGroupJoined.getContactGroup(groupId: groupId, ownedIdentity: persistedOwnedIdentity) else {
                        return cancel(withReason: .contactGroupCannotBeFound)
                    }
                    contactGroup = _contactGroup
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }
                guard contactGroup.ownerIdentity == fromContactIdentity.cryptoId.getIdentity() else {
                    return cancel(withReason: .sharedConfigWasNotSentByGroupOwner)
                }
                let sharedConfiguration = contactGroup.discussion.sharedConfiguration
                do {
                    guard try sharedConfiguration.merge(with: discussionSharedConfiguration, initiator: fromContactIdentity.cryptoId) else {
                        // There was nothing to do
                        return
                    }
                } catch {
                    return cancel(withReason: .unexpectedError)
                }
                self.updatedDiscussionObjectID = contactGroup.discussion.objectID
            } else {
                // The configuration concerns the one2one discussion we have with the contact
                let sharedConfiguration = persistedContact.oneToOneDiscussion.sharedConfiguration
                do {
                    guard try sharedConfiguration.merge(with: discussionSharedConfiguration, initiator: fromContactIdentity.cryptoId) else {
                        // There was nothing to do
                        return
                    }
                } catch {
                    return cancel(withReason: .unexpectedError)
                }
                self.updatedDiscussionObjectID = persistedContact.oneToOneDiscussion.objectID
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }
        
    }
}

enum MergeDiscussionSharedExpirationConfigurationOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case discussionCannotBeFound
    case contactCannotBeFound
    case couldNotFindPersistedOwnedIdentity
    case contactGroupCannotBeFound
    case sharedConfigWasNotSentByGroupOwner
    case unexpectedError

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .couldNotFindPersistedOwnedIdentity,
             .unexpectedError:
            return .fault
        case .discussionCannotBeFound,
             .contactCannotBeFound,
             .contactGroupCannotBeFound,
             .sharedConfigWasNotSentByGroupOwner:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .discussionCannotBeFound:
            return "Could not find discussion in database"
        case .contactCannotBeFound:
            return "Could not find contact in database"
        case .couldNotFindPersistedOwnedIdentity:
            return "Could not find persisted owned identity"
        case .contactGroupCannotBeFound:
            return "Could not find contact group"
        case .sharedConfigWasNotSentByGroupOwner:
            return "Group discussion configuration was not sent by the group owner"
        case .unexpectedError:
            return "Unexpected error. This is a bug."
        }
    }

}
