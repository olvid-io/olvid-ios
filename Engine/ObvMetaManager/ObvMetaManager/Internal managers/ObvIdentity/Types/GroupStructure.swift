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
import ObvTypes


public struct GroupStructure {
    
    public let groupUid: UID
    public let publishedGroupDetailsWithPhoto: GroupDetailsElementsWithPhoto
    public let trustedOrLatestGroupDetailsWithPhoto: GroupDetailsElementsWithPhoto // Trusted details iff groupType == .joined
    public let ownedIdentity: ObvCryptoIdentity
    public let groupMembers: Set<ObvCryptoIdentity>
    public let pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>
    public let declinedPendingGroupMembers: Set<ObvCryptoIdentity>
    public let groupMembersVersion: Int
    public let groupType: GroupType
    private let _groupOwner: ObvCryptoIdentity? // Non-nil iff groupType == .joined
    
    public var pendingGroupMembersIdentities: Set<ObvCryptoIdentity> {
        return Set(pendingGroupMembers.map { $0.cryptoIdentity })
    }
    
    public var groupOwner: ObvCryptoIdentity {
        switch groupType {
        case .joined:
            return _groupOwner!
        case .owned:
            return ownedIdentity
        }
    }

    
    public enum GroupType {
        case owned
        case joined
    }
    
    
    private init(groupUid: UID, publishedGroupDetailsWithPhoto: GroupDetailsElementsWithPhoto, trustedOrLatestGroupDetailsWithPhoto: GroupDetailsElementsWithPhoto, ownedIdentity: ObvCryptoIdentity, groupMembers: Set<ObvCryptoIdentity>, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, declinedPendingGroupMembers: Set<ObvCryptoIdentity>, groupMembersVersion: Int, groupType: GroupType, groupOwner: ObvCryptoIdentity?) throws {
        let cryptoIdentitiesOfPendingGroupMembers = Set(pendingGroupMembers.map { $0.cryptoIdentity })
        guard declinedPendingGroupMembers.isSubset(of: cryptoIdentitiesOfPendingGroupMembers) else {
            throw NSError()
        }
        self.groupUid = groupUid
        self.publishedGroupDetailsWithPhoto = publishedGroupDetailsWithPhoto
        self.trustedOrLatestGroupDetailsWithPhoto = trustedOrLatestGroupDetailsWithPhoto
        self.ownedIdentity = ownedIdentity
        self.groupMembers = groupMembers
        self.pendingGroupMembers = pendingGroupMembers
        self.declinedPendingGroupMembers = declinedPendingGroupMembers
        self.groupMembersVersion = groupMembersVersion
        self.groupType = groupType
        self._groupOwner = groupOwner
    }
    
    
    public static func createOwnedGroupStructure(groupUid: UID, publishedGroupDetailsWithPhoto: GroupDetailsElementsWithPhoto, latestGroupDetailsWithPhoto: GroupDetailsElementsWithPhoto,  ownedIdentity: ObvCryptoIdentity, groupMembers: Set<ObvCryptoIdentity>, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, declinedPendingGroupMembers: Set<ObvCryptoIdentity>, groupMembersVersion: Int) throws -> GroupStructure {
        return try GroupStructure(groupUid: groupUid,
                                  publishedGroupDetailsWithPhoto: publishedGroupDetailsWithPhoto,
                                  trustedOrLatestGroupDetailsWithPhoto: latestGroupDetailsWithPhoto,
                                  ownedIdentity: ownedIdentity,
                                  groupMembers: groupMembers,
                                  pendingGroupMembers: pendingGroupMembers,
                                  declinedPendingGroupMembers: declinedPendingGroupMembers,
                                  groupMembersVersion: groupMembersVersion,
                                  groupType: .owned,
                                  groupOwner: nil)
    }
    
    
    public static func createJoinedGroupStructure(groupUid: UID, publishedGroupDetailsWithPhoto: GroupDetailsElementsWithPhoto, trustedGroupDetailsWithPhoto: GroupDetailsElementsWithPhoto, ownedIdentity: ObvCryptoIdentity, groupMembers: Set<ObvCryptoIdentity>, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, groupMembersVersion: Int, groupOwner: ObvCryptoIdentity) -> GroupStructure {
        return try! GroupStructure(groupUid: groupUid,
                                   publishedGroupDetailsWithPhoto: publishedGroupDetailsWithPhoto,
                                   trustedOrLatestGroupDetailsWithPhoto: trustedGroupDetailsWithPhoto,
                                   ownedIdentity: ownedIdentity,
                                   groupMembers: groupMembers,
                                   pendingGroupMembers: pendingGroupMembers,
                                   declinedPendingGroupMembers: Set(),
                                   groupMembersVersion: groupMembersVersion,
                                   groupType: .joined,
                                   groupOwner: groupOwner)
    }
    
    
    
}


extension GroupStructure: Equatable {
    
    public static func == (lhs: GroupStructure, rhs: GroupStructure) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }

}


extension GroupStructure: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.groupUid)
        hasher.combine(self.groupOwner)
    }
    
}
