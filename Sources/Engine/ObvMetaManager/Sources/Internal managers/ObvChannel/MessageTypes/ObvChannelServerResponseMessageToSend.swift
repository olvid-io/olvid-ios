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
        self.channelType = .local(ownedIdentity: ownedIdentity)
        self.encodedElements = encodedElements
        self.responseType = responseType
        self.flowId = flowId
        self.serverTimestamp = serverTimestamp
    }

}

// MARK: - QueryType

extension ObvChannelServerResponseMessageToSend {

    public enum ResponseType {
        case deviceDiscovery(result: ServerResponseContactDeviceDiscoveryResult)
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
        case actionPerformedAboutOwnedDevice(success: Bool)
        case sourceGetSessionNumberMessage(result: SourceGetSessionNumberResult)
        case targetSendEphemeralIdentity(result: TargetSendEphemeralIdentityResult)
        case transferRelay(result: OwnedIdentityTransferRelayMessageResult)
        case transferWait(result: OwnedIdentityTransferWaitResult)
        case sourceWaitForTargetConnection(result: SourceWaitForTargetConnectionResult)
        case uploadPreKeyForCurrentDevice(result: UploadPreKeyForCurrentDeviceResult)

        public func getEncodedInputs() -> [ObvEncoded] {
            switch self {
            case .deviceDiscovery(result: let result):
                return [result.obvEncode()]
            case .putUserData:
                return []
            case .getUserData(result: let result):
                return [result.obvEncode()]
            case .checkKeycloakRevocation(verificationSuccessful: let verificationSuccessful):
                return [verificationSuccessful.obvEncode()]
            case .createGroupBlob(uploadResult: let uploadResult):
                return [uploadResult.obvEncode()]
            case .getGroupBlob(let result):
                return [result.obvEncode()]
            case .deleteGroupBlob(let groupDeletionWasSuccessful):
                return [groupDeletionWasSuccessful.obvEncode()]
            case .putGroupLog:
                return []
            case .requestGroupBlobLock(let result):
                return [result.obvEncode()]
            case .updateGroupBlob(uploadResult: let uploadResult):
                return [uploadResult.obvEncode()]
            case .getKeycloakData(result: let result):
                return [result.obvEncode()]
            case .ownedDeviceDiscovery(result: let result):
                return [result.obvEncode()]
            case .actionPerformedAboutOwnedDevice(success: let success):
                return [success.obvEncode()]
            case .sourceGetSessionNumberMessage(result: let result):
                return [result.obvEncode()]
            case .targetSendEphemeralIdentity(result: let result):
                return [result.obvEncode()]
            case .transferRelay(result: let result):
                return [result.obvEncode()]
            case .transferWait(result: let result):
                return [result.obvEncode()]
            case .sourceWaitForTargetConnection(result: let result):
                return [result.obvEncode()]
            case .uploadPreKeyForCurrentDevice(result: let result):
                return [result.obvEncode()]
            }
        }
    }
}
