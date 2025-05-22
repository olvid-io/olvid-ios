/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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


public struct PhotoServerKeyAndLabel: Equatable, Sendable {
    
    public let key: AuthenticatedEncryptionKey
    public let label: UID
    
    public init(key: AuthenticatedEncryptionKey, label: UID) {
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
        let label = UID.gen(with: prng)
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
        try container.encode(key.obvEncode().rawData, forKey: .key)
        try container.encode(label.raw, forKey: .label)
    }


    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawEncodedKey = try values.decode(Data.self, forKey: .key)
        guard let encodedKey = ObvEncoded(withRawData: rawEncodedKey) else { assertionFailure(); throw PhotoServerKeyAndLabel.makeError(message: "Could not parse raw encoded key") }
        let key = try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
        // We make the decoder as resilient as possible
        let label: UID
        if let labelAsData = try? values.decode(Data.self, forKey: .label),
           let labelAsUID = UID(uid: labelAsData) {
            // Expected
            label = labelAsUID
        } else if let labelAsUID = try? values.decode(UID.self, forKey: .label) {
            label = labelAsUID
        } else if let labelAsString = try? values.decode(String.self, forKey: .label),
                  let labelAsData = Data(base64Encoded: labelAsString),
                  let labelAsUID = UID(uid: labelAsData) {
            assertionFailure()
            label = labelAsUID
        } else if let labelAsString = try? values.decode(String.self, forKey: .label),
                  let labelAsData = Data(hexString: labelAsString),
                  let labelAsUID = UID(uid: labelAsData) {
            assertionFailure()
            label = labelAsUID
        } else {
            assertionFailure()
            throw Self.makeError(message: "Could not decode UID in decoder of PhotoServerKeyAndLabel")
        }
        self.init(key: key, label: label)
    }


    public static func jsonDecode(_ data: Data) throws -> PhotoServerKeyAndLabel {
        let decoder = JSONDecoder()
        return try decoder.decode(PhotoServerKeyAndLabel.self, from: data)
    }

}
