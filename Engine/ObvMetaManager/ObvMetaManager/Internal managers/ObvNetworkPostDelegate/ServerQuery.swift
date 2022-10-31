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
import ObvCrypto
import ObvEncoder
import ObvTypes

public struct ServerQuery {
    
    public let ownedIdentity: ObvCryptoIdentity
    public let encodedElements: ObvEncoded
    public let queryType: QueryType
    
    public init(ownedIdentity: ObvCryptoIdentity, queryType: QueryType, encodedElements: ObvEncoded) {
        self.ownedIdentity = ownedIdentity
        self.queryType = queryType
        self.encodedElements = encodedElements
    }
}

extension ServerQuery {
    
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


        private var rawValue: Int {
            switch self {
            case .deviceDiscovery:
                return 0
            case .putUserData:
                return 1
            case .getUserData:
                return 2
            case .checkKeycloakRevocation:
                return 3
            case .createGroupBlob:
                return 4
            case .getGroupBlob:
                return 5
            case .deleteGroupBlob:
                return 6
            case .putGroupLog:
                return 7
            case .requestGroupBlobLock:
                return 8
            case .updateGroupBlob:
                return 9
            }
        }
        
        public func obvEncode() -> ObvEncoded {
            switch self {
            case .deviceDiscovery(of: let identity):
                return [rawValue, identity].obvEncode()
            case .putUserData(label: let label, dataURL: let dataURL, dataKey: let dataKey):
                return [rawValue, label, dataURL, dataKey].obvEncode()
            case .getUserData(of: let identity, label: let label):
                return [rawValue, identity, label].obvEncode()
            case .checkKeycloakRevocation(keycloakServerUrl: let keycloakServerUrl, signedContactDetails: let signedContactDetails):
                return [rawValue, keycloakServerUrl, signedContactDetails].obvEncode()
            case .createGroupBlob(groupIdentifier: let groupIdentifier, serverAuthenticationPublicKey: let serverAuthenticationPublicKey, encryptedBlob: let encryptedBlob):
                return [rawValue, groupIdentifier, serverAuthenticationPublicKey, encryptedBlob].obvEncode()
            case .getGroupBlob(groupIdentifier: let groupIdentifier):
                return [rawValue, groupIdentifier].obvEncode()
            case .deleteGroupBlob(groupIdentifier: let groupIdentifier, signature: let signature):
                return [rawValue, groupIdentifier, signature].obvEncode()
            case .putGroupLog(groupIdentifier: let groupIdentifier, querySignature: let querySignature):
                return [rawValue, groupIdentifier, querySignature].obvEncode()
            case .requestGroupBlobLock(groupIdentifier: let groupIdentifier, lockNonce: let lockNonce, signature: let signature):
                return [rawValue, groupIdentifier, lockNonce, signature].obvEncode()
            case .updateGroupBlob(groupIdentifier: let groupIdentifier, encodedServerAdminPublicKey: let encodedServerAdminPublicKey, encryptedBlob: let encryptedBlob, lockNonce: let lockNonce, signature: let signature):
                return [rawValue.obvEncode(), groupIdentifier.obvEncode(), encodedServerAdminPublicKey, encryptedBlob.obvEncode(), lockNonce.obvEncode(), signature.obvEncode()].obvEncode()
            }
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let listOfEncoded = [ObvEncoded](obvEncoded) else { return nil }
            guard let encodedRawValue = listOfEncoded.first else { return nil }
            guard let rawValue = Int(encodedRawValue) else { return nil }
            switch rawValue {
            case 0:
                guard listOfEncoded.count == 2 else { return nil }
                guard let identity = ObvCryptoIdentity(listOfEncoded[1]) else { return nil }
                self = .deviceDiscovery(of: identity)
            case 1:
                guard listOfEncoded.count == 4 else { return nil }
                guard let label = UID(listOfEncoded[1]) else { return nil }
                guard let dataURL = URL(listOfEncoded[2]) else { return nil }
                guard let dataKey = try? AuthenticatedEncryptionKeyDecoder.decode(listOfEncoded[3]) else { return nil }
                self = .putUserData(label: label, dataURL: dataURL, dataKey: dataKey)
            case 2:
                guard listOfEncoded.count == 3 else { return nil }
                guard let identity = ObvCryptoIdentity(listOfEncoded[1]) else { return nil }
                guard let label = UID(listOfEncoded[2]) else { return nil }
                self = .getUserData(of: identity, label: label)
            case 3:
                guard listOfEncoded.count == 3 else { return nil }
                guard let keycloakServerUrl = URL(listOfEncoded[1]) else { return nil }
                guard let signedContactDetails = String(listOfEncoded[2]) else { return nil }
                self = .checkKeycloakRevocation(keycloakServerUrl: keycloakServerUrl, signedContactDetails: signedContactDetails)
            case 4:
                guard listOfEncoded.count == 4 else { return nil }
                guard let groupIdentifier = GroupV2.Identifier(listOfEncoded[1]) else { return nil }
                guard let serverAuthenticationPublicKey = PublicKeyForAuthenticationDecoder.obvDecode(listOfEncoded[2]) else { return nil }
                guard let encryptedBlob = EncryptedData(listOfEncoded[3]) else { return nil }
                self = .createGroupBlob(groupIdentifier: groupIdentifier, serverAuthenticationPublicKey: serverAuthenticationPublicKey, encryptedBlob: encryptedBlob)
            case 5:
                guard listOfEncoded.count == 2 else { return nil }
                guard let groupIdentifier = GroupV2.Identifier(listOfEncoded[1]) else { return nil }
                self = .getGroupBlob(groupIdentifier: groupIdentifier)
            case 6:
                guard listOfEncoded.count == 3 else { return nil }
                guard let groupIdentifier = GroupV2.Identifier(listOfEncoded[1]) else { return nil }
                guard let signature = Data(listOfEncoded[2]) else { return nil }
                self = .deleteGroupBlob(groupIdentifier: groupIdentifier, signature: signature)
            case 7:
                guard listOfEncoded.count == 3 else { return nil }
                guard let groupIdentifier = GroupV2.Identifier(listOfEncoded[1]) else { return nil }
                guard let querySignature = Data(listOfEncoded[2]) else { return nil }
                self = .putGroupLog(groupIdentifier: groupIdentifier, querySignature: querySignature)
            case 8:
                guard listOfEncoded.count == 4 else { return nil }
                guard let groupIdentifier = GroupV2.Identifier(listOfEncoded[1]) else { return nil }
                guard let lockNonce = Data(listOfEncoded[2]) else { return nil }
                guard let signature = Data(listOfEncoded[3]) else { return nil }
                self = .requestGroupBlobLock(groupIdentifier: groupIdentifier, lockNonce: lockNonce, signature: signature)
            case 9:
                guard listOfEncoded.count == 6 else { return nil }
                guard let groupIdentifier = GroupV2.Identifier(listOfEncoded[1]) else { return nil }
                let encodedServerAdminPublicKey = listOfEncoded[2]
                guard let encryptedBlob = EncryptedData(listOfEncoded[3]) else { return nil }
                guard let lockNonce = Data(listOfEncoded[4]) else { return nil }
                guard let signature = Data(listOfEncoded[5]) else { return nil }
                self = .updateGroupBlob(groupIdentifier: groupIdentifier, encodedServerAdminPublicKey: encodedServerAdminPublicKey, encryptedBlob: encryptedBlob, lockNonce: lockNonce, signature: signature)
            default:
                assertionFailure()
                return nil
            }
        }
        
    }

}
