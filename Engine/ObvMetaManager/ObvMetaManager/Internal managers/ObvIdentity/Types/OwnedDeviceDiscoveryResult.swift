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
import ObvEncoder
import OlvidUtils
import ObvCrypto
import ObvTypes


public struct OwnedDeviceDiscoveryResult: ObvErrorMaker {
    
    public let devices: Set<Device>
    public let isMultidevice: Bool?
    
    public static let errorDomain = "OwnedDeviceDiscoveryResult"

    private enum ObvCodingKeys: String, CaseIterable, CodingKey {
        case isMultidevice = "multi"
        case devices = "dev"
        var key: Data { rawValue.data(using: .utf8)! }
    }

    public static func decrypt(encryptedOwnedDeviceDiscoveryResult: EncryptedData, for ownedCryptoIdentity: ObvOwnedCryptoIdentity) throws -> Self {
        
        guard let rawOwnedDeviceDiscoveryResult = PublicKeyEncryption.decrypt(encryptedOwnedDeviceDiscoveryResult, for: ownedCryptoIdentity) else {
            assertionFailure()
            throw Self.makeError(message: "Could not decrypt the result of the owned device discovery query")
        }

        guard let encodedOwnedDeviceDiscoveryResult = ObvEncoded(withRawData: rawOwnedDeviceDiscoveryResult) else {
            assertionFailure()
            throw Self.makeError(message: "Could not parse the decrypted result of the owned device discovery query")
        }
        
        guard let obvDict = ObvDictionary(encodedOwnedDeviceDiscoveryResult) else {
            assertionFailure()
            throw Self.makeError(message: "Could not parse dictionary")
        }
        
        return try .init(obvDict: obvDict, for: ownedCryptoIdentity)
    }
    
    
    private init(obvDict: ObvDictionary, for ownedCryptoIdentity: ObvOwnedCryptoIdentity) throws {
        self.isMultidevice = try obvDict.obvDecodeIfPresent(Bool.self, forKey: ObvCodingKeys.isMultidevice)
        self.devices = try Set(obvDict.obvDecode([Device].self, forKey: ObvCodingKeys.devices)
            .map { device in
                device.withDecryptedName(for: ownedCryptoIdentity)
            })
    }
    
    
    public struct Device: Hashable, ObvDecodable {
        
        public let uid: UID
        public let expirationDate: Date?
        private let encryptedName: EncryptedData?
        public let latestRegistrationDate: Date?
        public let name: String?
        
        
        fileprivate func withDecryptedName(for ownedCryptoIdentity: ObvOwnedCryptoIdentity) -> Self {
            guard let encryptedName else { return self }
            guard let decryptedName = DeviceNameUtils.decrypt(encryptedDeviceName: encryptedName, for: ownedCryptoIdentity)
            else {
                assertionFailure()
                return self
            }
            return .init(
                uid: uid,
                expirationDate: expirationDate,
                encryptedName: encryptedName,
                latestRegistrationDate: latestRegistrationDate,
                name: decryptedName)
        }
        
        
        private init(uid: UID, expirationDate: Date?, encryptedName: EncryptedData?, latestRegistrationDate: Date?, name: String?) {
            self.uid = uid
            self.expirationDate = expirationDate
            self.encryptedName = encryptedName
            self.latestRegistrationDate = latestRegistrationDate
            self.name = name
        }
        
        
        private enum ObvCodingKeys: String, CaseIterable, CodingKey {
            case uid = "uid"
            case expirationDate = "exp"
            case latestRegistrationDate = "reg"
            case encryptedName = "name"
            var key: Data { rawValue.data(using: .utf8)! }
        }
        
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
            do {
                try self.init(obvDict: obvDict)
            } catch {
                assertionFailure(error.localizedDescription)
                return nil
            }
        }

        
        private init(obvDict: ObvDictionary) throws {
            do {
                let uid = try obvDict.obvDecode(UID.self, forKey: ObvCodingKeys.uid)
                let expirationDate = try obvDict.obvDecodeIfPresent(Date.self, forKey: ObvCodingKeys.expirationDate)
                let latestRegistrationDate = try obvDict.obvDecodeIfPresent(Date.self, forKey: ObvCodingKeys.latestRegistrationDate)
                let encryptedName = try obvDict.obvDecodeIfPresent(EncryptedData.self, forKey: ObvCodingKeys.encryptedName)
                self.init(
                    uid: uid,
                    expirationDate: expirationDate,
                    encryptedName: encryptedName,
                    latestRegistrationDate: latestRegistrationDate,
                    name: nil)
            } catch {
                assertionFailure(error.localizedDescription)
                throw error
            }
        }

    }

}


extension OwnedDeviceDiscoveryResult {
    
    public var obvOwnedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult {
        ObvOwnedDeviceDiscoveryResult(
            devices: Set(devices.map({ $0.obvOwnedDeviceDiscoveryResultDevice })),
            isMultidevice: isMultidevice ?? false)
    }
    
}


extension OwnedDeviceDiscoveryResult.Device {
    
    var obvOwnedDeviceDiscoveryResultDevice: ObvOwnedDeviceDiscoveryResult.Device {
        .init(identifier: uid.raw,
              expirationDate: expirationDate,
              latestRegistrationDate: latestRegistrationDate,
              name: name)
    }
    
}
