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
import ObvCrypto
import ObvMetaManager
import CoreData


/// This operation re-activates an owned identity. This shall only be performed after making sure the server considers that the current device of the owned identity is active.
/// As a consequence, if the user wants to reactivate the device, we do *not* immediately call this operation. Instead, we register the current device on the server with the `reactivateCurrentDevice` parameter set to `true`.
/// If this succeeds, the notification sent by the network manager will eventually trigger an execution of this operation.
final class ActivateOwnedIdentityOperation: ContextualOperationWithSpecificReasonForCancel<ActivateOwnedIdentityOperation.ReasonForCancel> {
    
    private let ownedCryptoIdentity: ObvCryptoIdentity
    private let identityDelegate: ObvIdentityDelegate
    
    init(ownedCryptoIdentity: ObvCryptoIdentity, identityDelegate: ObvIdentityDelegate) {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.identityDelegate = identityDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            // We first make sure the owned identity stil exist before trying to reactivate it.
            // If this is not the case, this operation does nothing
            
            guard try identityDelegate.isOwned(ownedCryptoIdentity, within: obvContext) else { return }
            
            // We reactivate the owned identity
            
            try identityDelegate.reactivateOwnedIdentity(ownedIdentity: ownedCryptoIdentity, within: obvContext)
            
            
        } catch {
            return cancel(withReason: .identityDelegateError(error: error))
        }

    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case identityDelegateError(error: Error)
        
        public var logType: OSLogType {
            switch self {
            case .identityDelegateError:
                return .fault
            }
        }
        
        public var errorDescription: String? {
            switch self {
            case .identityDelegateError(error: let error):
                return "Identity delegate error: \(error.localizedDescription)"
            }
        }
        
        
    }
    
}

