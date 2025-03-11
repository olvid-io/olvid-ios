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


final class SendOwnedWebRTCMessageOperation: ContextualOperationWithSpecificReasonForCancel<SendOwnedWebRTCMessageOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let webrtcMessage: WebRTCMessageJSON
    private let ownedCryptoId: ObvCryptoId
    private let obvEngine: ObvEngine
    
    init(webrtcMessage: WebRTCMessageJSON, ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine) {
        self.webrtcMessage = webrtcMessage
        self.ownedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        super.init()
    }
    

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            guard ownedIdentity.hasAnotherDeviceWhichIsReachable else {
                return
            }
                        
            let messageToSend = PersistedItemJSON(webrtcMessage: webrtcMessage)
            let messagePayload = try messageToSend.jsonEncode()

            _ = try obvEngine.post(
                messagePayload: messagePayload,
                extendedPayload: nil,
                withUserContent: false,
                isVoipMessageForStartingCall: false,
                attachmentsToSend: [],
                toContactIdentitiesWithCryptoId: [],
                ofOwnedIdentityWithCryptoId: ownedCryptoId,
                alsoPostToOtherOwnedDevices: true,
                completionHandler: nil)

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
