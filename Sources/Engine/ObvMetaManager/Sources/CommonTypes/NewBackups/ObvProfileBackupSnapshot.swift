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
import ObvEncoder
import ObvTypes
import OlvidUtils


/// Type used when uploading a backup to the server, and when downloading one.
///
/// This is the exact structure that gets encoded, padded, encrypted, and included in the signed datas when uploading a backup.
public struct ObvProfileBackupSnapshot {
    
    public let profileSnapshotNode: ObvDictionary
    public let additionalInfosForProfileBackup: AdditionalInfosForProfileBackup
    public let creationDate: Date
    
    public init(profileSnapshotNode: ObvDictionary, additionalInfosForProfileBackup: AdditionalInfosForProfileBackup) {
        self.profileSnapshotNode = profileSnapshotNode
        self.additionalInfosForProfileBackup = additionalInfosForProfileBackup
        self.creationDate = Date.now
    }
    
    fileprivate init(profileSnapshotNode: ObvDictionary, additionalInfosForProfileBackup: AdditionalInfosForProfileBackup, creationDate: Date) {
        self.profileSnapshotNode = profileSnapshotNode
        self.additionalInfosForProfileBackup = additionalInfosForProfileBackup
        self.creationDate = creationDate
    }

}


extension ObvProfileBackupSnapshot: ObvFailableCodable {
    
    private enum ObvCodingKeys: String, CaseIterable, CodingKey {
        case profileSnapshotNode = "snapshot"
        case additionalInfosForProfileBackup = "additional_info"
        case creationDate = "timestamp"
        var key: Data { rawValue.data(using: .utf8)! }
    }

    
    public func obvEncode() throws -> ObvEncoded {
        var obvDict = [Data: ObvEncoded]()
        for codingKey in ObvCodingKeys.allCases {
            switch codingKey {
            case .additionalInfosForProfileBackup:
                try obvDict.obvEncode(additionalInfosForProfileBackup, forKey: codingKey)
            case .profileSnapshotNode:
                obvDict[codingKey.rawValue.data(using: .utf8)!] = profileSnapshotNode.obvEncode()
            case .creationDate:
                try obvDict.obvEncode(creationDate, forKey: codingKey)
            }
        }
        return obvDict.obvEncode()
    }
    
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let dict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
        do {
            guard let encodedProfileSnapshotNode = dict[ObvCodingKeys.profileSnapshotNode.key] else { assertionFailure(); return nil }
            guard let profileSnapshotNode = ObvDictionary(encodedProfileSnapshotNode) else { assertionFailure(); return nil }
            let additionalInfosForProfileBackup = try dict.obvDecode(AdditionalInfosForProfileBackup.self, forKey: ObvCodingKeys.additionalInfosForProfileBackup)
            let creationDate = try dict.obvDecode(Date.self, forKey: ObvCodingKeys.creationDate)
            self.init(profileSnapshotNode: profileSnapshotNode, additionalInfosForProfileBackup: additionalInfosForProfileBackup, creationDate: creationDate)
        } catch {
            assertionFailure()
            return nil
        }
    }
    
}


// MARK: AdditionalInfosForProfileBackup implements ObvCodable

extension AdditionalInfosForProfileBackup: ObvFailableCodable {
    
    private enum ObvCodingKeys: String, CaseIterable, CodingKey {
        case nameOfDeviceWhichPerformedBackup = "device_name"
        case platformOfDeviceWhichPerformedBackup = "platform"
        var key: Data { rawValue.data(using: .utf8)! }
    }

    public func obvEncode() throws -> ObvEncoded {
        var obvDict = [Data: ObvEncoded]()
        for codingKey in ObvCodingKeys.allCases {
            switch codingKey {
            case .nameOfDeviceWhichPerformedBackup:
                try obvDict.obvEncode(nameOfDeviceWhichPerformedBackup, forKey: codingKey)
            case .platformOfDeviceWhichPerformedBackup:
                try obvDict.obvEncode(self.platformOfDeviceWhichPerformedBackup, forKey: codingKey)
            }
        }
        return obvDict.obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let dict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
        do {
            let nameOfDeviceWhichPerformedBackup = try dict.obvDecode(String.self, forKey: ObvCodingKeys.nameOfDeviceWhichPerformedBackup)
            let platformOfDeviceWhichPerformedBackup = try dict.obvDecode(OlvidPlatform.self, forKey: ObvCodingKeys.platformOfDeviceWhichPerformedBackup)
            self.init(nameOfDeviceWhichPerformedBackup: nameOfDeviceWhichPerformedBackup, platformOfDeviceWhichPerformedBackup: platformOfDeviceWhichPerformedBackup)
        } catch {
            assertionFailure()
            return nil
        }
    }
    
}


// MARK: OlvidPlatform implements ObvCodable

extension OlvidPlatform: ObvFailableCodable {
    
    public func obvEncode() throws -> ObvEncoded {
        guard let data = self.rawValue.data(using: .utf8) else {
            assertionFailure()
            throw ObvError.encodingFailed
        }
        return data.obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let data = Data(obvEncoded) else { assertionFailure(); return nil }
        guard let rawValue = String(data: data, encoding: .utf8) else { assertionFailure(); return nil }
        guard let platform = OlvidPlatform(rawValue: rawValue) else { assertionFailure(); return nil }
        self = platform
    }
    
    enum ObvError: Error {
        case encodingFailed
    }

}
