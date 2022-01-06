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


public struct PhotoServerKeyAndLabel: Equatable {
    
    public let key: AuthenticatedEncryptionKey
    public let label: String
    
    public init(key: AuthenticatedEncryptionKey, label: String) {
        self.key = key
        self.label = label
    }
    
    public static func == (lhs: PhotoServerKeyAndLabel, rhs: PhotoServerKeyAndLabel) -> Bool {
        guard lhs.label == rhs.label else { return false }
        do {
            guard try AuthenticatedEncryptionKeyComparator.areEqual(lhs.key, rhs.key) else { return false }
        } catch {
            assertionFailure()
            return false
        }
        return true
    }
 
    public static func generate(with prng: PRNGService) -> PhotoServerKeyAndLabel {
        let label = UID.gen(with: prng).raw.base64EncodedString()
        let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption()
        let key = authEnc.generateKey(with: prng)
        return PhotoServerKeyAndLabel(key: key, label: label)
    }
}

extension PhotoServerKeyAndLabel: Codable {
    
    private static func makeError(message: String) -> Error { NSError(domain: "PhotoServerKeyAndLabel", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    enum CodingKeys: String, CodingKey {
        case key = "photo_key"
        case label = "photo_label"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key.encode().rawData, forKey: .key)
        try container.encode(label, forKey: .label)
    }


    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawEncodedKey = try values.decode(Data.self, forKey: .key)
        guard let encodedKey = ObvEncoded(withRawData: rawEncodedKey) else { throw PhotoServerKeyAndLabel.makeError(message: "Could not parse raw encoded key") }
        let key = try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
        let label = try values.decode(String.self, forKey: .label)
        self.init(key: key, label: label)
    }


    static func decode(_ data: Data) throws -> PhotoServerKeyAndLabel {
        let decoder = JSONDecoder()
        return try decoder.decode(PhotoServerKeyAndLabel.self, from: data)
    }

}
