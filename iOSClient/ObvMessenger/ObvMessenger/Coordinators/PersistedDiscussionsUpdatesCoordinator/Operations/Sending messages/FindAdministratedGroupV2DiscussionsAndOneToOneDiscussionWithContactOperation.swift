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
import OlvidUtils
import CoreData

/// Given a contact device object ID (or a contact), this operation finds the corresponding contact. It then looks for all the group v2 discussions where the contact is a member and administrated by the corresponding owned identity. It also look for the appropriate oneToOneDiscussion.
final class FindAdministratedGroupV2DiscussionsAndOneToOneDiscussionWithContactOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    enum Input {
        case contactDevice(contactDeviceObjectID: NSManagedObjectID)
        case contact(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
    }
    
    private let input: Input
    private let includeOneToOneDiscussionInResult: Bool
        
    init(input: Input, includeOneToOneDiscussionInResult: Bool) {
        self.input = input
        self.includeOneToOneDiscussionInResult = includeOneToOneDiscussionInResult
        super.init()
    }
    
    /// If this operation finishes without cancelling, this is guaranteed to be set.
    /// It will contain the object IDs of all the group V2 discussions where the contact is part of the members and where the corresponding owned identity is an administrator.
    /// It will also contain the object ID of the oneToOne discussion.
    private(set) var persistedDiscussionObjectIDs = Set<TypeSafeManagedObjectID<PersistedDiscussion>>()

    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {

            do {
            
                let contact: PersistedObvContactIdentity
                
                switch input {
                case .contactDevice(let contactDeviceObjectID):
                    
                    // Find the contact device and corresponding contact
                    
                    guard let device = try PersistedObvContactDevice.get(contactDeviceObjectID: contactDeviceObjectID, within: obvContext.context) else {
                        assertionFailure()
                        return
                    }
                    
                    guard let _contact = device.identity else {
                        assertionFailure()
                        return
                    }
                    
                    contact = _contact
                    
                case .contact(let contactObjectID):
                    
                    guard let _contact = try PersistedObvContactIdentity.get(objectID: contactObjectID, within: obvContext.context) else {
                        assertionFailure()
                        return
                    }
                    
                    contact = _contact

                }

                // Find all group v2 that include this contact and keep those that we administrate
                
                let administratedGroups = try PersistedGroupV2.getAllPersistedGroupV2(whereContactIdentitiesInclude: contact)
                    .filter({ $0.ownedIdentityIsAllowedToChangeSettings })
                
                // Save the object IDs of the corresponding discussions
                
                self.persistedDiscussionObjectIDs = Set(administratedGroups.compactMap({ $0.discussion?.typedObjectID.downcast }))
                
                // Add the objectID of the one-to-one discussion the owned identity has with the contact
                
                if includeOneToOneDiscussionInResult {
                    if let oneToOneDiscussionObjectID = contact.oneToOneDiscussion?.typedObjectID.downcast {
                        self.persistedDiscussionObjectIDs.insert(oneToOneDiscussionObjectID)
                    } else if contact.isOneToOne {
                        assertionFailure()
                        // Continue anyway
                    }
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
}
