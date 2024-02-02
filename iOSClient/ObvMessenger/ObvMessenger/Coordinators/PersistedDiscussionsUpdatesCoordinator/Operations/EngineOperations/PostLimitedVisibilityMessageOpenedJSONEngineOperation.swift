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
import ObvEngine
import ObvUICoreData
import ObvTypes
import CoreData


final class PostLimitedVisibilityMessageOpenedJSONEngineOperation: ContextualOperationWithSpecificReasonForCancel<PostLimitedVisibilityMessageOpenedJSONEngineOperation.ReasonForCancel> {
    
    let obvEngine: ObvEngine
    let op: OperationProvidingLimitedVisibilityMessageOpenedJSONs
    
    init(op: OperationProvidingLimitedVisibilityMessageOpenedJSONs, obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        self.op = op
        super.init()
    }
    

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        assert(op.isFinished)
        
        guard !op.isCancelled else { return }
        guard !op.limitedVisibilityMessageOpenedJSONsToSend.isEmpty else { return }
        guard let ownedCryptoId = op.ownedCryptoId else { assertionFailure(); return }

        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            guard ownedIdentity.hasAnotherDeviceWithChannel else {
                // No need to propagate the fact that we opened a message with limited visibility since we don't have any other owned device with a secure channel
                return
            }
                        
            for limitedVisibilityMessageOpenedJSON in op.limitedVisibilityMessageOpenedJSONsToSend {
                
                let persistedItemsJSON = PersistedItemJSON(limitedVisibilityMessageOpenedJSON: limitedVisibilityMessageOpenedJSON)
                let payload = try persistedItemsJSON.jsonEncode()
                
                _ = try obvEngine.post(messagePayload: payload,
                                       extendedPayload: nil,
                                       withUserContent: false,
                                       isVoipMessageForStartingCall: false,
                                       attachmentsToSend: [],
                                       toContactIdentitiesWithCryptoId: Set(),
                                       ofOwnedIdentityWithCryptoId: ownedCryptoId,
                                       alsoPostToOtherOwnedDevices: true)
                
            }
            
        } catch {
            return cancel(withReason: .someError(error: error))
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case couldNotFindOwnedIdentity
        case someError(error: Error)
        
        var logType: OSLogType {
            return .fault
        }
        
        var errorDescription: String? {
            switch self {
            case .someError(error: let error):
                return "Error: \(error.localizedDescription)"
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            }
        }
        
    }

}


protocol OperationProvidingLimitedVisibilityMessageOpenedJSONs: Operation {
    
    var ownedCryptoId: ObvCryptoId? { get }
    var limitedVisibilityMessageOpenedJSONsToSend: [LimitedVisibilityMessageOpenedJSON] { get }
    
}
