/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import os.log
import CoreData
import OlvidUtils
import ObvUICoreData
import ObvEncoder


final class MigrateUtiOfFyleMessageJoinWithStatusForLinkPreviewIfAppropriateOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    

    private let objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>
    
    init(objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) {
        self.objectID = objectID
        super.init()
    }
    
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let join = try FyleMessageJoinWithStatus.get(objectID: objectID.objectID, within: obvContext.context) else { return }
            
            // Check that the file on disk is an ObvLinkMetadata
            
            guard let fileURL = join.fyle?.url else { return }
            guard FileManager.default.fileExists(atPath: fileURL.path) else { assertionFailure(); return }
            guard let fileSize = fileURL.getFileSize() else { assertionFailure(); return }
            guard fileSize < 10_000_000 else { return }
            guard let data = try? Data(contentsOf: fileURL) else { assertionFailure(); return }
            guard let obvEncoded = ObvEncoded(withRawData: data), ObvLinkMetadata.decode(obvEncoded, fallbackURL: nil) != nil else { return }

            // If we reach this point, the file on disk is an ObvLinkMetadata. We migrate the UTI of the join.
            
            join.migrateDynUtiToOlvidPreviewUti()
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
}
