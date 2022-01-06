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
import ObvTypes
import ObvCrypto
import OlvidUtils


public struct ObvIdentityNotification {

    public struct OwnedIdentityDetailsPublicationInProgress {
        public static let name = NSNotification.Name("ObvIdentityNotification.OwnedIdentityDetailsPublicationInProgress")
        public struct Key {
            public static let ownedCryptoIdentity = "ownedCryptoIdentity" // ObvCryptoIdentity
        }
        public static func parse(_ notification: Notification) -> ObvCryptoIdentity? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let ownedCryptoIdentity = userInfo[Key.ownedCryptoIdentity] as? ObvCryptoIdentity else { return nil }
            return ownedCryptoIdentity
        }
    }
    
    public struct NewPublishedContactIdentityDetails {
        public static let name = NSNotification.Name("ObvIdentityNotification.NewPublishedContactIdentityDetails")
        public struct Key {
            public static let contactCryptoIdentity = "contactCryptoIdentity" // ObvCryptoIdentity
            public static let ownedCryptoIdentity = "ownedCryptoIdentity"
            public static let publishedIdentityDetails = "publishedIdentityDetails"
        }
        public static func parse(_ notification: Notification) -> (contactCryptoIdentity: ObvCryptoIdentity, ownedCryptoIdentity: ObvCryptoIdentity, publishedIdentityDetails: ObvIdentityDetails)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let contactCryptoIdentity = userInfo[Key.contactCryptoIdentity] as? ObvCryptoIdentity else { return nil }
            guard let ownedCryptoIdentity = userInfo[Key.ownedCryptoIdentity] as? ObvCryptoIdentity else { return nil }
            guard let publishedIdentityDetails = userInfo[Key.publishedIdentityDetails] as? ObvIdentityDetails else { return nil }
            return (contactCryptoIdentity, ownedCryptoIdentity, publishedIdentityDetails)
        }
    }
    

    public struct NewTrustedContactIdentityDetails {
        public static let name = NSNotification.Name("ObvIdentityNotification.NewTrustedContactIdentityDetails")
        public struct Key {
            public static let contactCryptoIdentity = "contactCryptoIdentity" // ObvCryptoIdentity
            public static let ownedCryptoIdentity = "ownedCryptoIdentity"
            public static let trustedIdentityDetails = "trustedIdentityDetails"
        }
        public static func parse(_ notification: Notification) -> (contactCryptoIdentity: ObvCryptoIdentity, ownedCryptoIdentity: ObvCryptoIdentity, trustedIdentityDetails: ObvIdentityDetails)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let contactCryptoIdentity = userInfo[Key.contactCryptoIdentity] as? ObvCryptoIdentity else { return nil }
            guard let ownedCryptoIdentity = userInfo[Key.ownedCryptoIdentity] as? ObvCryptoIdentity else { return nil }
            guard let trustedIdentityDetails = userInfo[Key.trustedIdentityDetails] as? ObvIdentityDetails else { return nil }
            return (contactCryptoIdentity, ownedCryptoIdentity, trustedIdentityDetails)
        }
    }

    
    // MARK: - Creating and deleting Contact Groups
    
    public struct NewContactGroupOwned {
        public static let name = NSNotification.Name("ObvIdentityNotification.NewContactGroupOwned")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let ownedIdentity = "ownedIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, ownedIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, ownedIdentity)
        }
    }

    
    public struct NewContactGroupJoined {
        public static let name = NSNotification.Name("ObvIdentityNotification.NewContactGroupJoined")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let groupOwner = "groupOwner"
            public static let ownedIdentity = "ownedIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, groupOwner: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let groupOwner = userInfo[Key.groupOwner] as? ObvCryptoIdentity else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, groupOwner, ownedIdentity)
        }
    }

    
    public struct ContactGroupOwnedHasUpdatedLatestDetails {
        public static let name = NSNotification.Name("ObvIdentityNotification.ContactGroupOwnedHasUpdatedLatestDetails")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let ownedIdentity = "ownedIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, ownedIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, ownedIdentity)
        }
    }

    
    public struct ContactGroupOwnedDiscardedLatestDetails {
        public static let name = NSNotification.Name("ObvIdentityNotification.ContactGroupOwnedDiscardedLatestDetails")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let ownedIdentity = "ownedIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, ownedIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, ownedIdentity)
        }
    }

    
    public struct ContactGroupJoinedHasUpdatedTrustedDetails {
        public static let name = NSNotification.Name("ObvIdentityNotification.ContactGroupJoinedHasUpdatedTrustedDetails")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let groupOwner = "groupOwner"
            public static let ownedIdentity = "ownedIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, groupOwner: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let groupOwner = userInfo[Key.groupOwner] as? ObvCryptoIdentity else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, groupOwner, ownedIdentity)
        }
    }

    
    public struct ContactGroupOwnedHasUpdatedPublishedDetails {
        public static let name = NSNotification.Name("ObvIdentityNotification.ContactGroupOwnedHasUpdatedPublishedDetails")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let ownedIdentity = "ownedIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, ownedIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, ownedIdentity)
        }
    }

    
    public struct ContactGroupJoinedHasUpdatedPublishedDetails {
        public static let name = NSNotification.Name("ObvIdentityNotification.ContactGroupJoinedHasUpdatedPublishedDetails")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let groupOwner = "groupOwner"
            public static let ownedIdentity = "ownedIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, groupOwner: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let groupOwner = userInfo[Key.groupOwner] as? ObvCryptoIdentity else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, groupOwner, ownedIdentity)
        }
    }
    
    
    public struct ContactGroupOwnedHasUpdatedPendingMembersAndGroupMembers {
        public static let name = NSNotification.Name("ObvIdentityNotification.ContactGroupOwnedHasUpdatedPendingMembersAndGroupMembers")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let ownedIdentity = "ownedIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, ownedIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, ownedIdentity)
        }
    }

    
    public struct ContactGroupJoinedHasUpdatedPendingMembersAndGroupMembers {
        public static let name = NSNotification.Name("ObvIdentityNotification.ContactGroupJoinedHasUpdatedPendingMembersAndGroupMembers")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let groupOwner = "groupOwner"
            public static let ownedIdentity = "ownedIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, groupOwner: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let groupOwner = userInfo[Key.groupOwner] as? ObvCryptoIdentity else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, groupOwner, ownedIdentity)
        }
    }

    
    public struct PendingGroupMemberDeclinedInvitationToOwnedGroup {
        public static let name = NSNotification.Name("ObvIdentityNotification.PendingGroupMemberDeclinedInvitationToOwnedGroup")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let ownedIdentity = "ownedIdentity"
            public static let contactIdentity = "contactIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            guard let contactIdentity = userInfo[Key.contactIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, ownedIdentity, contactIdentity)
        }
    }

    
    public struct DeclinedPendingGroupMemberWasUndeclinedForOwnedGroup {
        public static let name = NSNotification.Name("ObvIdentityNotification.DeclinedPendingGroupMemberWasUndeclinedForOwnedGroup")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let ownedIdentity = "ownedIdentity"
            public static let contactIdentity = "contactIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            guard let contactIdentity = userInfo[Key.contactIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, ownedIdentity, contactIdentity)
        }
    }

    
    public struct ContactGroupDeleted {
        public static let name = NSNotification.Name("ObvIdentityNotification.ContactGroupDeleted")
        public struct Key {
            public static let groupUid = "groupUid"
            public static let groupOwner = "groupOwner"
            public static let ownedIdentity = "ownedIdentity"
        }
        public static func parse(_ notification: Notification) -> (groupUid: UID, groupOwner: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let groupOwner = userInfo[Key.groupOwner] as? ObvCryptoIdentity else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            return (groupUid, groupOwner, ownedIdentity)
        }
    }


    public struct ContactTrustLevelWasIncreased {
        public static let name = NSNotification.Name("ObvIdentityNotification.ContactTrustLevelWasIncreased")
        public struct Key {
            public static let ownedIdentity = "ownedIdentity"
            public static let contactIdentity = "contactIdentity"
            public static let trustLevelOfContactIdentity = "trustLevelOfContactIdentity"
            public static let flowId = "flowId"
        }
        public static func parse(_ notification: Notification) -> (ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, trustLevelOfContactIdentity: TrustLevel, flowId: FlowIdentifier)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvCryptoIdentity else { return nil }
            guard let contactIdentity = userInfo[Key.contactIdentity] as? ObvCryptoIdentity else { return nil }
            guard let trustLevelOfContactIdentity = userInfo[Key.trustLevelOfContactIdentity] as? TrustLevel else { return nil }
            guard let flowId = userInfo[Key.flowId] as? FlowIdentifier else { return nil }
            return (ownedIdentity, contactIdentity, trustLevelOfContactIdentity, flowId)
        }
    }
}
