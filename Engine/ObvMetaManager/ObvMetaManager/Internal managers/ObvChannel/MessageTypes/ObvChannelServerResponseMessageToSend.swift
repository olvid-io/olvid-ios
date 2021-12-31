/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import ObvEncoder
import ObvCrypto
import ObvTypes
import OlvidUtils


public struct ObvChannelServerResponseMessageToSend: ObvChannelMessageToSend {
    
    public let messageType = ObvChannelMessageType.ServerResponse
    public let channelType: ObvChannelSendChannelType
    public let encodedElements: ObvEncoded
    public let responseType: ResponseType
    public let flowId: FlowIdentifier
    public let serverTimestamp: Date

    public init(toOwnedIdentity ownedIdentity: ObvCryptoIdentity, serverTimestamp: Date, responseType: ResponseType, encodedElements: ObvEncoded, flowId: FlowIdentifier) {
        self.channelType = .Local(ownedIdentity: ownedIdentity)
        self.encodedElements = encodedElements
        self.responseType = responseType
        self.flowId = flowId
        self.serverTimestamp = serverTimestamp
    }

}

// MARK: - QueryType

extension ObvChannelServerResponseMessageToSend {
    
    public enum ResponseType {
        case deviceDiscovery(of: ObvCryptoIdentity, deviceUids: [UID])
        case putUserData
        case getUserData(of: ObvCryptoIdentity, userDataPath: String)
        case checkKeycloakRevocation(verificationSuccessful: Bool)

        public func getEncodedInputs() -> [ObvEncoded] {
            switch self {
            case .deviceDiscovery(of: _, deviceUids: let deviceUids):
                let listOfEncodedUids = deviceUids.map { $0.encode() }
                return [listOfEncodedUids.encode()]
            case .putUserData:
                return []
            case .getUserData(of: _, userDataPath: let userDataPath):
                return [userDataPath.encode()]
            case .checkKeycloakRevocation(verificationSuccessful: let verificationSuccessful):
                return [verificationSuccessful.encode()]
            }
        }
    }
}
