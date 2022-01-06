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
import OlvidUtils

public struct ObvEngineNotification {
    
    // MARK: - NewUserDialogToPresent
    
    public struct NewUserDialogToPresent {
        public static let name = NSNotification.Name("ObvEngineNotification.NewUserDialogToPresent")
        public struct Key {
            public static let obvDialog = "obvDialog" // ObvDialog
        }
        public static func parse(_ notification: Notification) -> ObvDialog? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let obvDialog = userInfo[Key.obvDialog] as? ObvDialog else { return nil }
            return obvDialog
        }
    }
    
    // MARK: - APersistedDialogWasDeleted
    
    public struct APersistedDialogWasDeleted {
        public static let name = NSNotification.Name("ObvEngineNotification.APersistedDialogWasDeleted")
        public struct Key {
            public static let uuid = "uuid" // UUID
        }
        public static func parse(_ notification: Notification) -> UUID? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let uuid = userInfo[Key.uuid] as? UUID else { return nil }
            return uuid
        }
    }
    
    // MARK: - DeletedObliviousChannelWithContactDevice
    
    public struct DeletedObliviousChannelWithContactDevice {
        public static let name = NSNotification.Name("ObvEngineNotification.DeletedObliviousChannelWithContactDevice")
        public struct Key {
            public static let obvContactDevice = "obvContactDevice" // ObvContactDevice
        }
        public static func parse(_ notification: Notification) -> ObvContactDevice? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let obvContactDevice = userInfo[Key.obvContactDevice] as? ObvContactDevice else { return nil }
            return obvContactDevice
        }
    }
    
    // MARK: - NewTrustedContactIdentity
    
    public struct NewTrustedContactIdentity {
        public static let name = NSNotification.Name("NewContactIdentity")
        public struct Key {
            public static let contactIdentity = "contactIdentity" // ObvContactIdentity
        }
        public static func parse(_ notification: Notification) -> ObvContactIdentity? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let contactIdentity = userInfo[Key.contactIdentity] as? ObvContactIdentity else { return nil }
            return contactIdentity
        }
    }
    
    // MARK: - NewContactGroup
    
    public struct NewContactGroup {
        public static let name = NSNotification.Name("ObvEngineNotification.NewContactGroup")
        public struct Key {
            public static let obvContactGroup = "ObvContactGroup"
        }
        public static func parse(_ notification: Notification) -> ObvContactGroup? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let obvContactGroup = userInfo[Key.obvContactGroup] as? ObvContactGroup else { return nil }
            return obvContactGroup
        }
    }

    
    // MARK: - ContactGroupHasUpdatedPendingMembersAndGroupMembers

    public struct ContactGroupHasUpdatedPendingMembersAndGroupMembers {
        public static let name = NSNotification.Name("ObvEngineNotification.ContactGroupHasUpdatedPendingMembersAndGroupMembers")
        public struct Key {
            public static let obvContactGroup = "ObvContactGroup"
        }
        public static func parse(_ notification: Notification) -> ObvContactGroup? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let obvContactGroup = userInfo[Key.obvContactGroup] as? ObvContactGroup else { return nil }
            return obvContactGroup
        }
    }

    
    // MARK: - ContactGroupHasUpdatedPublishedDetails
    
    public struct ContactGroupHasUpdatedPublishedDetails {
        public static let name = NSNotification.Name("ObvEngineNotification.ContactGroupHasUpdatedPublishedDetails")
        public struct Key {
            public static let obvContactGroup = "ObvContactGroup"
        }
        public static func parse(_ notification: Notification) -> ObvContactGroup? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let obvContactGroup = userInfo[Key.obvContactGroup] as? ObvContactGroup else { return nil }
            return obvContactGroup
        }
    }

    
    // MARK: - ContactGroupDeleted
    
    public struct ContactGroupDeleted {
        public static let name = NSNotification.Name("ObvEngineNotification.ContactGroupDeleted")
        public struct Key {
            public static let ownedIdentity = "ownedIdentity"
            public static let groupOwner = "groupOwner"
            public static let groupUid = "groupUid"
        }
        public static func parse(_ notification: Notification) -> (obvOwnedIdentity: ObvOwnedIdentity, groupOwner: ObvCryptoId, groupUid: UID)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let ownedIdentity = userInfo[Key.ownedIdentity] as? ObvOwnedIdentity else { return nil }
            guard let groupOwner = userInfo[Key.groupOwner] as? ObvCryptoId else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            return (ownedIdentity, groupOwner, groupUid)
        }
    }

    
    // MARK: - ContactGroupOwnedHasUpdatedLatestDetails

    public struct ContactGroupOwnedHasUpdatedLatestDetails {
        public static let name = NSNotification.Name("ObvEngineNotification.ContactGroupOwnedHasUpdatedLatestDetails")
        public struct Key {
            public static let obvContactGroup = "ObvContactGroup"
        }
        public static func parse(_ notification: Notification) -> ObvContactGroup? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let obvContactGroup = userInfo[Key.obvContactGroup] as? ObvContactGroup else { return nil }
            return obvContactGroup
        }
    }
    
    
    // MARK: - ContactGroupOwnedDiscardedLatestDetails
    
    public struct ContactGroupOwnedDiscardedLatestDetails {
        public static let name = NSNotification.Name("ObvEngineNotification.ContactGroupOwnedDiscardedLatestDetails")
        public struct Key {
            public static let obvContactGroup = "ObvContactGroup"
        }
        public static func parse(_ notification: Notification) -> ObvContactGroup? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let obvContactGroup = userInfo[Key.obvContactGroup] as? ObvContactGroup else { return nil }
            return obvContactGroup
        }
    }
    
    
    // MARK: - ContactGroupJoinedHasUpdatedTrustedDetails
    
    public struct ContactGroupJoinedHasUpdatedTrustedDetails {
        public static let name = NSNotification.Name("ObvEngineNotification.ContactGroupJoinedHasUpdatedTrustedDetails")
        public struct Key {
            public static let obvContactGroup = "ObvContactGroup"
        }
        public static func parse(_ notification: Notification) -> ObvContactGroup? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let obvContactGroup = userInfo[Key.obvContactGroup] as? ObvContactGroup else { return nil }
            return obvContactGroup
        }
    }

    
    // MARK: - ContactGroupJoinedHasUpdatedTrustedDetails
    
    public struct NewPendingGroupMemberDeclinedStatus {
        public static let name = NSNotification.Name("ObvEngineNotification.NewPendingGroupMemberDeclinedStatus")
        public struct Key {
            public static let obvContactGroup = "ObvContactGroup"
        }
        public static func parse(_ notification: Notification) -> ObvContactGroup? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let obvContactGroup = userInfo[Key.obvContactGroup] as? ObvContactGroup else { return nil }
            return obvContactGroup
        }
    }

}
