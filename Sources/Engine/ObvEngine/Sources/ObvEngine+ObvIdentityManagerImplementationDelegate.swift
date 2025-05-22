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
import ObvIdentityManager
import ObvTypes
import OlvidUtils
import ObvCrypto


extension ObvEngine: ObvIdentityManagerImplementationDelegate {
    public func previousBackedUpDeviceSnapShotIsObsolete(_ identityManagerImplementation: ObvIdentityManager.ObvIdentityManagerImplementation) async {
        
        guard let obvBackupManagerNew else {
            assert(self.appType != .mainApp)
            return
        }
        
        let flowId = FlowIdentifier()

        await obvBackupManagerNew.previousBackedUpDeviceSnapShotIsObsolete(flowId: flowId)
        
    }
    
    
    public func previousBackedUpProfileSnapShotIsObsolete(_ identityManagerImplementation: ObvIdentityManager.ObvIdentityManagerImplementation, ownedCryptoId: ObvTypes.ObvCryptoId) async {

        guard let obvBackupManagerNew else {
            assert(self.appType != .mainApp)
            return
        }
        
        let flowId = FlowIdentifier()
        
        await obvBackupManagerNew.previousBackupOfOwnedIdentityIsObsolete(ownedCryptoId: ownedCryptoId, flowId: flowId)
    }
    
    
    /// Called when an owned identity gets deleted from identity manager database
    public func anOwnedIdentityWasDeleted(_ identityManagerImplementation: ObvIdentityManagerImplementation, deletedOwnedCryptoId: ObvCryptoIdentity) async {
        Task { await engineCoordinator.anOwnedIdentityWasDeleted(deletedOwnedCryptoId: deletedOwnedCryptoId) }
        notifyAppThatOwnedIdentityWasDeleted()
    }
    
}
