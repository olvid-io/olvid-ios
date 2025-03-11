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


/// The operations deactivates the owned identity, deletes all the devices of the contacts of this owned identity and deletes all the oblivious channels between the current device of this owned identity (including channels with other owned devices).
/// Note that we do not delete other owned devices, we only delete any oblivious we have with them.
final class DeactivateOwnedIdentityAndMore: ContextualOperationWithSpecificReasonForCancel<DeactivateOwnedIdentityAndMore.ReasonForCancel>, @unchecked Sendable {
    
    private let ownedCryptoIdentity: ObvCryptoIdentity
    private let identityDelegate: ObvIdentityDelegate
    private let channelDelegate: ObvChannelDelegate
    
    init(ownedCryptoIdentity: ObvCryptoIdentity, identityDelegate: ObvIdentityDelegate, channelDelegate: ObvChannelDelegate) {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.identityDelegate = identityDelegate
        self.channelDelegate = channelDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        // Make sure the owned identity still exists as this operation may be called during the deletion of an owned identity
        do {
            guard try identityDelegate.isOwned(ownedCryptoIdentity, within: obvContext) else {
                return
            }
        } catch {
            assertionFailure()
            return cancel(withReason: .identityDelegateError(error: error))
        }
        
        let currentDeviceUid: UID
        do {
            currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
            try identityDelegate.deactivateOwnedIdentityAndDeleteContactDevices(ownedIdentity: ownedCryptoIdentity, within: obvContext)
        } catch {
            assertionFailure()
            return cancel(withReason: .identityDelegateError(error: error))
        }
        
        do {
            try channelDelegate.deleteAllObliviousChannelsWithTheCurrentDeviceUid(currentDeviceUid, within: obvContext)
        } catch {
            assertionFailure()
            return cancel(withReason: .channelDelegate(error: error))
        }

    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case identityDelegateError(error: Error)
        case channelDelegate(error: Error)
        case contextIsNil
        
        public var logType: OSLogType {
            switch self {
            case .coreDataError,
                    .channelDelegate,
                    .identityDelegateError,
                    .contextIsNil:
                return .fault
            }
        }
        
        public var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "Context is nil"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .identityDelegateError(error: let error):
                return "Identity delegate error: \(error.localizedDescription)"
            case .channelDelegate(error: let error):
                return "Channel delegate error: \(error.localizedDescription)"
            }
        }
        
        
    }
    
}
