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
import ObvUICoreData
import CoreData
import ObvAppCoreConstants


final class SynchronizeOneToOneDiscussionTitlesWithContactNameOperation: ContextualOperationWithSpecificReasonForCancel<SynchronizeOneToOneDiscussionTitlesWithContactNameOperationReasonForCancel>, @unchecked Sendable {
    
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SynchronizeOneToOneDiscussionTitlesWithContactNameOperation.self))

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            let ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: obvContext.context)
            for ownedIdentity in ownedIdentities {
                ownedIdentity.contacts.forEach { contact in
                    do {
                        try contact.resetOneToOneDiscussionTitle()
                    } catch {
                        os_log("One of the one2one discussion title could not be reset", log: log, type: .fault)
                        assertionFailure()
                        // Continue anyway
                    }
                }
            }
        } catch {
            return cancel(withReason: .coreDataError(error: error))
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
