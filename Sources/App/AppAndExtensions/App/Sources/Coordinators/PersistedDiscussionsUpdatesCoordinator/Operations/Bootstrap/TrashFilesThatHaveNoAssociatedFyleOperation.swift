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
import CoreData
import os.log
import OlvidUtils
import ObvUICoreData
import ObvAppCoreConstants


/// This method takes as an input a list of file names (expected to be in the Fyles directory) that are likely to have no associated `Fyle` entry in database.
/// For each of these files, we check that there is no `Fyle` entry and, if this is the case, move the file to the trash.
/// The list of file candidates is expected to be constructed asynchronously since it is potentially an expensive operation. Since the work is done asynchronously,
/// we *do* check here that no `Fyle` entry was created between the time the list of candidates was computed and the time this operation is executed.
final class TrashFilesThatHaveNoAssociatedFyleOperation: OperationWithSpecificReasonForCancel<TrashFilesThatHaveNoAssociatedFyleOperationReasonForCancel>, @unchecked Sendable {
        
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: TrashFilesThatHaveNoAssociatedFyleOperation.self))

    private let urlsCandidatesForTrash: Set<URL>
    
    init(urlsCandidatesForTrash: Set<URL>) {
        self.urlsCandidatesForTrash = urlsCandidatesForTrash
        super.init()
    }
 
    
    override func main() {

        var errorWhenTrashingFile: Error?

        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            for url in urlsCandidatesForTrash {
                
                do {
                    guard try Fyle.noFyleReferencesTheURL(url, within: context) else { continue }
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }

                // If we reach this point, we can trash the file at url

                do {
                    try url.moveToTrash()
                } catch {
                    os_log("Failed to move a specific orphaned file to trash: %{public}@", log: log, type: .fault, error.localizedDescription)
                    errorWhenTrashingFile = error
                    // We continue iterating of the other urls
                }
                
            }
            
        }
        
        if let error = errorWhenTrashingFile {
            return cancel(withReason: .couldNotTrashFile(error: error))
        }
        
    }
    
}


enum TrashFilesThatHaveNoAssociatedFyleOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case couldNotTrashFile(error: Error)
    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .couldNotTrashFile:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .couldNotTrashFile(error: let error):
            return "Failed to trash a file: \(error.localizedDescription)"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
    
}
