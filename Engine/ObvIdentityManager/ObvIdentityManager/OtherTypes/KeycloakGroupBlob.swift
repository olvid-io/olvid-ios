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
import OlvidUtils
import ObvCrypto
import ObvTypes
import ObvMetaManager


struct KeycloakGroupBlob: Decodable, ObvErrorMaker {
    
    let groupUid: UID
    let groupCoreDetails: ObvGroupCoreDetails
    let serializedGroupCoreDetails: Data // Corresponds to the groupCoreDetails
    let photoServerKeyAndLabel: PhotoServerKeyAndLabel?
    let pushTopic: String?
    let groupMembersAndPermissions: Set<GroupV2.KeycloakGroupMemberAndPermissions>
    let serializedSharedSettings: String?
    let timestamp: Date

    var serverPhotoInfo: GroupV2.ServerPhotoInfo? {
        guard let photoServerKeyAndLabel else { return nil }
        return GroupV2.ServerPhotoInfo(photoServerKeyAndLabel: photoServerKeyAndLabel, identity: nil)
    }
    
    static let errorDomain = "KeycloakGroupBlob"

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid"
        case groupCoreDetails = "details"
        case pushTopic = "pt"
        case groupMembersAndPermissions = "gm_perms"
        case serializedSharedSettings = "sss"
        case timestamp = "timestamp"
    }

    private init(groupUid: UID, groupCoreDetails: ObvGroupCoreDetails, serializedGroupCoreDetails: Data, photoServerKeyAndLabel: PhotoServerKeyAndLabel?, pushTopic: String?, groupMembersAndPermissions: Set<GroupV2.KeycloakGroupMemberAndPermissions>, serializedSharedSettings: String?, timestamp: Date) {
        self.groupUid = groupUid
        self.groupCoreDetails = groupCoreDetails
        self.serializedGroupCoreDetails = serializedGroupCoreDetails
        self.photoServerKeyAndLabel = photoServerKeyAndLabel
        self.pushTopic = pushTopic
        self.groupMembersAndPermissions = groupMembersAndPermissions
        self.serializedSharedSettings = serializedSharedSettings
        self.timestamp = timestamp
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let groupUidRaw = try values.decode(Data.self, forKey: .groupUid)
        guard let groupUid = UID(uid: groupUidRaw) else {
            throw Self.makeError(message: "Could get group uid")
        }
        let groupCoreDetails = try values.decode(ObvGroupCoreDetails.self, forKey: .groupCoreDetails)
        let photoServerKeyAndLabel = try? decoder.singleValueContainer().decode(PhotoServerKeyAndLabel.self) // We use try? as the photo's key and label may be nil
        let pushTopic = try values.decodeIfPresent(String.self, forKey: .pushTopic)
        let groupMembersAndPermissions = try values.decode(Set<GroupV2.KeycloakGroupMemberAndPermissions>.self, forKey: .groupMembersAndPermissions)
        let serializedSharedSettings = try values.decodeIfPresent(String.self, forKey: .serializedSharedSettings)
        let timestampInMs = try values.decode(Int.self, forKey: .timestamp)
        let timestamp = Date(epochInMs: Int64(timestampInMs))
        let serializedGroupCoreDetails = try groupCoreDetails.jsonEncode()
        self.init(groupUid: groupUid,
                  groupCoreDetails: groupCoreDetails,
                  serializedGroupCoreDetails: serializedGroupCoreDetails,
                  photoServerKeyAndLabel: photoServerKeyAndLabel,
                  pushTopic: pushTopic,
                  groupMembersAndPermissions: groupMembersAndPermissions,
                  serializedSharedSettings: serializedSharedSettings,
                  timestamp: timestamp)
    }

    static func jsonDecode(_ data: Data) throws -> KeycloakGroupBlob {
        let decoder = JSONDecoder()
        return try decoder.decode(KeycloakGroupBlob.self, from: data)
    }

}
