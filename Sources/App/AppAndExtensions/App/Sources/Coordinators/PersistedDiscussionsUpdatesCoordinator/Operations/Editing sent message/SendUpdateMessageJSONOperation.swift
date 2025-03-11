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
import OSLog
import ObvEngine
import OlvidUtils
import ObvTypes
import ObvUICoreData
import ObvAppCoreConstants


/// This operation is typically used when the user decides to update the text body of one of here sent messages or the location.
final class SendUpdateMessageJSONOperation: AsyncOperationWithSpecificReasonForCancel<SendUpdateMessageJSONOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let obvEngine: ObvEngine
    private let updateMessageJSONToSend: UpdateMessageJSONToSend
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SendUpdateMessageJSONOperation.self))

    init(updateMessageJSONToSend: UpdateMessageJSONToSend, obvEngine: ObvEngine) {
        self.updateMessageJSONToSend = updateMessageJSONToSend
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main() async {
        
        let itemJSON: PersistedItemJSON = PersistedItemJSON(updateMessageJSON: updateMessageJSONToSend.updateMessageJSON)
        
        // Create a payload of the PersistedItemJSON we just created and send it.
        // We do not keep track of the message identifiers from engine.
        
        let payload: Data
        do {
            payload = try itemJSON.jsonEncode()
        } catch {
            return cancel(withReason: .failedToEncodePersistedItemJSON)
        }
        
        if !updateMessageJSONToSend.contactCryptoIds.isEmpty || updateMessageJSONToSend.hasAnotherDeviceWhichIsReachable {
            let obvEngine = self.obvEngine
            do {
                _ = try obvEngine.post(messagePayload: payload,
                                       extendedPayload: nil,
                                       withUserContent: true,
                                       isVoipMessageForStartingCall: false,
                                       attachmentsToSend: [],
                                       toContactIdentitiesWithCryptoId: updateMessageJSONToSend.contactCryptoIds,
                                       ofOwnedIdentityWithCryptoId: updateMessageJSONToSend.ownedCryptoId,
                                       alsoPostToOtherOwnedDevices: true)
            } catch {
                Self.logger.fault("Could not post message within engine: \(error.localizedDescription)")
                assertionFailure()
                return cancel(withReason: .couldNotPostMessageWithinEngine(error: error))
            }
        }
        
        return finish()
        
    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case failedToEncodePersistedItemJSON
        case couldNotPostMessageWithinEngine(error: Error)

        var logType: OSLogType {
            switch self {
            case .failedToEncodePersistedItemJSON, .couldNotPostMessageWithinEngine:
                 return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .failedToEncodePersistedItemJSON:
                return "We failed to encode the persisted item JSON"
            case .couldNotPostMessageWithinEngine(error: let error):
                return "Could not post message within engine: \(error.localizedDescription)"
            }
        }

    }

}
