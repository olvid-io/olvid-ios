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
import ObvEncoder
import ObvCrypto
import CryptoKit

/// This structure allows to transfer a server query from the engine to the server. This is for example used to ask the server about the list of device uids of a given identity.
public struct ObvChannelServerQueryMessageToSend: ObvChannelMessageToSend {
    
    public let messageType = ObvChannelMessageType.ServerQuery
    public let channelType: ObvChannelSendChannelType
    public let encodedElements: ObvEncoded
    public let queryType: QueryType

    // The toIdentity is one of our own, used to receive the server response
    public init(ownedIdentity: ObvCryptoIdentity, serverQueryType: QueryType, encodedElements: ObvEncoded) {
        self.channelType = .ServerQuery(ownedIdentity: ownedIdentity)
        self.encodedElements = encodedElements
        self.queryType = serverQueryType
    }
    
}


// MARK: - QueryType

extension ObvChannelServerQueryMessageToSend {
    
    public enum QueryType {
        case deviceDiscovery(of: ObvCryptoIdentity)
        case putUserData(label: UID, dataURL: URL, dataKey: AuthenticatedEncryptionKey)
        case getUserData(of: ObvCryptoIdentity, label: UID)
        case checkKeycloakRevocation(keycloakServerUrl: URL, signedContactDetails: String)
        case createGroupBlob(groupIdentifier: GroupV2.Identifier, serverAuthenticationPublicKey: PublicKeyForAuthentication, encryptedBlob: EncryptedData)
        case getGroupBlob(groupIdentifier: GroupV2.Identifier)
        case deleteGroupBlob(groupIdentifier: GroupV2.Identifier, signature: Data)
        case putGroupLog(groupIdentifier: GroupV2.Identifier, querySignature: Data)
        case requestGroupBlobLock(groupIdentifier: GroupV2.Identifier, lockNonce: Data, signature: Data)
        case updateGroupBlob(groupIdentifier: GroupV2.Identifier, encodedServerAdminPublicKey: ObvEncoded, encryptedBlob: EncryptedData, lockNonce: Data, signature: Data)
    }
    
}
