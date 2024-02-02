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
import os.log
import ObvEngine
import CoreData
import ObvUICoreData


final class ProcessContactGroupHasUpdatedPendingMembersAndGroupMembersOperation: ContextualOperationWithSpecificReasonForCancel<ProcessContactGroupHasUpdatedPendingMembersAndGroupMembersOperationReasonForCancel> {

    let obvContactGroup: ObvContactGroup
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ProcessContactGroupHasUpdatedPendingMembersAndGroupMembersOperation.self))

    init(obvContactGroup: ObvContactGroup) {
        self.obvContactGroup = obvContactGroup
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let persistedObvOwnedIdentity = try PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: obvContext.context) else {
                return
            }
            
            let persistedObvContactIdentities: Set<PersistedObvContactIdentity> = Set(obvContactGroup.groupMembers.compactMap {
                guard let persistedContact = try? PersistedObvContactIdentity.get(persisted: $0.contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    os_log("One of the group members is not among our persisted contacts. The group members will be updated when this contact will be added to the persisted contact.", log: Self.log, type: .info)
                    return nil
                }
                return persistedContact
            })
            
            guard let contactGroup = try PersistedContactGroup.getContactGroup(groupIdentifier: obvContactGroup.groupIdentifier, ownedIdentity: persistedObvOwnedIdentity) else {
                return cancel(withReason: .couldNotFindContactGroup)
            }
            
            contactGroup.set(persistedObvContactIdentities)
            try contactGroup.setPendingMembers(to: obvContactGroup.pendingGroupMembers)
            
            if let groupOwned = contactGroup as? PersistedContactGroupOwned {
                if obvContactGroup.groupType == .owned {
                    let declinedMemberIdentites = Set(obvContactGroup.declinedPendingGroupMembers.map { $0.cryptoId })
                    for pendingMember in groupOwned.pendingMembers {
                        pendingMember.declined = declinedMemberIdentites.contains(pendingMember.cryptoId)
                    }
                }
            }
            
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
}


enum ProcessContactGroupHasUpdatedPendingMembersAndGroupMembersOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindContactGroup
    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil, .couldNotFindContactGroup:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindContactGroup:
            return "Could not find contact group"
        }
    }

}
