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
    
    public var isWebSocket: Bool {
        switch self.queryType {
        case .deviceDiscovery,
                .putUserData,
                .getUserData,
                .checkKeycloakRevocation,
                .createGroupBlob,
                .getGroupBlob,
                .deleteGroupBlob,
                .putGroupLog,
                .requestGroupBlobLock,
                .updateGroupBlob,
                .getKeycloakData,
                .ownedDeviceDiscovery,
                .setOwnedDeviceName,
                .deactivateOwnedDevice,
                .setUnexpiringOwnedDevice,
                .uploadPreKeyForCurrentDevice:
            return false
        case .sourceGetSessionNumber,
                .sourceWaitForTargetConnection,
                .targetSendEphemeralIdentity,
                .transferRelay,
                .closeWebsocketConnection,
                .transferWait:
            return true
        }
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
        case getKeycloakData(serverURL: URL, serverLabel: UID)
        case ownedDeviceDiscovery
        case setOwnedDeviceName(ownedDeviceUID: UID, encryptedOwnedDeviceName: EncryptedData, isCurrentDevice: Bool)
        case deactivateOwnedDevice(ownedDeviceUID: UID, isCurrentDevice: Bool)
        case setUnexpiringOwnedDevice(ownedDeviceUID: UID)
        case sourceGetSessionNumber(protocolInstanceUID: UID)
        case sourceWaitForTargetConnection(protocolInstanceUID: UID)
        case targetSendEphemeralIdentity(protocolInstanceUID: UID, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, payload: Data)
        case transferRelay(protocolInstanceUID: UID, connectionIdentifier: String, payload: Data, thenCloseWebSocket: Bool)
        case transferWait(protocolInstanceUID: UID, connectionIdentifier: String)
        case closeWebsocketConnection(protocolInstanceUID: UID)
        case uploadPreKeyForCurrentDevice(deviceBlobOnServerToUpload: DeviceBlobOnServer)


        
        public var isCheckKeycloakRevocation: Bool {
            switch self {
            case .checkKeycloakRevocation:
                return true
            default: return false
            }
        }
        

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
            case .getKeycloakData:
                return 10
            case .ownedDeviceDiscovery:
                return 11
            case .setOwnedDeviceName:
                return 12
            case .deactivateOwnedDevice:
                return 13
            case .setUnexpiringOwnedDevice:
                return 14
            case .sourceGetSessionNumber:
                return 15
            case .sourceWaitForTargetConnection:
                return 16
            case .targetSendEphemeralIdentity:
                return 17
            case .transferRelay:
                return 18
            case .transferWait:
                return 19
            case .closeWebsocketConnection:
                return 20
            case .uploadPreKeyForCurrentDevice:
                return 21
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
            case .getKeycloakData(serverURL: let serverURL, serverLabel: let serverLabel):
                return [rawValue, serverURL, serverLabel].obvEncode()
            case .ownedDeviceDiscovery:
                return [rawValue].obvEncode()
            case .setOwnedDeviceName(ownedDeviceUID: let ownedDeviceUID, encryptedOwnedDeviceName: let encryptedOwnedDeviceName, isCurrentDevice: let isCurrentDevice):
                return [rawValue.obvEncode(), ownedDeviceUID.obvEncode(), encryptedOwnedDeviceName.obvEncode(), isCurrentDevice.obvEncode()].obvEncode()
            case .deactivateOwnedDevice(ownedDeviceUID: let ownedDeviceUID, isCurrentDevice: let isCurrentDevice):
                return [rawValue.obvEncode(), ownedDeviceUID.obvEncode(), isCurrentDevice.obvEncode()].obvEncode()
            case .setUnexpiringOwnedDevice(ownedDeviceUID: let ownedDeviceUID):
                return [rawValue.obvEncode(), ownedDeviceUID.obvEncode()].obvEncode()
            case .sourceGetSessionNumber(protocolInstanceUID: let protocolInstanceUID):
                return [rawValue, protocolInstanceUID].obvEncode()
            case .sourceWaitForTargetConnection(protocolInstanceUID: let protocolInstanceUID):
                return [rawValue, protocolInstanceUID].obvEncode()
            case .targetSendEphemeralIdentity(protocolInstanceUID: let protocolInstanceUID, transferSessionNumber: let transferSessionNumber, payload: let payload):
                return [rawValue, protocolInstanceUID, transferSessionNumber, payload].obvEncode()
            case .transferRelay(protocolInstanceUID: let protocolInstanceUID, connectionIdentifier: let connectionIdentifier, payload: let payload, thenCloseWebSocket: let thenCloseWebSocket):
                return [rawValue, protocolInstanceUID, connectionIdentifier, payload, thenCloseWebSocket].obvEncode()
            case .transferWait(protocolInstanceUID: let protocolInstanceUID, connectionIdentifier: let connectionIdentifier):
                return [rawValue, protocolInstanceUID, connectionIdentifier].obvEncode()
            case .closeWebsocketConnection(protocolInstanceUID: let protocolInstanceUID):
                return [rawValue, protocolInstanceUID].obvEncode()
            case .uploadPreKeyForCurrentDevice(deviceBlobOnServerToUpload: let deviceBlobOnServerToUpload):
                return [rawValue, deviceBlobOnServerToUpload].obvEncode()
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
            case 10:
                guard listOfEncoded.count == 3 else { assertionFailure(); return nil }
                guard let serverURL = URL(listOfEncoded[1]) else { assertionFailure(); return nil }
                guard let serverLabel = UID(listOfEncoded[2]) else { assertionFailure(); return nil }
                self = .getKeycloakData(serverURL: serverURL, serverLabel: serverLabel)
            case 11:
                guard listOfEncoded.count == 1 else { return nil }
                self = .ownedDeviceDiscovery
            case 12:
                guard listOfEncoded.count == 4 else { return nil }
                guard let ownedDeviceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
                guard let encryptedOwnedDeviceName = EncryptedData(listOfEncoded[2]) else { assertionFailure(); return nil }
                guard let isCurrentDevice = Bool(listOfEncoded[3]) else { assertionFailure(); return nil }
                self = .setOwnedDeviceName(ownedDeviceUID: ownedDeviceUID, encryptedOwnedDeviceName: encryptedOwnedDeviceName, isCurrentDevice: isCurrentDevice)
            case 13:
                guard listOfEncoded.count == 3 else { return nil }
                guard let ownedDeviceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
                guard let isCurrentDevice = Bool(listOfEncoded[2]) else { assertionFailure(); return nil }
                self = .deactivateOwnedDevice(ownedDeviceUID: ownedDeviceUID, isCurrentDevice: isCurrentDevice)
            case 14:
                guard listOfEncoded.count == 2 || listOfEncoded.count == 3 else { return nil } // 3, for legacy reasons
                guard let ownedDeviceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
                self = .setUnexpiringOwnedDevice(ownedDeviceUID: ownedDeviceUID)
            case 15:
                guard listOfEncoded.count == 2 else { return nil }
                guard let protocolInstanceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
                self = .sourceGetSessionNumber(protocolInstanceUID: protocolInstanceUID)
            case 16:
                guard listOfEncoded.count == 2 else { return nil }
                guard let protocolInstanceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
                self = .sourceWaitForTargetConnection(protocolInstanceUID: protocolInstanceUID)
            case 17:
                guard listOfEncoded.count == 4 else { return nil }
                guard let protocolInstanceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
                guard let transferSessionNumber = ObvOwnedIdentityTransferSessionNumber(listOfEncoded[2]) else { assertionFailure(); return nil }
                guard let payload = Data(listOfEncoded[3]) else { assertionFailure(); return nil }
                self = .targetSendEphemeralIdentity(protocolInstanceUID: protocolInstanceUID, transferSessionNumber: transferSessionNumber, payload: payload)
            case 18:
                guard listOfEncoded.count == 5 else { return nil }
                guard let protocolInstanceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
                guard let connectionIdentifier = String(listOfEncoded[2]) else { assertionFailure(); return nil }
                guard let payload = Data(listOfEncoded[3]) else { assertionFailure(); return nil }
                guard let thenCloseWebSocket = Bool(listOfEncoded[4]) else { assertionFailure(); return nil }
                self = .transferRelay(protocolInstanceUID: protocolInstanceUID, connectionIdentifier: connectionIdentifier, payload: payload, thenCloseWebSocket: thenCloseWebSocket)
            case 19:
                guard listOfEncoded.count == 3 else { return nil }
                guard let protocolInstanceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
                guard let connectionIdentifier = String(listOfEncoded[2]) else { assertionFailure(); return nil }
                self = .transferWait(protocolInstanceUID: protocolInstanceUID, connectionIdentifier: connectionIdentifier)
            case 20:
                guard listOfEncoded.count == 2 else { return nil }
                guard let protocolInstanceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
                self = .closeWebsocketConnection(protocolInstanceUID: protocolInstanceUID)
            case 21:
                guard listOfEncoded.count == 2 else { return nil }
                guard let deviceBlobOnServerToUpload = DeviceBlobOnServer(listOfEncoded[1]) else { assertionFailure(); return nil }
                self = .uploadPreKeyForCurrentDevice(deviceBlobOnServerToUpload: deviceBlobOnServerToUpload)
            default:
                assertionFailure()
                return nil
            }
        }
        
    }

}


