/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OlvidUtils
import ObvCrypto


final class GetOwnedIdentitiesHavingServerSessionOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private(set) var ownedCryptoIds: Set<ObvCryptoIdentity>?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            let serverSessions = try ServerSession.getAllServerSessions(within: obvContext.context)
            self.ownedCryptoIds = Set(try serverSessions.map({ try $0.ownedCryptoIdentity }))
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
