/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

final class SynchronizeOneToOneDiscussionTitlesWithContactNameOperation: ContextualOperationWithSpecificReasonForCancel<SynchronizeOneToOneDiscussionTitlesWithContactNameOperationReasonForCancel> {
    
    private let ownedIdentityObjectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    init(ownedIdentityObjectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>) {
        self.ownedIdentityObjectID = ownedIdentityObjectID
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {

            do {
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(objectID: ownedIdentityObjectID, within: obvContext.context) else { assertionFailure(); return }
                ownedIdentity.contacts.forEach { contact in
                    do {
                        try contact.resetOneToOneDiscussionTitle()
                    } catch {
                        os_log("One of the one2one discussion title could not be reset", log: log, type: .fault)
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


enum SynchronizeOneToOneDiscussionTitlesWithContactNameOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .contextIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
    
}
