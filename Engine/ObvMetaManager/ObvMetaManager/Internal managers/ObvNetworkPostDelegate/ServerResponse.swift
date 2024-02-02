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
import ObvCrypto
import ObvEncoder
import ObvTypes

public struct ServerResponse {
    
    public let ownedIdentity: ObvCryptoIdentity
    public let encodedElements: ObvEncoded
    public let encodedInputs: ObvEncoded
    public let queryType: ResponseType
    public let backgroundActivityId: UUID?

    public init(ownedIdentity: ObvCryptoIdentity, queryType: ResponseType, encodedElements: ObvEncoded, encodedInputs: ObvEncoded, backgroundActivityId: UUID?) {
        self.ownedIdentity = ownedIdentity
        self.queryType = queryType
        self.encodedElements = encodedElements
        self.encodedInputs = encodedInputs
        self.backgroundActivityId = backgroundActivityId
    }
    
}

extension ServerResponse {
        
    public enum ResponseType {
        case deviceDiscovery(of: ObvCryptoIdentity, deviceUids: [UID])
        case putUserData
        case getUserData(result: GetUserDataResult)
        case checkKeycloakRevocation(verificationSuccessful: Bool)
        case createGroupBlob(uploadResult: UploadResult)
        case getGroupBlob(result: GetGroupBlobResult)
        case deleteGroupBlob(groupDeletionWasSuccessful: Bool)
        case putGroupLog
        case requestGroupBlobLock(result: RequestGroupBlobLockResult)
        case updateGroupBlob(uploadResult: UploadResult)
        case getKeycloakData(result: GetUserDataResult)
        case ownedDeviceDiscovery(encryptedOwnedDeviceDiscoveryResult: EncryptedData)
        case setOwnedDeviceName(success: Bool)
        case sourceGetSessionNumberMessage(result: SourceGetSessionNumberResult)
        case targetSendEphemeralIdentity(result: TargetSendEphemeralIdentityResult)
        case transferRelay(result: OwnedIdentityTransferRelayMessageResult)
        case transferWait(result: OwnedIdentityTransferWaitResult)
        case sourceWaitForTargetConnection(result: SourceWaitForTargetConnectionResult)

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
            case .sourceGetSessionNumberMessage:
                return 13
            case .targetSendEphemeralIdentity:
                return 14
            case .transferRelay:
                return 15
            case .transferWait:
                return 16
            case .sourceWaitForTargetConnection:
                return 17
            }
        }
        
        public func obvEncode() -> ObvEncoded {
            switch self {
            case .deviceDiscovery(of: let identity, deviceUids: let deviceUids):
                let listOfEncodedDeviceUids = deviceUids.map { $0.obvEncode() }
                return [rawValue.obvEncode(), identity.obvEncode(), listOfEncodedDeviceUids.obvEncode()].obvEncode()
            case .putUserData:
                return [rawValue.obvEncode()].obvEncode()
            case .getUserData(result: let result):
                return [rawValue.obvEncode(), result.obvEncode()].obvEncode()
            case .checkKeycloakRevocation(verificationSuccessful: let verificationSuccessful):
                return [rawValue.obvEncode(), verificationSuccessful.obvEncode()].obvEncode()
            case .createGroupBlob(uploadResult: let uploadResult):
                return [rawValue.obvEncode(), uploadResult.obvEncode()].obvEncode()
            case .getGroupBlob(let result):
                return [rawValue.obvEncode(), result.obvEncode()].obvEncode()
            case .deleteGroupBlob(let groupDeletionWasSuccessful):
                return [rawValue.obvEncode(), groupDeletionWasSuccessful.obvEncode()].obvEncode()
            case .putGroupLog:
                return [rawValue.obvEncode()].obvEncode()
            case .requestGroupBlobLock(let result):
                return [rawValue.obvEncode(), result.obvEncode()].obvEncode()
            case .updateGroupBlob(uploadResult: let uploadResult):
                return [rawValue.obvEncode(), uploadResult.obvEncode()].obvEncode()
            case .getKeycloakData(result: let result):
                return [rawValue.obvEncode(), result.obvEncode()].obvEncode()
            case .ownedDeviceDiscovery(encryptedOwnedDeviceDiscoveryResult: let encryptedOwnedDeviceDiscoveryResult):
                return [rawValue.obvEncode(), encryptedOwnedDeviceDiscoveryResult.obvEncode()].obvEncode()
            case .setOwnedDeviceName(success: let success):
                return [rawValue.obvEncode(), success.obvEncode()].obvEncode()
            case .sourceGetSessionNumberMessage(result: let result):
                return [rawValue.obvEncode(), result.obvEncode()].obvEncode()
            case .targetSendEphemeralIdentity(result: let result):
                return [rawValue.obvEncode(), result.obvEncode()].obvEncode()
            case .transferRelay(result: let result):
                return [rawValue.obvEncode(), result.obvEncode()].obvEncode()
            case .transferWait(result: let result):
                return [rawValue.obvEncode(), result.obvEncode()].obvEncode()
            case .sourceWaitForTargetConnection(result: let result):
                return [rawValue.obvEncode(), result.obvEncode()].obvEncode()
            }
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let listOfEncoded = [ObvEncoded](obvEncoded) else { return nil }
            guard let encodedRawValue = listOfEncoded.first else { return nil }
            guard let rawValue = Int(encodedRawValue) else { return nil }
            switch rawValue {
            case 0:
                guard listOfEncoded.count == 3 else { return nil }
                guard let identity = ObvCryptoIdentity(listOfEncoded[1]) else { return nil }
                guard let listOfEncodedDeviceUids = [ObvEncoded](listOfEncoded[2]) else { return nil }
                var deviceUids = [UID]()
                for encoded in listOfEncodedDeviceUids {
                    guard let deviceUid = UID(encoded) else { return nil }
                    deviceUids.append(deviceUid)
                }
                self = .deviceDiscovery(of: identity, deviceUids: deviceUids)
            case 1:
                self = .putUserData
            case 2:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = GetUserDataResult(listOfEncoded[1]) else { return nil }
                self = .getUserData(result: result)
            case 3:
                guard listOfEncoded.count == 2 else { return nil }
                guard let verificationSuccessful = Bool(listOfEncoded[1]) else { return nil }
                self = .checkKeycloakRevocation(verificationSuccessful: verificationSuccessful)
            case 4:
                guard listOfEncoded.count == 2 else { return nil }
                guard let uploadResult = UploadResult(listOfEncoded[1]) else { return nil }
                self = .createGroupBlob(uploadResult: uploadResult)
            case  5:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = GetGroupBlobResult(listOfEncoded[1]) else { assertionFailure(); return nil }
                self = .getGroupBlob(result: result)
            case 6:
                guard listOfEncoded.count == 2 else { return nil }
                guard let groupDeletionWasSuccessful = Bool(listOfEncoded[1]) else { assertionFailure(); return nil }
                self = .deleteGroupBlob(groupDeletionWasSuccessful: groupDeletionWasSuccessful)
            case 7:
                guard listOfEncoded.count == 1 else { return nil }
                self = .putGroupLog
            case 8:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = RequestGroupBlobLockResult(listOfEncoded[1]) else { assertionFailure(); return nil }
                self = .requestGroupBlobLock(result: result)
            case 9:
                guard listOfEncoded.count == 2 else { return nil }
                guard let uploadResult = UploadResult(listOfEncoded[1]) else { return nil }
                self = .updateGroupBlob(uploadResult: uploadResult)
            case 10:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = GetUserDataResult(listOfEncoded[1]) else { return nil }
                self = .getKeycloakData(result: result)
            case 11:
                guard listOfEncoded.count == 2 else { return nil }
                guard let encryptedOwnedDeviceDiscoveryResult = EncryptedData(listOfEncoded[1]) else { return nil }
                self = .ownedDeviceDiscovery(encryptedOwnedDeviceDiscoveryResult: encryptedOwnedDeviceDiscoveryResult)
            case 12:
                guard listOfEncoded.count == 2 else { return nil }
                guard let success = Bool(listOfEncoded[1]) else { return nil }
                self = .setOwnedDeviceName(success: success)
            case 13:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = SourceGetSessionNumberResult(listOfEncoded[1]) else { return nil }
                self = .sourceGetSessionNumberMessage(result: result)
            case 14:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = TargetSendEphemeralIdentityResult(listOfEncoded[1]) else { return nil }
                self = .targetSendEphemeralIdentity(result: result)
            case 15:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = OwnedIdentityTransferRelayMessageResult(listOfEncoded[1]) else { return nil }
                self = .transferRelay(result: result)
            case 16:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = OwnedIdentityTransferWaitResult(listOfEncoded[1]) else { return nil }
                self = .transferWait(result: result)
            case 17:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = SourceWaitForTargetConnectionResult(listOfEncoded[1]) else { return nil }
                self = .sourceWaitForTargetConnection(result: result)
            default:
                assertionFailure()
                return nil
            }
        }
        
    }
    
}
