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
        case deviceDiscovery(of: ObvCryptoIdentity, deviceUids: [UID])
        case putUserData
        case getUserData(of: ObvCryptoIdentity, userDataPath: String)
        case checkKeycloakRevocation(verificationSuccessful: Bool)

        private var rawValue: Int {
            switch self {
            case .deviceDiscovery:
                return 0
            case .putUserData:
                return 1
            case .getUserData:
                return 2
            case .checkKeycloakRevocation:
                return 3
            }
        }
        
        public func obvEncode() -> ObvEncoded {
            switch self {
            case .deviceDiscovery(of: let identity, deviceUids: let deviceUids):
                let listOfEncodedDeviceUids = deviceUids.map { $0.obvEncode() }
                return [rawValue.obvEncode(), identity.obvEncode(), listOfEncodedDeviceUids.obvEncode()].obvEncode()
            case .putUserData:
                return [rawValue.obvEncode()].obvEncode()
            case .getUserData(of: let identity, userDataPath: let userDataPath):
                return [rawValue.obvEncode(), identity.obvEncode(), userDataPath.obvEncode()].obvEncode()
            case .checkKeycloakRevocation(verificationSuccessful: let verificationSuccessful):
                return [rawValue.obvEncode(), verificationSuccessful.obvEncode()].obvEncode()
            }
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let listOfEncoded = [ObvEncoded](obvEncoded) else { return nil }
            guard let encodedRawValue = listOfEncoded.first else { return nil }
            guard let rawValue = Int(encodedRawValue) else { return nil }
            switch rawValue {
            case 0:
                guard listOfEncoded.count == 3 else { return nil }
                guard let identity = ObvCryptoIdentity(listOfEncoded[1]) else { return nil }
                guard let listOfEncodedDeviceUids = [ObvEncoded](listOfEncoded[2]) else { return nil }
                var deviceUids = [UID]()
                for encoded in listOfEncodedDeviceUids {
                    guard let deviceUid = UID(encoded) else { return nil }
                    deviceUids.append(deviceUid)
                }
                self = .deviceDiscovery(of: identity, deviceUids: deviceUids)
            case 1:
                self = .putUserData
            case 2:
                guard listOfEncoded.count == 3 else { return nil }
                guard let identity = ObvCryptoIdentity(listOfEncoded[1]) else { return nil }
                guard let userDataPath = String(listOfEncoded[2]) else { return nil }
                self = .getUserData(of: identity, userDataPath: userDataPath)
            case 3:
                guard listOfEncoded.count == 2 else { return nil }
                guard let verificationSuccessful = Bool(listOfEncoded[1]) else { return nil }
                self = .checkKeycloakRevocation(verificationSuccessful: verificationSuccessful)
            default:
                return nil
            }
        }
        
    }
    
}
