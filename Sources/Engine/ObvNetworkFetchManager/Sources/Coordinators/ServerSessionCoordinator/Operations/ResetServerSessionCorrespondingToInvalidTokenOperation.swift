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


final class ResetServerSessionCorrespondingToInvalidTokenOperation: ContextualOperationWithSpecificReasonForCancel<ResetServerSessionCorrespondingToInvalidTokenOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let ownedCryptoIdentity: ObvCryptoIdentity
    private let invalidToken: Data
    
    init(ownedCryptoIdentity: ObvCryptoIdentity, invalidToken: Data) {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.invalidToken = invalidToken
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let serverSession = try ServerSession.getOrCreate(within: obvContext.context, withIdentity: ownedCryptoIdentity)

            guard serverSession.token == invalidToken else {
                // The token of the current session is not the one that is invalid.
                // There is nothing left to do
                return
            }
            
            serverSession.resetSession()
            
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
