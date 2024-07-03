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


public struct ContactDeviceDiscoveryResult {
            
    public let devices: Set<Device>
    public let serverCurrentTimestamp: Date
    public let wasContactRecentlyOnline: Bool
    
    
    private enum ObvCodingKeys: String, CaseIterable, CodingKey {
        case devices = "dev"
        case serverCurrentTimestamp = "st"
        case wasContactRecentlyOnline = "ro"
        var key: Data { rawValue.data(using: .utf8)! }
    }

    
    private init(devices: Set<Device>, serverCurrentTimestamp: Date, wasContactRecentlyOnline: Bool) {
        self.devices = devices
        self.serverCurrentTimestamp = serverCurrentTimestamp
        self.wasContactRecentlyOnline = wasContactRecentlyOnline
    }
    
    
    private func toObvDictionary() -> ObvDictionary {
        return [
            ObvCodingKeys.devices.key: devices.obvEncode(),
            ObvCodingKeys.serverCurrentTimestamp.key: serverCurrentTimestamp.obvEncode(),
            ObvCodingKeys.wasContactRecentlyOnline.key: wasContactRecentlyOnline.obvEncode(),
        ]
    }
    
    
    private init(obvDict: ObvDictionary) throws {
        let wasContactRecentlyOnline = try obvDict.obvDecode(Bool.self, forKey: ObvCodingKeys.wasContactRecentlyOnline)
        let devices = try Set(obvDict.obvDecode([Device].self, forKey: ObvCodingKeys.devices))
        let rawServerTimestamp: Int = try obvDict.obvDecode(Int.self, forKey: ObvCodingKeys.serverCurrentTimestamp)
        let serverCurrentTimestamp = Date(epochInMs: Int64(rawServerTimestamp))
        self.init(devices: devices,
                  serverCurrentTimestamp: serverCurrentTimestamp,
                  wasContactRecentlyOnline: wasContactRecentlyOnline)
    }

    public struct Device: Hashable, ObvCodable {
        
        public let uid: UID
        public let deviceBlobOnServer: DeviceBlobOnServer?
        
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(uid)
        }
        
        
        public static func == (lhs: Device, rhs: Device) -> Bool {
            return lhs.uid == rhs.uid
        }
        
        
        private init(uid: UID, deviceBlobOnServer: DeviceBlobOnServer?) throws {
            self.uid = uid
            self.deviceBlobOnServer = deviceBlobOnServer
            if let deviceBlobOnServer {
                guard self.uid == deviceBlobOnServer.deviceBlob.devicePreKey.deviceUID else {
                    assertionFailure()
                    throw ObvError.preKeyDeviceUIDDoesNotMatchDeviceUID
                }
            }
        }
        
        enum ObvError: Error {
            case preKeyDeviceUIDDoesNotMatchDeviceUID
        }
        

        private enum ObvCodingKeys: String, CaseIterable, CodingKey {
            case uid = "uid"
            case deviceBlobOnServer = "prk"
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
                let deviceBlobOnServer = try obvDict.obvDecodeIfPresent(DeviceBlobOnServer.self, forKey: ObvCodingKeys.deviceBlobOnServer)
                try self.init(
                    uid: uid,
                    deviceBlobOnServer: deviceBlobOnServer)
            } catch {
                assertionFailure(error.localizedDescription)
                throw error
            }
        }
        
        
        private func toObvDictionary() -> ObvDictionary {
            var obvDict = [
                ObvCodingKeys.uid.key: self.uid.obvEncode(),
            ]
            if let deviceBlobOnServer {
                obvDict[ObvCodingKeys.deviceBlobOnServer.key] = deviceBlobOnServer.obvEncode()
            }
            return obvDict
        }
        
        public func obvEncode() -> ObvEncoded {
            toObvDictionary().obvEncode()
        }
        
    }

}


// MARK: - ContactDeviceDiscoveryResult as ObvCodable

extension ContactDeviceDiscoveryResult: ObvCodable {
    
    public init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
        guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
        do {
            try self.init(obvDict: obvDict)
        } catch {
            assertionFailure()
            return nil
        }
    }
    
    public func obvEncode() -> ObvEncoder.ObvEncoded {
        self.toObvDictionary().obvEncode()
    }

}


// MARK: - Helpers

fileprivate extension Set<ContactDeviceDiscoveryResult.Device> {
    
    func obvEncode() -> ObvEncoder.ObvEncoded {
        self.map({ $0.obvEncode() }).obvEncode()
    }
    
}
