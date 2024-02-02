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


//public struct ObvSyncSnapshotAndVersion: ObvFailableCodable {
//    public let version: Int
//    public let syncSnapshot: ObvSyncSnapshot
//    public init(version: Int, syncSnapshot: ObvSyncSnapshot) {
//        self.version = version
//        self.syncSnapshot = syncSnapshot
//    }
//    public func obvEncode() throws -> ObvEncoder.ObvEncoded {
//        return [version.obvEncode(), try syncSnapshot.obvEncode()].obvEncode()
//    }
//    public init?(_ obvEncoded: ObvEncoded) {
//        do {
//            (version, syncSnapshot) = try obvEncoded.obvDecode()
//        } catch {
//            assertionFailure(error.localizedDescription)
//            return nil
//        }
//    }
//}


public struct ObvSyncSnapshot {

    private enum Tag: String, CaseIterable {
        case appNode = "app"
        case identityNode = "identity"
    }


    public let appNode: any ObvSyncSnapshotNode
    public let identityNode: any ObvSyncSnapshotNode


    private init(appNode: any ObvSyncSnapshotNode, identityNode: any ObvSyncSnapshotNode) {
        self.appNode = appNode
        self.identityNode = identityNode
    }
    
    
    public init(ownedCryptoId: ObvCryptoId, appSnapshotableObject: ObvSnapshotable, identitySnapshotableObject: ObvSnapshotable) throws {
        let appNode = try appSnapshotableObject.getSyncSnapshotNode(for: ownedCryptoId)
        let identityNode = try identitySnapshotableObject.getSyncSnapshotNode(for: ownedCryptoId)
        self.init(appNode: appNode, identityNode: identityNode)
    }

        
    public static func fromObvDictionary(_ obvDictionary: ObvDictionary, appSnapshotableObject: ObvSnapshotable, identitySnapshotableObject: ObvSnapshotable) throws -> Self {
        
        let dict: [Tag: Data] = .init(
            obvDictionary,
            keyMapping: {
                guard let rawTag = String(data: $0, encoding: .utf8), let tag = Tag(rawValue: rawTag) else { return nil }
                return tag
            }, 
            valueMapping: {
                Data($0)
            })
        
        guard let serializedAppNode = dict[.appNode], let serializedIdentityNode = dict[.identityNode] else {
            throw ObvError.missingNode
        }
        
        let identityNode = try identitySnapshotableObject.deserializeObvSyncSnapshotNode(serializedIdentityNode)
        let appNode = try appSnapshotableObject.deserializeObvSyncSnapshotNode(serializedAppNode)

        return .init(appNode: appNode, identityNode: identityNode)
        
    }
    

    public func toObvDictionary(appSnapshotableObject: ObvSnapshotable, identitySnapshotableObject: ObvSnapshotable) throws -> ObvDictionary {

        let dict: [Tag: Data] = [
            .appNode: try appSnapshotableObject.serializeObvSyncSnapshotNode(appNode),
            .identityNode: try identitySnapshotableObject.serializeObvSyncSnapshotNode(identityNode),
        ]
        
        let obvDict: ObvDictionary = .init(dict, keyMapping: { $0.rawValue.data(using: .utf8) }, valueMapping: { $0.obvEncode() })

        return obvDict
        
    }


    /// Returns `true` if both ObvSyncSnapshotNode are exactly the same (deep compare).
//    public func isContentIdenticalTo(other syncSnapshot: ObvSyncSnapshot?) -> Bool {
//        guard let syncSnapshot else { return false }
//        let diffs = computeDiff(withOther: syncSnapshot)
//        return diffs.isEmpty
//    }


//    public func computeDiff(withOther syncSnapshot: ObvSyncSnapshot) -> Set<ObvSyncDiff> {
//        var diffs = Set<ObvSyncDiff>()
//        for tag in Tag.allCases {
//            switch tag {
//            case .appNode:
//                diffs.formUnion(self.appNode.computeDiff(withOther: syncSnapshot.appNode))
//            case .identityNode:
//                diffs.formUnion(self.identityNode.computeDiff(withOther: syncSnapshot.identityNode))
//            }
//        }
//        return diffs
//    }


    public enum ObvError: Error {
        case cannotEncodeTag
        case duplicateKeys
        case unexpectedObvDict
        case cannotDecodeTag
        case missingNode
    }

}
