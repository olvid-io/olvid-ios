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
import OlvidUtils
import ObvTypes


// MARK: - DeviceBlobOnServer

public struct DeviceBlobOnServer: ObvCodable {
        
    private let challengeResponse: Data
    public let deviceBlob: DeviceBlob
    private let deviceBlobEncoded: ObvEncoded // These are the bytes signed


    private init(challengeResponse: Data, deviceBlob: DeviceBlob, deviceBlobEncoded: ObvEncoded) {
        self.challengeResponse = challengeResponse
        self.deviceBlob = deviceBlob
        self.deviceBlobEncoded = deviceBlobEncoded
    }
    
    public func obvEncode() -> ObvEncoded {
        [deviceBlobEncoded, challengeResponse.obvEncode()].obvEncode()
    }
    
    
    public init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
        
        guard let arrayOfEncoded = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
        guard arrayOfEncoded.count == 2 else { assertionFailure(); return nil }

        let deviceBlobEncoded = arrayOfEncoded[0]
        guard let deviceBlob: DeviceBlob = try? arrayOfEncoded[0].obvDecode() else { assertionFailure(); return nil }
        guard let challengeResponse: Data = try? arrayOfEncoded[1].obvDecode() else { assertionFailure(); return nil }
        
        self.init(challengeResponse: challengeResponse, deviceBlob: deviceBlob, deviceBlobEncoded: deviceBlobEncoded)

    }
    
    
    public func checkChallengeResponse(for cryptoIdentity: ObvCryptoIdentity) throws {
        guard ObvSolveChallengeStruct.checkResponse(challengeResponse, to: .devicePreKey(deviceBlobEncoded: deviceBlobEncoded.rawData), from: cryptoIdentity) else {
            throw ObvError.challengeResponseCheckFailed
        }
    }
    
    
    public static func createDevicePreKeyToUploadOnServer(devicePreKey: DevicePreKey, deviceCapabilities: Set<ObvCapability>, ownedCryptoId: ObvCryptoIdentity, prng: PRNGService, solveChallengeDelegate: ObvSolveChallengeDelegate, within obvContext: ObvContext) throws -> Self {
        let devicePreKeyEncoded = devicePreKey.obvEncode()
        let deviceBlob = DeviceBlob(devicePreKey: devicePreKey, deviceCapabilities: deviceCapabilities, devicePreKeyEncoded: devicePreKeyEncoded)
        let deviceBlobEncoded = deviceBlob.obvEncode()
        let challengeResponse = try solveChallengeDelegate.solveChallenge(.devicePreKey(deviceBlobEncoded: deviceBlobEncoded.rawData), for: ownedCryptoId, using: prng, within: obvContext)
        return DeviceBlobOnServer(challengeResponse: challengeResponse, deviceBlob: deviceBlob, deviceBlobEncoded: deviceBlobEncoded)
    }

    
    enum ObvError: Error {
        case challengeResponseCheckFailed
    }
    
}


// MARK: - DeviceBlob

public struct DeviceBlob: ObvCodable {
    
    public let devicePreKey: DevicePreKey
    public let deviceCapabilities: Set<ObvCapability>

    private let devicePreKeyEncoded: ObvEncoded
    
    private enum ObvCodingKeys: String, CaseIterable, CodingKey {
        case devicePreKey = "prk"
        case deviceCapabilities = "cap"
        var key: Data { rawValue.data(using: .utf8)! }
    }

    fileprivate init(devicePreKey: DevicePreKey, deviceCapabilities: Set<ObvCapability>, devicePreKeyEncoded: ObvEncoded) {
        self.devicePreKey = devicePreKey
        self.deviceCapabilities = deviceCapabilities
        self.devicePreKeyEncoded = devicePreKeyEncoded
    }
    
    public func obvEncode() -> ObvEncoded {
        var obvDict = [Data: ObvEncoded]()
        for codingKey in ObvCodingKeys.allCases {
            switch codingKey {
            case .devicePreKey:
                try! obvDict.obvEncode(devicePreKey, forKey: codingKey)
            case .deviceCapabilities:
                try! obvDict.obvEncode(deviceCapabilities, forKey: codingKey)
            }
        }
        return obvDict.obvEncode()
    }

    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
        do {
            let deviceCapabilities = try obvDict.obvDecode(Set<ObvCapability>.self, forKey: ObvCodingKeys.deviceCapabilities)
            guard let devicePreKeyEncoded = obvDict[ObvCodingKeys.devicePreKey.key] else { assertionFailure(); return nil }
            guard let devicePreKey = DevicePreKey(devicePreKeyEncoded) else { assertionFailure(); return nil }
            self.init(devicePreKey: devicePreKey, deviceCapabilities: deviceCapabilities, devicePreKeyEncoded: devicePreKeyEncoded)
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }
    
}


// MARK: - DevicePreKey

public struct DevicePreKey: ObvCodable {
    
    public let keyId: CryptoKeyId
    public let encryptionKey: PublicKeyForPublicKeyEncryption
    public let deviceUID: UID // Must be identical to the Device's uid holding this PreKey
    public let expirationTimestamp: Date

    
    public init(keyId: CryptoKeyId, encryptionKey: PublicKeyForPublicKeyEncryption, deviceUID: UID, expirationTimestamp: Date) {
        self.keyId = keyId
        self.encryptionKey = encryptionKey
        self.deviceUID = deviceUID
        self.expirationTimestamp = expirationTimestamp
    }

    
    public func obvEncode() -> ObvEncoded {
        [keyId.obvEncode(), encryptionKey.getCompactKey().obvEncode(), deviceUID.obvEncode(), expirationTimestamp.obvEncode()].obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
        
        guard let arrayOfEncoded = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
        guard arrayOfEncoded.count == 4 else { assertionFailure(); return nil }

        guard let keyId: CryptoKeyId = try? arrayOfEncoded[0].obvDecode() else { assertionFailure(); return nil }

        guard let encryptionKey = PublicKeyForPublicKeyEncryptionDecoder.obvDecodeCompactKey(arrayOfEncoded[1]) else { assertionFailure(); return nil }

        guard let deviceUID: UID = try? arrayOfEncoded[2].obvDecode() else { assertionFailure(); return nil }
        
        guard let expirationTimestamp: Date = try? arrayOfEncoded[3].obvDecode() else { assertionFailure(); return nil }

        self.init(keyId: keyId, encryptionKey: encryptionKey, deviceUID: deviceUID, expirationTimestamp: expirationTimestamp)
        
    }
    
    
    public static func generate(prng: PRNGService, forDeviceUID deviceUID: UID, withExpirationTimestamp expirationTimestamp: Date) -> (devicePreKey: Self, privateKeyForPublicKeyEncryption: PrivateKeyForPublicKeyEncryption) {
        let keyId = CryptoKeyId.gen(with: prng)
        let (pk, sk) = PublicKeyEncryption.generateKeyPair(for: .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256, with: prng)
        let devicePreKey = DevicePreKey(keyId: keyId, encryptionKey: pk, deviceUID: deviceUID, expirationTimestamp: expirationTimestamp)
        return (devicePreKey, sk)
    }
    
}


// MARK: - ResultOfUnwrapWithPreKey

public enum ResultOfUnwrapWithPreKey {
    
    case couldNotUnwrap
    case unwrapSucceededButRemoteCryptoIdIsUnknown(remoteCryptoIdentity: ObvCryptoIdentity)
    case unwrapSucceeded(messageKey: any AuthenticatedEncryptionKey, receptionChannelInfo: ObvProtocolReceptionChannelInfo)
    case contactIsRevokedAsCompromised
    
}
