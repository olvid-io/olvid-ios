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
import OlvidUtils
import CoreData
import ObvUICoreData
import ObvTypes
import os.log


/// Given a contact device object ID (or a contact), this operation finds the corresponding contact. It then looks for all the group v2 discussions where the contact is a member and administrated by the corresponding owned identity. It also look for the appropriate oneToOneDiscussion.
final class FindAdministratedGroupV2DiscussionsAndOneToOneDiscussionWithContactOperation: ContextualOperationWithSpecificReasonForCancel<FindAdministratedGroupV2DiscussionsAndOneToOneDiscussionWithContactOperation.ReasonForCancel>, @unchecked Sendable {
    
    enum Input {
        case contactDevice(contactDeviceObjectID: TypeSafeManagedObjectID<PersistedObvContactDevice>)
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
    /// It will contain the identifiers of all the group V2 discussions where the contact is part of the members and where the corresponding owned identity is an administrator.
    /// It will also contain the identifier of the oneToOne discussion.
    private(set) var persistedDiscussionIdentifiers = [DiscussionIdentifier]()
    private(set) var ownedCryptoId: ObvCryptoId?
    private(set) var contactCryptoId: ObvCryptoId?

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let contact: PersistedObvContactIdentity
            
            switch input {
            case .contactDevice(let contactDeviceObjectID):
                
                // Find the contact device and corresponding contact
                
                guard let device = try PersistedObvContactDevice.get(contactDeviceObjectID: contactDeviceObjectID.objectID, within: obvContext.context) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindContactDevice)
                }
                
                guard let _contact = device.identity else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindContactIdentity)
                }
                
                contact = _contact
                
            case .contact(let contactObjectID):
                
                guard let _contact = try PersistedObvContactIdentity.get(objectID: contactObjectID, within: obvContext.context) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindContactIdentity)
                }
                
                contact = _contact
                
            }
            
            self.contactCryptoId = contact.cryptoId
            
            guard let _ownedCryptoId = contact.ownedIdentity?.cryptoId else {
                return cancel(withReason: .couldNotDetermineOwnedCryptoId)
            }
            
            self.ownedCryptoId = _ownedCryptoId
            
            // Find all group v2 that include this contact and keep those that we administrate
            
            let administratedGroups = try PersistedGroupV2.getAllPersistedGroupV2(whereContactIdentitiesInclude: contact)
                .filter({ $0.ownedIdentityIsAllowedToChangeSettings })
            
            // Save the object IDs of the corresponding discussions
            
            self.persistedDiscussionIdentifiers = administratedGroups.compactMap({ try? $0.discussion?.identifier })
            
            // Add the objectID of the one-to-one discussion the owned identity has with the contact
            
            if includeOneToOneDiscussionInResult {
                if let oneToOneDiscussionIdentifier = try? contact.oneToOneDiscussion?.identifier {
                    self.persistedDiscussionIdentifiers.append(oneToOneDiscussionIdentifier)
                } else if contact.isOneToOne {
                    assertionFailure()
                    // Continue anyway
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotDetermineOwnedCryptoId
        case couldNotFindContactDevice
        case couldNotFindContactIdentity
        
        var logType: OSLogType {
            return .fault
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotDetermineOwnedCryptoId:
                return "Could not determine owned crypto id"
            case .couldNotFindContactDevice:
                return "Could not find contact device"
            case .couldNotFindContactIdentity:
                return "Could not find contact identity"
            }
        }

    }

}
