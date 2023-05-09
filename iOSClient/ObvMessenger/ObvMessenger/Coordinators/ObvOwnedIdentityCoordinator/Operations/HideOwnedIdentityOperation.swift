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
import os.log
import ObvTypes


final class HideOwnedIdentityOperation: ContextualOperationWithSpecificReasonForCancel<HideOwnedIdentityOperationReasonForCancel> {

    private let ownedCryptoId: ObvCryptoId
    private let password: String
    
    init(ownedCryptoId: ObvCryptoId, password: String) {
        self.ownedCryptoId = ownedCryptoId
        self.password = password
        super.init()
    }
    
    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        guard password.count >= ObvMessengerConstants.minimumLengthOfPasswordForHiddenProfiles else {
            return cancel(withReason: .passwordTooShort)
        }
        
        obvContext.performAndWait {
            do {
                let nonHiddenOwnedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: obvContext.context)
                guard let ownedIdentity = nonHiddenOwnedIdentities.first(where: { $0.cryptoId == ownedCryptoId }) else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }
                guard nonHiddenOwnedIdentities.count > 1 else {
                    return cancel(withReason: .cannotHideTheSoleOwnedIdentity)
                }
                try ownedIdentity.hideProfileWithPassword(password)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
    }
}


enum HideOwnedIdentityOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)
    case passwordTooShort
    case couldNotFindOwnedIdentity
    case cannotHideTheSoleOwnedIdentity
    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil, .passwordTooShort, .couldNotFindOwnedIdentity, .cannotHideTheSoleOwnedIdentity:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .passwordTooShort:
            return "The password is too short"
        case .couldNotFindOwnedIdentity:
            return "Could not find owned identity"
        case .cannotHideTheSoleOwnedIdentity:
            return "Cannot hide the sole owned identity"
        }
    }

}
