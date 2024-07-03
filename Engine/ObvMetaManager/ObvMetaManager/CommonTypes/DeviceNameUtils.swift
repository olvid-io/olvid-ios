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


public struct DeviceNameUtils {
    
    public static func encrypt(deviceName: String, for ownedIdentity: ObvCryptoIdentity, using prng: PRNGService) -> EncryptedData? {
        
        let encodedDeviceName = [deviceName.trimmingWhitespacesAndNewlines().obvEncode()].obvEncode()
        let unpaddedLength = encodedDeviceName.rawData.count
        let paddedLength: Int = (1 + ((unpaddedLength-1)>>7)) << 7 // We pad to the smallest multiple of 128 larger than the actual length
        let paddedEncodedDeviceName = encodedDeviceName.rawData + Data(count: paddedLength-unpaddedLength)

        let encryptedCurrentDeviceName = PublicKeyEncryption.encrypt(paddedEncodedDeviceName, using: ownedIdentity.publicKeyForPublicKeyEncryption, and: prng)

        return encryptedCurrentDeviceName
        
    }
    
    
    public static func decrypt(encryptedDeviceName: EncryptedData, for ownedCryptoIdentity: ObvOwnedCryptoIdentity) -> String? {
        
        guard let paddedEncodedDeviceName = PublicKeyEncryption.decrypt(encryptedDeviceName, for: ownedCryptoIdentity),
              let encodedDeviceName = ObvEncoded(withPaddedRawData: paddedEncodedDeviceName),
              let listOfEncoded = [ObvEncoded](encodedDeviceName),
              let encodedName = listOfEncoded.first,
              let name = String(encodedName)
        else {
            assertionFailure()
            return nil
        }

        return name
        
    }
    
}
