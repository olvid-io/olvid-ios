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
import ObvTypes
import CoreData
import ObvUICoreData


final class UpdateCustomNicknameAndPictureForContactOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    let persistedContactObjectID: NSManagedObjectID
    let customDisplayName: String?
    let customPhotoURL: URL?
    
    init(persistedContactObjectID: NSManagedObjectID, customDisplayName: String?, customPhotoURL: URL?) {
        self.persistedContactObjectID = persistedContactObjectID
        self.customDisplayName = customDisplayName
        self.customPhotoURL = customPhotoURL
        super.init()
    }
    
    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            do {
                
                guard let contact = try PersistedObvContactIdentity.get(objectID: persistedContactObjectID, within: obvContext.context) else { assertionFailure(); return }
                try contact.setCustomDisplayName(to: customDisplayName)
                contact.setCustomPhotoURL(with: customPhotoURL)

            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }

    }
}
