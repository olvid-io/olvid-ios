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
import CoreData
import ObvMetaManager
import ObvTypes
import OlvidUtils
import ObvCrypto

public struct ObvContactGroup {
    
    public let groupUid: UID
    private let publishedGroupDetailsWithPhoto: GroupDetailsElementsWithPhoto // We do not want to expose all the vars of a GroupDetailsElementsWithPhoto instance
    private let trustedOrLatestGroupDetailsWithPhoto: GroupDetailsElementsWithPhoto // Trusted details iff groupType == .joined
    public let ownedIdentity: ObvOwnedIdentity
    public let groupMembers: Set<ObvContactIdentity>
    public let pendingGroupMembers: Set<ObvGenericIdentity>
    public let declinedPendingGroupMembers: Set<ObvGenericIdentity> // Subset of the pending members that have declined the group invitation (e.g., using the invitation when the TL is not sufficient for an auto enrolment)
    public let groupType: GroupType
    private let _groupOwner: ObvContactIdentity? // Non-nil iff groupType == .joined

    public var groupOwner: ObvGenericIdentity {
        switch groupType {
        case .joined:
            return _groupOwner!.getGenericIdentity()
        case .owned:
            return ownedIdentity.getGenericIdentity()
        }
    }

    public var groupIdentifier: GroupV1Identifier {
        return .init(groupUid: groupUid, groupOwner: groupOwner.cryptoId)
    }
    
    public var obvGroupIdentifier: ObvGroupV1Identifier {
        return .init(ownedCryptoId: ownedIdentity.cryptoId, groupV1Identifier: groupIdentifier)
    }
    
    public enum GroupType {
        case owned
        case joined
    }

    public var publishedCoreDetails: ObvGroupCoreDetails {
        publishedGroupDetailsWithPhoto.coreDetails
    }
    
    public var trustedOrLatestCoreDetails: ObvGroupCoreDetails {
        trustedOrLatestGroupDetailsWithPhoto.coreDetails
    }
    
    public var publishedPhotoURL: URL? {
        publishedGroupDetailsWithPhoto.photoURL
    }
    
    public var trustedOrLatestPhotoURL: URL? {
        trustedOrLatestGroupDetailsWithPhoto.photoURL
    }
    
    public var publishedObvGroupDetails: ObvGroupDetails {
        publishedGroupDetailsWithPhoto.obvGroupDetails
    }
    
    public var trustedOrLatestGroupDetails: ObvGroupDetails {
        trustedOrLatestGroupDetailsWithPhoto.obvGroupDetails
    }
    
    init?(groupStructure: GroupStructure, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) {
        
        self.groupUid = groupStructure.groupUid
        self.publishedGroupDetailsWithPhoto = groupStructure.publishedGroupDetailsWithPhoto
        self.trustedOrLatestGroupDetailsWithPhoto = groupStructure.trustedOrLatestGroupDetailsWithPhoto
        do {
            guard let _ownedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: groupStructure.ownedIdentity,
                                                        identityDelegate: identityDelegate,
                                                        within: obvContext) else { return nil }
            self.ownedIdentity = _ownedIdentity
        }
        do {
            let _groupMembers = Set(groupStructure.groupMembers.compactMap { (groupMember) in
                return ObvContactIdentity(contactCryptoIdentity: groupMember, ownedCryptoIdentity: groupStructure.ownedIdentity, identityDelegate: identityDelegate, within: obvContext)
            })
            guard _groupMembers.count == groupStructure.groupMembers.count else { return nil }
            self.groupMembers = _groupMembers
        }
        self.pendingGroupMembers = Set(groupStructure.pendingGroupMembers.map({
            return ObvGenericIdentity.init(cryptoIdentity: $0.cryptoIdentity, currentCoreIdentityDetails: $0.coreDetails)
        }))
        self.declinedPendingGroupMembers = self.pendingGroupMembers.filter { groupStructure.declinedPendingGroupMembers.contains($0.cryptoId.cryptoIdentity) }
        switch groupStructure.groupType {
        case .joined:
            self.groupType = .joined
            guard let _groupOwner = ObvContactIdentity(contactCryptoIdentity: groupStructure.groupOwner, ownedCryptoIdentity: groupStructure.ownedIdentity, identityDelegate: identityDelegate, within: obvContext) else { return nil }
            self._groupOwner = _groupOwner
        case .owned:
            self.groupType = .owned
            self._groupOwner = nil
        }
    }
    
    public func publishedDetailsAndTrustedOrLatestDetailsAreEquivalentForTheUser() -> Bool {
        publishedGroupDetailsWithPhoto.hasIdenticalContent(as: trustedOrLatestGroupDetailsWithPhoto)
    }
}


extension ObvContactGroup: Equatable {
    
    public static func == (lhs: ObvContactGroup, rhs: ObvContactGroup) -> Bool {
        return lhs.groupOwner.cryptoId == rhs.groupOwner.cryptoId && lhs.groupUid == rhs.groupUid
    }
    
}

extension ObvContactGroup: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.groupOwner.cryptoId.cryptoIdentity.getIdentity())
        hasher.combine(self.groupUid.raw)
    }
    
}
