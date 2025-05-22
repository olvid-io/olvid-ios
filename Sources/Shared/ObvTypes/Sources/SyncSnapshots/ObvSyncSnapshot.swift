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


public struct ObvSyncSnapshot {

    private enum Tag: String, CaseIterable {
        case appNode = "app"
        case identityNode = "identity"
    }
    
    public enum Context {
        case transfer(ownedCryptoId: ObvCryptoId)
        case backupDevice
        case backupProfile(ownedCryptoId: ObvCryptoId)
    }


    public let appNode: any ObvSyncSnapshotNode
    public let identityNode: any ObvSyncSnapshotNode


    private init(appNode: any ObvSyncSnapshotNode, identityNode: any ObvSyncSnapshotNode) {
        self.appNode = appNode
        self.identityNode = identityNode
    }
    
    
    public init(context: Context, appSnapshotableObject: ObvSnapshotable, identitySnapshotableObject: ObvSnapshotable) throws {
        let appNode = try appSnapshotableObject.getSyncSnapshotNode(for: context)
        let identityNode = try identitySnapshotableObject.getSyncSnapshotNode(for: context)
        self.init(appNode: appNode, identityNode: identityNode)
    }

        
    public static func fromObvDictionary(_ obvDictionary: ObvDictionary, appSnapshotableObject: ObvSnapshotable, identitySnapshotableObject: ObvSnapshotable, context: Context) throws -> Self {
        
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
        
        let identityNode = try identitySnapshotableObject.deserializeObvSyncSnapshotNode(serializedIdentityNode, context: context)
        let appNode = try appSnapshotableObject.deserializeObvSyncSnapshotNode(serializedAppNode, context: context)

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


    public enum ObvError: Error {
        case cannotEncodeTag
        case duplicateKeys
        case unexpectedObvDict
        case cannotDecodeTag
        case missingNode
    }

}
