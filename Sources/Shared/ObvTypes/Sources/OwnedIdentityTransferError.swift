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


/// Errors thrown by the ``OwnedIdentityTransferProtocl``. We define these errors in this shared framework, making them available both at the engine level and the app level.
/// This allows to display specific error messages when certain errors are thrown (most notably, the `.serverRequestFailed` and the `.tryingToTransferAnOwnedIdentityThatAlreadyExistsOnTargetDevice` errors).
public enum OwnedIdentityTransferError: Error {
    case couldNotGenerateObvChannelServerQueryMessageToSend // erro 0
    case couldNotDecodeSyncSnapshot // erro 1
    case decryptionFailed // erro 2
    case decodingFailed // erro 3
    case incorrectSAS // erro 4
    case serverRequestFailed // erro 5
    case connectionIdsDoNotMatch // erro 6
    case tryingToTransferAnOwnedIdentityThatAlreadyExistsOnTargetDevice // erro 7
    case couldNotOpenCommitment // erro 8
    case couldNotComputeSeed // erro 9
    case couldNotEncryptPayload // error 10
    case couldNotEncryptDecommitment // error 11
    case couldNotObtainKeycloakConfiguration // error 12
}
