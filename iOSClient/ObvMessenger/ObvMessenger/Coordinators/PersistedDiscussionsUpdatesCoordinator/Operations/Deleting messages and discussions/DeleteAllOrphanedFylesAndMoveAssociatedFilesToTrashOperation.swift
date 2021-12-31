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
import CoreData
import os.log
import OlvidUtils


/// This operation deletes all `Fyle` instances that have no associated `FyleMessageJoinWithStatus` instance.
/// For each orphaned fyle, we first move the associated file (on disk) to the trash.
final class DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation: ContextualOperationWithSpecificReasonForCancel<DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperationReasonForCancel> {
 
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {

            let orphanedFyles: [Fyle]
            do {
                orphanedFyles = try Fyle.getAllOrphaned(within: obvContext.context)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            guard !orphanedFyles.isEmpty else { return }
            
            for fyle in orphanedFyles {
                do {
                    try fyle.moveFileToTrash()
                    obvContext.context.delete(fyle)
                } catch {
                    os_log("One of the fyles could not be trashed: %{public}@", type: .fault, error.localizedDescription)
                    assertionFailure()
                    // Continue anyway
                }
            }
                        
        }
        
    }

}

enum DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperationReasonForCancel: LocalizedErrorWithLogType {
    
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
