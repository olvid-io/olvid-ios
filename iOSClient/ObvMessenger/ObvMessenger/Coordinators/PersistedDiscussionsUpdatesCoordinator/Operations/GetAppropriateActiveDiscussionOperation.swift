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
import ObvTypes
import OlvidUtils
import ObvCrypto

/// This operation looks for a persisted discussion (either one2one or for a group) that is the most appropriate given the parameters. In case the groupId is non nil, it looks for a group discussion and makes sure the contact identity is part of the group (but not necessarily owner).
/// If this operation finishes without cancelling, the value of the `discussionObjectID` variable is guaranteed to be set.
final class GetAppropriateActiveDiscussionOperation: OperationWithSpecificReasonForCancel<GetAppropriateDiscussionOperationReasonForCancel> {

    private let contact: ObvContactIdentity
    private let groupIdentifier: GroupIdentifier?
    
    private(set) var discussionObjectID: NSManagedObjectID?
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: GetAppropriateActiveDiscussionOperation.self))

    init(contact: ObvContactIdentity, groupIdentifier: GroupIdentifier?) {
        self.contact = contact
        self.groupIdentifier = groupIdentifier
        super.init()
    }

    override func main() {

        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            do {
                
                guard let persistedContact = try PersistedObvContactIdentity.get(persisted: contact, whereOneToOneStatusIs: .any, within: context) else {
                    return cancel(withReason: .couldNotFindContact)
                }
                
                guard let ownedIdentity = persistedContact.ownedIdentity else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }
                
                switch groupIdentifier {
                    
                case .none:
                    
                    guard let discussion = try PersistedOneToOneDiscussion.get(with: persistedContact, status: .active) else {
                        return cancel(withReason: .couldNotFindDiscussion)
                    }
                    assert(persistedContact.isOneToOne)
                    // If we reach this point, we found the appropriate one2one discussion
                    self.discussionObjectID = discussion.objectID
                    return
                    
                case .groupV1(groupV1Identifier: let groupV1Identifier):
                    
                    guard let contactGroup = try PersistedContactGroup.getContactGroup(groupId: groupV1Identifier, ownedIdentity: ownedIdentity) else {
                        return cancel(withReason: .couldNotFindContactGroup)
                    }
                    // We make sure the contact is either owner or part of the group
                    if let ownedGroup = contactGroup as? PersistedContactGroupOwned {
                        guard ownedGroup.contactIdentities.contains(persistedContact) else {
                            assertionFailure()
                            return cancel(withReason: .contactIsNotPartOfGroup)
                        }
                    } else if let joinedGroup = contactGroup as? PersistedContactGroupJoined {
                        guard joinedGroup.contactIdentities.contains(persistedContact) ||
                                joinedGroup.owner == persistedContact else {
                            assertionFailure()
                            return cancel(withReason: .contactIsNotPartOfGroup)
                        }
                    } else {
                        return cancel(withReason: .unexpectedGroupSubclass)
                    }
                    // If we reach this point, we found the group and the contact is indeed part of this group
                    guard contactGroup.discussion.status == .active else {
                        return cancel(withReason: .couldNotFindDiscussion)
                    }
                    self.discussionObjectID = contactGroup.discussion.objectID
                    return
                    
                case .groupV2(groupV2Identifier: let groupV2Identifier):
                    
                    guard let group = try PersistedGroupV2.get(ownIdentity: ownedIdentity, appGroupIdentifier: groupV2Identifier) else {
                        return cancel(withReason: .couldNotFindContactGroup)
                    }
                    // Make sure the contact is part of the group
                    guard group.contactsAmongOtherPendingAndNonPendingMembers.contains(persistedContact) else {
                        assertionFailure()
                        return cancel(withReason: .contactIsNotPartOfGroup)
                    }
                    // If we reach this point, we found the group and the contact is indeed part of this group
                    guard let discussion = group.discussion, discussion.status == .active else {
                        return cancel(withReason: .couldNotFindDiscussion)
                    }
                    self.discussionObjectID = discussion.objectID
                    return
                    
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
}


enum GetAppropriateDiscussionOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case couldNotFindContact
    case couldNotFindOwnedIdentity
    case couldNotFindContactGroup
    case contactIsNotPartOfGroup
    case unexpectedGroupSubclass
    case couldNotFindDiscussion

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .couldNotFindOwnedIdentity,
             .couldNotFindContactGroup,
             .contactIsNotPartOfGroup,
             .unexpectedGroupSubclass,
             .couldNotFindDiscussion,
             .couldNotFindContact:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindContact:
            return "Could not find contact in database"
        case .couldNotFindOwnedIdentity:
            return "Could not find owned identity"
        case .couldNotFindContactGroup:
            return "Could not find contact group"
        case .contactIsNotPartOfGroup:
            return "The contact is not part of the group"
        case .unexpectedGroupSubclass:
            return "Unexpected contact group subclass"
        case .couldNotFindDiscussion:
            return "Could not find discussion"
        }
    }

}
