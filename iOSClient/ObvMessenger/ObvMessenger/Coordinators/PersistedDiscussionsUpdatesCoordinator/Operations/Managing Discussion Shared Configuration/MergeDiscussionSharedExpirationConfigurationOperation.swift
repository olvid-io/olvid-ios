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
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MergeDiscussionSharedExpirationConfigurationOperation.self))

    private(set) var updatedDiscussionObjectID: NSManagedObjectID? // Set if the operation changes something and finishes without cancelling
    
    init(discussionSharedConfiguration: DiscussionSharedConfigurationJSON, fromContactIdentity: ObvContactIdentity) {
        self.discussionSharedConfiguration = discussionSharedConfiguration
        self.fromContactIdentity = fromContactIdentity
        super.init()
    }
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            do {
                
                guard let persistedContact = try PersistedObvContactIdentity.get(persisted: fromContactIdentity, whereOneToOneStatusIs: .any, within: context) else {
                    return cancel(withReason: .contactCannotBeFound)
                }
                
                switch discussionSharedConfiguration.groupIdentifier {
                    
                case .none:
                    
                    // The configuration concerns the one2one discussion we have with the contact
                    guard let oneToOneDiscussion = persistedContact.oneToOneDiscussion else {
                        return cancel(withReason: .discussionCannotBeFound)
                    }
                    let sharedConfiguration = oneToOneDiscussion.sharedConfiguration
                    guard try sharedConfiguration.merge(with: discussionSharedConfiguration, initiator: fromContactIdentity.cryptoId) else {
                        // There was nothing to do
                        return
                    }
                    self.updatedDiscussionObjectID = oneToOneDiscussion.objectID
                    
                case .groupV1(groupV1Identifier: let groupV1Identifier):
                    
                    // The configuration concerns a group discussion
                    guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(persisted: fromContactIdentity.ownedIdentity, within: context) else {
                        return cancel(withReason: .couldNotFindPersistedOwnedIdentity)
                    }
                    let contactGroup: PersistedContactGroup
                    guard let _contactGroup = try PersistedContactGroupJoined.getContactGroup(groupId: groupV1Identifier, ownedIdentity: persistedOwnedIdentity) else {
                        return cancel(withReason: .contactGroupCannotBeFound)
                    }
                    contactGroup = _contactGroup
                    guard contactGroup.ownerIdentity == fromContactIdentity.cryptoId.getIdentity() else {
                        return cancel(withReason: .sharedConfigWasNotSentByGroupOwner)
                    }
                    let sharedConfiguration = contactGroup.discussion.sharedConfiguration
                    guard try sharedConfiguration.merge(with: discussionSharedConfiguration, initiator: fromContactIdentity.cryptoId) else {
                        // There was nothing to do
                        return
                    }
                    self.updatedDiscussionObjectID = contactGroup.discussion.objectID
                    
                case .groupV2(groupV2Identifier: let groupV2Identifier):
                    
                    // The configuration concerns a group v2 discussion
                    guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(persisted: fromContactIdentity.ownedIdentity, within: context) else {
                        return cancel(withReason: .couldNotFindPersistedOwnedIdentity)
                    }
                    guard let group = try PersistedGroupV2.get(ownIdentity: persistedOwnedIdentity, appGroupIdentifier: groupV2Identifier) else {
                        return cancel(withReason: .contactGroupCannotBeFound)
                    }
                    guard let discussion = group.discussion else {
                        return cancel(withReason: .discussionCannotBeFound)
                    }
                    let sharedConfiguration = discussion.sharedConfiguration
                    guard try sharedConfiguration.merge(with: discussionSharedConfiguration, initiator: fromContactIdentity.cryptoId) else {
                        // There was nothing to do
                        return
                    }
                    self.updatedDiscussionObjectID = discussion.objectID
                    
                }
                
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
