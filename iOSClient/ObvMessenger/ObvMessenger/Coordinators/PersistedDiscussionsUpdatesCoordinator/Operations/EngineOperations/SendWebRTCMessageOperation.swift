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
import ObvTypes
import ObvUICoreData
import CoreData


final class SendWebRTCMessageOperation: ContextualOperationWithSpecificReasonForCancel<SendWebRTCMessageOperationReasonForCancel> {
    
    private let webrtcMessage: WebRTCMessageJSON
    private let contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>
    private let forStartingCall: Bool
    private let obvEngine: ObvEngine
    private let log: OSLog
    
    init(webrtcMessage: WebRTCMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, forStartingCall: Bool, obvEngine: ObvEngine, log: OSLog) {
        self.webrtcMessage = webrtcMessage
        self.contactID = contactID
        self.forStartingCall = forStartingCall
        self.obvEngine = obvEngine
        self.log = log
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let messageToSend = PersistedItemJSON(webrtcMessage: webrtcMessage)
        
        let messagePayload: Data
        do {
            messagePayload = try messageToSend.jsonEncode()
        } catch {
            os_log("☎️ We failed to post a %{public}s WebRTCMessage", log: log, type: .fault, String(describing: webrtcMessage.messageType))
            return cancel(withReason: .couldNotEncodeMessageToSend)
        }
        
        do {
            
            guard let contact = try PersistedObvContactIdentity.get(objectID: contactID, within: obvContext.context) else {
                os_log("☎️ We failed to post a %{public}s WebRTCMessage", log: log, type: .fault, String(describing: webrtcMessage.messageType))
                return cancel(withReason: .couldNotFindContact)
            }
            let contactCryptoId = contact.cryptoId
            guard let ownedCryptoId = contact.ownedIdentity?.cryptoId else { return }
            let messageIdentifierForContactToWhichTheMessageWasSent: [ObvCryptoId : Data]
            do {
                messageIdentifierForContactToWhichTheMessageWasSent = try obvEngine.post(
                    messagePayload: messagePayload,
                    extendedPayload: nil,
                    withUserContent: false,
                    isVoipMessageForStartingCall: forStartingCall, // True only for starting a call
                    attachmentsToSend: [],
                    toContactIdentitiesWithCryptoId: [contactCryptoId],
                    ofOwnedIdentityWithCryptoId: ownedCryptoId,
                    alsoPostToOtherOwnedDevices: false,
                    completionHandler: nil)
            } catch {
                os_log("☎️ We failed to post a %{public}s WebRTCMessage", log: log, type: .fault, String(describing: webrtcMessage.messageType))
                return cancel(withReason: .engineFailedToSendMessage(error: error))
            }
            if messageIdentifierForContactToWhichTheMessageWasSent[contactCryptoId] != nil {
                os_log("☎️ We posted a new %{public}s WebRTCMessage for call %{public}s", log: log, type: .info, String(describing: webrtcMessage.messageType), String(webrtcMessage.callIdentifier))
            } else {
                os_log("☎️ We failed to post a %{public}s WebRTCMessage", log: log, type: .fault, String(describing: webrtcMessage.messageType))
                assertionFailure()
            }
            
        } catch {
            os_log("☎️ We failed to post a %{public}s WebRTCMessage", log: log, type: .fault, String(describing: webrtcMessage.messageType))
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

}


enum SendWebRTCMessageOperationReasonForCancel: LocalizedErrorWithLogType {
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotEncodeMessageToSend
    case couldNotFindContact
    case engineFailedToSendMessage(error: Error)

    var logType: OSLogType { .fault }

    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .contextIsNil:
            return "The context is not set"
        case .couldNotEncodeMessageToSend:
            return "Could not encode message to send"
        case .couldNotFindContact:
            return "Could not find contact"
        case .engineFailedToSendMessage(error: let error):
            return "Engine failed to send message: \(error.localizedDescription)"
        }
    }

}
