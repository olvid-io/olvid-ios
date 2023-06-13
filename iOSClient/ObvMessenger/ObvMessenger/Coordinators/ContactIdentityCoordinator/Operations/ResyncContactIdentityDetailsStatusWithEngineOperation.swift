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
import ObvEngine
import ObvUICoreData


final class ResyncContactIdentityDetailsStatusWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<ResyncContactIdentityDetailsStatusWithEngineOperationReasonForCancel> {

    let ownedCryptoId: ObvCryptoId
    let contactCryptoId: ObvCryptoId
    let obvEngine: ObvEngine

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "ResyncContactIdentityDetailsStatusWithEngineOperation")
    
    init(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, obvEngine: ObvEngine) {
        self.ownedCryptoId = ownedCryptoId
        self.contactCryptoId = contactCryptoId
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        let obvContactIdentity: ObvContactIdentity
        do {
            obvContactIdentity = try obvEngine.getContactIdentity(with: contactCryptoId, ofOwnedIdentityWith: ownedCryptoId)
        } catch {
            os_log("While trying to re-sync a persisted contact, we could not find her in the engine", log: Self.log, type: .fault)
            return cancel(withReason: .couldNotGetObvContactIdentityFromEngine)
        }

        obvContext.performAndWait {
            
            do {
                
                guard let persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: obvContactIdentity, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedContact)
                }
                guard let receivedPublishedDetails = obvContactIdentity.publishedIdentityDetails else { return }
                if obvContactIdentity.trustedIdentityDetails == receivedPublishedDetails {
                    persistedContactIdentity.setContactStatus(to: .noNewPublishedDetails)
                } else {
                    persistedContactIdentity.setContactStatus(to: .unseenPublishedDetails)
                }

            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }

    }
}



enum ResyncContactIdentityDetailsStatusWithEngineOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotGetObvContactIdentityFromEngine
    case couldNotFindPersistedContact

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .contextIsNil,
             .couldNotFindPersistedContact,
             .couldNotGetObvContactIdentityFromEngine:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindPersistedContact:
            return "Could not find contact"
        case .couldNotGetObvContactIdentityFromEngine:
            return "Could not get ObvContactIdentity from engine"
        }
    }

}