extension ServerQuery.QueryType: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        switch self {
        case .deviceDiscovery:
            return "deviceDiscovery"
        case .putUserData:
            return "putUserData"
        case .getUserData:
            return "getUserData"
        case .checkKeycloakRevocation:
            return "checkKeycloakRevocation"
        case .createGroupBlob:
            return "createGroupBlob"
        case .getGroupBlob:
            return "getGroupBlob"
        case .deleteGroupBlob:
            return "deleteGroupBlob"
        case .putGroupLog:
            return "putGroupLog"
        case .requestGroupBlobLock:
            return "requestGroupBlobLock"
        case .updateGroupBlob:
            return "updateGroupBlob"
        case .getKeycloakData:
            return "getKeycloakData"
        case .ownedDeviceDiscovery:
            return "ownedDeviceDiscovery"
        case .setOwnedDeviceName:
            return "setOwnedDeviceName"
        case .deactivateOwnedDevice:
            return "deactivateOwnedDevice"
        case .setUnexpiringOwnedDevice:
            return "setUnexpiringOwnedDevice"
        case .sourceGetSessionNumber:
            return "sourceGetSessionNumber"
        case .sourceWaitForTargetConnection:
            return "sourceWaitForTargetConnection"
        case .targetSendEphemeralIdentity:
            return "targetSendEphemeralIdentity"
        case .transferRelay:
            return "transferRelay"
        case .transferWait:
            return "transferWait"
        case .closeWebsocketConnection:
            return "closeWebsocketConnection"
        case .uploadPreKeyForCurrentDevice:
            return "uploadPreKeyForCurrentDevice"
        }
    }
    
}


extension ServerQuery: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        return "ServerQuery<\(ownedIdentity.debugDescription),\(queryType.debugDescription)>"
    }
    
}
