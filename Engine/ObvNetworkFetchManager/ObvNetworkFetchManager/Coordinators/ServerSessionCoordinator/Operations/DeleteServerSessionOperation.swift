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
import ObvCrypto
import CoreData
import os.log


final class DeleteServerSessionOperation: ContextualOperationWithSpecificReasonForCancel<DeleteServerSessionOperation.ReasonForCancel> {
    
    private let ownedCryptoIdentity: ObvCryptoIdentity
    
    init(ownedCryptoIdentity: ObvCryptoIdentity) {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            try ServerSession.deleteAllSessionsOfIdentity(ownedCryptoIdentity, within: obvContext.context)
            
        } catch {
            
            return cancel(withReason: .coreDataError(error: error))
            
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        
        public var logType: OSLogType {
            switch self {
            case .coreDataError:
                return .fault
            }
        }

        public var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            }
        }

    }
    
}
