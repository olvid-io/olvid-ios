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

final class RemoveUpdateInProgressForGroupV2Operation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let ownedIdentity: ObvCryptoId
    private let appGroupIdentifier: Data
    
    init(ownedIdentity: ObvCryptoId, appGroupIdentifier: Data) {
        self.ownedIdentity = ownedIdentity
        self.appGroupIdentifier = appGroupIdentifier
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            do {
                guard let group = try PersistedGroupV2.get(ownIdentity: ownedIdentity, appGroupIdentifier: appGroupIdentifier, within: obvContext.context) else {
                    return
                }
                group.removeUpdateInProgress()
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
}
