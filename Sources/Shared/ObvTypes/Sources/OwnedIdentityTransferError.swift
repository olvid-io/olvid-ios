/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


/// Errors thrown by the ``OwnedIdentityTransferProtocol``. We define these errors in this shared framework, making them available both at the engine level and the app level.
/// This allows to display specific error messages when certain errors are thrown (most notably, the `.serverRequestFailed` and the `.tryingToTransferAnOwnedIdentityThatAlreadyExistsOnTargetDevice` errors).
public enum OwnedIdentityTransferError: Error {
    case couldNotGenerateObvChannelServerQueryMessageToSend // error 0
    case couldNotDecodeSyncSnapshot // error 1
    case decryptionFailed // error 2
    case decodingFailed // error 3
    case incorrectSAS // error 4
    case serverRequestFailed // error 5
    case connectionIdsDoNotMatch // error 6
    case tryingToTransferAnOwnedIdentityThatAlreadyExistsOnTargetDevice(ownedCryptoId: ObvCryptoId) // error 7
    case couldNotOpenCommitment // error 8
    case couldNotComputeSeed // error 9
    case couldNotEncryptPayload // error 10
    case couldNotEncryptDecommitment // error 11
    case couldNotObtainKeycloakConfiguration // error 12
}


extension OwnedIdentityTransferError: CustomNSError {

    public static var errorDomain: String { "ObvTypes.OwnedIdentityTransferError" }

    /// The error code shown to the user on the transfer failure screen and sent to the support team by email.
    /// We pin these codes explicitly: without this, the code is the automatic enum tag, which numbers cases with
    /// an associated value before the other ones (adding the associated value to error 7 silently turned error 5 into error 6).
    /// The explicit codes below match the historical numbering, well known to the support team.
    public var errorCode: Int {
        switch self {
        case .couldNotGenerateObvChannelServerQueryMessageToSend: return 0
        case .couldNotDecodeSyncSnapshot: return 1
        case .decryptionFailed: return 2
        case .decodingFailed: return 3
        case .incorrectSAS: return 4
        case .serverRequestFailed: return 5
        case .connectionIdsDoNotMatch: return 6
        case .tryingToTransferAnOwnedIdentityThatAlreadyExistsOnTargetDevice: return 7
        case .couldNotOpenCommitment: return 8
        case .couldNotComputeSeed: return 9
        case .couldNotEncryptPayload: return 10
        case .couldNotEncryptDecommitment: return 11
        case .couldNotObtainKeycloakConfiguration: return 12
        }
    }

}
