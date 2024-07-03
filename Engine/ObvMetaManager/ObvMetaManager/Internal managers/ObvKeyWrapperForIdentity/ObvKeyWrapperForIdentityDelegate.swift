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
import ObvTypes
import OlvidUtils


/// This protocol will typically be implemented by the Identity Manager
public protocol ObvKeyWrapperForIdentityDelegate: ObvManager {
    
    // For the asymmetric channel
    func wrap(_: AuthenticatedEncryptionKey, for: ObvCryptoIdentity, randomizedWith: PRNGService) -> EncryptedData?
    func unwrap(_: EncryptedData, for: ObvCryptoIdentity, within: ObvContext) -> AuthenticatedEncryptionKey?
    
    // For the pre-key channel
    func wrap(_ messageKey: any AuthenticatedEncryptionKey, forRemoteDeviceUID uid: UID, ofRemoteCryptoId remoteCryptoId: ObvCryptoIdentity, ofOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, randomizedWith prng: any ObvCrypto.PRNGService, within obvContext: ObvContext) throws -> EncryptedData?
    func unwrapWithPreKey(_ wrappedMessageKey: EncryptedData, forOwnedIdentity ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ResultOfUnwrapWithPreKey

}
