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
        case deviceDiscovery(result: ContactDeviceDiscoveryResult)
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
        case ownedDeviceDiscovery(result: ServerResponseOwnedDeviceDiscoveryResult)
        case actionPerformedAboutOwnedDevice(success: Bool) // Used for the responses to ServerQuery.setOwnedDeviceName, .deactivateOwnedDevice, .setUnexpiringOwnedDevice
        case sourceGetSessionNumberMessage(result: SourceGetSessionNumberResult)
        case targetSendEphemeralIdentity(result: TargetSendEphemeralIdentityResult)
        case transferRelay(result: OwnedIdentityTransferRelayMessageResult)
        case transferWait(result: OwnedIdentityTransferWaitResult)
        case sourceWaitForTargetConnection(result: SourceWaitForTargetConnectionResult)

        
        private enum RawKind: Int, CaseIterable, ObvCodable {
            
            case deviceDiscovery = 0
            case putUserData = 1
            case getUserData = 2
            case checkKeycloakRevocation = 3
            case createGroupBlob = 4
            case getGroupBlob = 5
            case deleteGroupBlob = 6
            case putGroupLog = 7
            case requestGroupBlobLock = 8
            case updateGroupBlob = 9
            case getKeycloakData = 10
            case ownedDeviceDiscovery = 11
            case actionPerformedAboutOwnedDevice = 12
            case sourceGetSessionNumberMessage = 13
            case targetSendEphemeralIdentity = 14
            case transferRelay = 15
            case transferWait = 16
            case sourceWaitForTargetConnection = 17
            
            func obvEncode() -> ObvEncoder.ObvEncoded {
                self.rawValue.obvEncode()
            }

            init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
                guard let rawValue = Int(obvEncoded) else { assertionFailure(); return nil }
                guard let rawKind = RawKind(rawValue: rawValue) else { assertionFailure(); return nil }
                self = rawKind
            }

        }
        
        private var rawKind: RawKind {
            switch self {
            case .deviceDiscovery: return .deviceDiscovery
            case .putUserData: return .putUserData
            case .getUserData: return .getUserData
            case .checkKeycloakRevocation: return .checkKeycloakRevocation
            case .createGroupBlob: return .createGroupBlob
            case .getGroupBlob: return .getGroupBlob
            case .deleteGroupBlob: return .deleteGroupBlob
            case .putGroupLog: return .putGroupLog
            case .requestGroupBlobLock: return .requestGroupBlobLock
            case .updateGroupBlob: return .updateGroupBlob
            case .getKeycloakData: return .getKeycloakData
            case .ownedDeviceDiscovery: return .ownedDeviceDiscovery
            case .actionPerformedAboutOwnedDevice: return .actionPerformedAboutOwnedDevice
            case .sourceGetSessionNumberMessage: return .sourceGetSessionNumberMessage
            case .targetSendEphemeralIdentity: return .targetSendEphemeralIdentity
            case .transferRelay: return .transferRelay
            case .transferWait: return .transferWait
            case .sourceWaitForTargetConnection: return .sourceWaitForTargetConnection
            }
        }
        
        public func obvEncode() -> ObvEncoded {
            switch self {
            case .deviceDiscovery(result: let result):
                return [rawKind.obvEncode(), result.obvEncode()].obvEncode()
            case .putUserData:
                return [rawKind.obvEncode()].obvEncode()
            case .getUserData(result: let result):
                return [rawKind.obvEncode(), result.obvEncode()].obvEncode()
            case .checkKeycloakRevocation(verificationSuccessful: let verificationSuccessful):
                return [rawKind.obvEncode(), verificationSuccessful.obvEncode()].obvEncode()
            case .createGroupBlob(uploadResult: let uploadResult):
                return [rawKind.obvEncode(), uploadResult.obvEncode()].obvEncode()
            case .getGroupBlob(let result):
                return [rawKind.obvEncode(), result.obvEncode()].obvEncode()
            case .deleteGroupBlob(let groupDeletionWasSuccessful):
                return [rawKind.obvEncode(), groupDeletionWasSuccessful.obvEncode()].obvEncode()
            case .putGroupLog:
                return [rawKind.obvEncode()].obvEncode()
            case .requestGroupBlobLock(let result):
                return [rawKind.obvEncode(), result.obvEncode()].obvEncode()
            case .updateGroupBlob(uploadResult: let uploadResult):
                return [rawKind.obvEncode(), uploadResult.obvEncode()].obvEncode()
            case .getKeycloakData(result: let result):
                return [rawKind.obvEncode(), result.obvEncode()].obvEncode()
            case .ownedDeviceDiscovery(result: let result):
                return [rawKind.obvEncode(), result.obvEncode()].obvEncode()
            case .actionPerformedAboutOwnedDevice(success: let success):
                return [rawKind.obvEncode(), success.obvEncode()].obvEncode()
            case .sourceGetSessionNumberMessage(result: let result):
                return [rawKind.obvEncode(), result.obvEncode()].obvEncode()
            case .targetSendEphemeralIdentity(result: let result):
                return [rawKind.obvEncode(), result.obvEncode()].obvEncode()
            case .transferRelay(result: let result):
                return [rawKind.obvEncode(), result.obvEncode()].obvEncode()
            case .transferWait(result: let result):
                return [rawKind.obvEncode(), result.obvEncode()].obvEncode()
            case .sourceWaitForTargetConnection(result: let result):
                return [rawKind.obvEncode(), result.obvEncode()].obvEncode()
            }
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let listOfEncoded = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
            guard let encodedRawValue = listOfEncoded.first else { assertionFailure(); return nil }
            guard let rawValue = Int(encodedRawValue) else { assertionFailure(); return nil }
            guard let rawKind = RawKind(rawValue: rawValue) else { assertionFailure(); return nil }
            switch rawKind {
            case .deviceDiscovery:
                if listOfEncoded.count == 2 {
                    guard let result = ContactDeviceDiscoveryResult(listOfEncoded[1]) else { assertionFailure(); return nil }
                    self = .deviceDiscovery(result: result)
                } else if listOfEncoded.count == 3 {
                    // Legacy decoding
                    // guard let identity = ObvCryptoIdentity(listOfEncoded[1]) else { return nil }
                    guard let listOfEncodedDeviceUids = [ObvEncoded](listOfEncoded[2]) else { return nil }
                    var deviceUids = [UID]()
                    for encoded in listOfEncodedDeviceUids {
                        guard let deviceUid = UID(encoded) else { return nil }
                        deviceUids.append(deviceUid)
                    }
                    self = .deviceDiscovery(result: .success(deviceUIDs: deviceUids))
                } else {
                    assertionFailure()
                    return nil
                }
            case .putUserData:
                self = .putUserData
            case .getUserData:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = GetUserDataResult(listOfEncoded[1]) else { return nil }
                self = .getUserData(result: result)
            case .checkKeycloakRevocation:
                guard listOfEncoded.count == 2 else { return nil }
                guard let verificationSuccessful = Bool(listOfEncoded[1]) else { return nil }
                self = .checkKeycloakRevocation(verificationSuccessful: verificationSuccessful)
            case .createGroupBlob:
                guard listOfEncoded.count == 2 else { return nil }
                guard let uploadResult = UploadResult(listOfEncoded[1]) else { return nil }
                self = .createGroupBlob(uploadResult: uploadResult)
            case .getGroupBlob:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = GetGroupBlobResult(listOfEncoded[1]) else { assertionFailure(); return nil }
                self = .getGroupBlob(result: result)
            case .deleteGroupBlob:
                guard listOfEncoded.count == 2 else { return nil }
                guard let groupDeletionWasSuccessful = Bool(listOfEncoded[1]) else { assertionFailure(); return nil }
                self = .deleteGroupBlob(groupDeletionWasSuccessful: groupDeletionWasSuccessful)
            case .putGroupLog:
                guard listOfEncoded.count == 1 else { return nil }
                self = .putGroupLog
            case .requestGroupBlobLock:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = RequestGroupBlobLockResult(listOfEncoded[1]) else { assertionFailure(); return nil }
                self = .requestGroupBlobLock(result: result)
            case .updateGroupBlob:
                guard listOfEncoded.count == 2 else { return nil }
                guard let uploadResult = UploadResult(listOfEncoded[1]) else { return nil }
                self = .updateGroupBlob(uploadResult: uploadResult)
            case .getKeycloakData:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = GetUserDataResult(listOfEncoded[1]) else { return nil }
                self = .getKeycloakData(result: result)
            case .ownedDeviceDiscovery:
                guard listOfEncoded.count == 2 else { return nil }
                if let result = ServerResponseOwnedDeviceDiscoveryResult(listOfEncoded[1]) {
                    self = .ownedDeviceDiscovery(result: result)
                } else if let encryptedOwnedDeviceDiscoveryResult = EncryptedData(listOfEncoded[1]) {
                    // Legacy decoding
                    self = .ownedDeviceDiscovery(result: .success(encryptedOwnedDeviceDiscoveryResult: encryptedOwnedDeviceDiscoveryResult))
                } else {
                    assertionFailure()
                    return nil
                }
            case .actionPerformedAboutOwnedDevice:
                guard listOfEncoded.count == 2 else { return nil }
                guard let success = Bool(listOfEncoded[1]) else { return nil }
                self = .actionPerformedAboutOwnedDevice(success: success)
            case .sourceGetSessionNumberMessage:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = SourceGetSessionNumberResult(listOfEncoded[1]) else { return nil }
                self = .sourceGetSessionNumberMessage(result: result)
            case .targetSendEphemeralIdentity:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = TargetSendEphemeralIdentityResult(listOfEncoded[1]) else { return nil }
                self = .targetSendEphemeralIdentity(result: result)
            case .transferRelay:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = OwnedIdentityTransferRelayMessageResult(listOfEncoded[1]) else { return nil }
                self = .transferRelay(result: result)
            case .transferWait:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = OwnedIdentityTransferWaitResult(listOfEncoded[1]) else { return nil }
                self = .transferWait(result: result)
            case .sourceWaitForTargetConnection:
                guard listOfEncoded.count == 2 else { return nil }
                guard let result = SourceWaitForTargetConnectionResult(listOfEncoded[1]) else { return nil }
                self = .sourceWaitForTargetConnection(result: result)
            }
        }
        
    }
    
}
