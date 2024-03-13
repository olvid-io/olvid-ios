/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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


/// This operation should not be executed if `hasAnotherDeviceWithChannel` is false for the owned identity
final class PostDiscussionReadJSONEngineOperation: AsyncOperationWithSpecificReasonForCancel<PostDiscussionReadJSONEngineOperation.ReasonForCancel> {
    
    let obvEngine: ObvEngine
    let op: OperationProvidingDiscussionReadJSON
    
    init(op: OperationProvidingDiscussionReadJSON, obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        self.op = op
        super.init()
    }
    
    override func main() async {
        
        assert(op.isFinished)
        
        guard let discussionReadJSONToSend = op.discussionReadJSONToSend else { return finish() }
        guard let ownedCryptoId = op.ownedCryptoId else { assertionFailure(); return finish() }

        do {
            
            let persistedItemsJSON = PersistedItemJSON(discussionRead: discussionReadJSONToSend)
            let payload = try persistedItemsJSON.jsonEncode()
            
            _ = try obvEngine.post(messagePayload: payload,
                                   extendedPayload: nil,
                                   withUserContent: false,
                                   isVoipMessageForStartingCall: false,
                                   attachmentsToSend: [],
                                   toContactIdentitiesWithCryptoId: Set(),
                                   ofOwnedIdentityWithCryptoId: ownedCryptoId,
                                   alsoPostToOtherOwnedDevices: true)
            
            return finish()
                
            
        } catch {
            return cancel(withReason: .someError(error: error))
        }

    }
        
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case someError(error: Error)
        
        var logType: OSLogType {
            return .fault
        }
        
        var errorDescription: String? {
            switch self {
            case .someError(error: let error):
                return "Error: \(error.localizedDescription)"
            }
        }
        
    }

}


protocol OperationProvidingDiscussionReadJSON: Operation {
    
    var ownedCryptoId: ObvCryptoId? { get }
    var discussionReadJSONToSend: DiscussionReadJSON? { get }
    
}
