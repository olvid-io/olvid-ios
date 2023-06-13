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
import ObvTypes
import ObvUICoreData

final class UpdateCustomNameAndGroupV2PhotoOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>
    private let customName: String?
    private let customPhotoURL: URL?
    
    init(groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, customName: String?, customPhotoURL: URL?) {
        self.groupObjectID = groupObjectID
        self.customName = customName
        self.customPhotoURL = customPhotoURL
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            do {
                
                guard let group = try PersistedGroupV2.get(objectID: groupObjectID, within: obvContext.context) else {
                    return
                }
                
                do {
                    try group.updateCustomNameWith(with: customName)
                    try group.updateCustomPhotoWithPhotoAtURL(customPhotoURL, within: obvContext)
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }
                
                // Since the previous call did copy the photo to a proper location, we can delete the photo at the passed URL
                // We do so, even if there is an error during the context save
                
                if let customPhotoURL = customPhotoURL {
                    do {
                        try obvContext.addContextDidSaveCompletionHandler { _ in
                            try? FileManager.default.removeItem(at: customPhotoURL)
                        }
                    } catch {
                        return cancel(withReason: .coreDataError(error: error))
                    }
                    
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
}
