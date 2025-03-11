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
import ObvTypes
import ObvUICoreData
import CoreData
import ObvCrypto


final class SendWebRTCMessageOperation: AsyncOperationWithSpecificReasonForCancel<SendWebRTCMessageOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let webrtcMessage: WebRTCMessageJSON
    private let recipient: Recipient
    private let obvEngine: ObvEngine
    private let logger: Logger
    
    enum Recipient {
        case allContactDevices(contactIdentifier: ObvContactIdentifier, forStartingCall: Bool, deviceUIDToExclude: UID?)
        case singleContactDevice(contactDeviceIdentifier: ObvContactDeviceIdentifier)
    }
    
    init(webrtcMessage: WebRTCMessageJSON, recipient: Recipient, obvEngine: ObvEngine, logger: Logger) {
        self.webrtcMessage = webrtcMessage
        self.recipient = recipient
        self.obvEngine = obvEngine
        self.logger = logger
        super.init()
    }
    
    override func main() async {
            
        let messageToSend = PersistedItemJSON(webrtcMessage: webrtcMessage)
        let webrtcMessageType = webrtcMessage.messageType
        
        let messagePayload: Data
        do {
            messagePayload = try messageToSend.jsonEncode()
        } catch {
            logger.fault("☎️ We failed to post a \(webrtcMessageType) WebRTCMessage")
            return cancel(withReason: .couldNotEncodeMessageToSend)
        }
        
        switch recipient {

        case .allContactDevices(contactIdentifier: let contactIdentifier, forStartingCall: let forStartingCall, deviceUIDToExclude: let deviceUIDToExclude):

            let messageIdentifierForContactToWhichTheMessageWasSent: [ObvCryptoId : Data]
            
            let contactDeviceIdentifiersToExclude: Set<ObvContactDeviceIdentifier>
            if let deviceUIDToExclude {
                contactDeviceIdentifiersToExclude = Set([ObvContactDeviceIdentifier(contactIdentifier: contactIdentifier, deviceUID: deviceUIDToExclude)])
            } else {
                contactDeviceIdentifiersToExclude = Set([])
            }

            do {
                messageIdentifierForContactToWhichTheMessageWasSent = try obvEngine.post(
                    messagePayload: messagePayload,
                    extendedPayload: nil,
                    withUserContent: false,
                    isVoipMessageForStartingCall: forStartingCall, // True only for starting a call
                    attachmentsToSend: [],
                    toContactIdentitiesWithCryptoId: [contactIdentifier.contactCryptoId],
                    ofOwnedIdentityWithCryptoId: contactIdentifier.ownedCryptoId,
                    contactDeviceIdentifiersToExclude: contactDeviceIdentifiersToExclude,
                    alsoPostToOtherOwnedDevices: false,
                    completionHandler: nil)
            } catch {
                logger.fault("☎️ We failed to post a \(webrtcMessageType) WebRTCMessage")
                return cancel(withReason: .engineFailedToSendMessage(error: error))
            }
            
            if messageIdentifierForContactToWhichTheMessageWasSent[contactIdentifier.contactCryptoId] != nil {
                logger.info("☎️ We posted a new \(webrtcMessageType) \(messageIdentifierForContactToWhichTheMessageWasSent) WebRTCMessage for call %{public}s")
            } else {
                logger.fault("☎️ We failed to post a \(webrtcMessageType) WebRTCMessage")
                assertionFailure()
            }

        case .singleContactDevice(contactDeviceIdentifier: let contactDeviceIdentifier):

            do {
                _ = try obvEngine.post(
                    messagePayload: messagePayload,
                    toContactDevice: contactDeviceIdentifier)
            } catch {
                logger.fault("☎️ We failed to post a \(webrtcMessageType) WebRTCMessage")
                return cancel(withReason: .engineFailedToSendMessage(error: error))
            }

            logger.info("☎️ We posted a new \(webrtcMessageType) WebRTCMessage for call %{public}s to a single contact device")

        }

        return finish()
        
    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {
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

}
