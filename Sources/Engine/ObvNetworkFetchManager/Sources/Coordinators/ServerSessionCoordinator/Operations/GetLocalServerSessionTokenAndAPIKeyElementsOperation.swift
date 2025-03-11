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
import ObvTypes


final class GetLocalServerSessionTokenAndAPIKeyElementsOperation: ContextualOperationWithSpecificReasonForCancel<GetLocalServerSessionTokenAndAPIKeyElementsOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let ownedCryptoIdentity: ObvCryptoIdentity
    
    init(ownedCryptoIdentity: ObvCryptoIdentity) {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        super.init()
    }
    
    private(set) var serverSessionTokenAndAPIKeyElements: (serverSessionToken: Data, apiKeyElements: APIKeyElements)?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let serverSession = try ServerSession.getOrCreate(within: obvContext.context, withIdentity: ownedCryptoIdentity)

            if let serverSessionToken = serverSession.token, let apiKeyElements = serverSession.apiKeyElements {
                self.serverSessionTokenAndAPIKeyElements = (serverSessionToken, apiKeyElements)
            }
            
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
