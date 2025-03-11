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
import OlvidUtils
import ObvTypes
import CryptoKit
import os.log
import ObvPlatformBase
import ObvEngine
import ObvUIObvCircledInitials
import ObvSettings
import ObvAppTypes


@objc(PersistedGroupV2)
public final class PersistedGroupV2: NSManagedObject {
    
    private static let entityName = "PersistedGroupV2"

    // Attributes
    
    @NSManaged public private(set) var customName: String?
    @NSManaged private var customPhotoFilename: String?
    @NSManaged public private(set) var groupIdentifier: Data // Part of primary key
    @NSManaged public private(set) var keycloakManaged: Bool
    @NSManaged private var namesOfOtherMembers: String?
    @NSManaged private var ownPermissionAdmin: Bool
    @NSManaged private var ownPermissionChangeSettings: Bool
    @NSManaged private var ownPermissionEditOrRemoteDeleteOwnMessages: Bool
    @NSManaged private var ownPermissionRemoteDeleteAnything: Bool
    @NSManaged private var ownPermissionSendMessage: Bool
    @NSManaged public private(set) var personalNote: String?
    @NSManaged private var rawOwnedIdentityIdentity: Data // Part of primary key
    @NSManaged private var rawPublishedDetailsStatus: Int
    @NSManaged public private(set) var updateInProgress: Bool
    @NSManaged private var serializedGroupType: Data? // Might be nil

    // Relationships
    
    @NSManaged private var detailsPublished: PersistedGroupV2Details? // Non-nil iff there are untrusted new details
    @NSManaged public private(set) var detailsTrusted: PersistedGroupV2Details? // Expected to be non nil
    @NSManaged private var rawDiscussion: PersistedGroupV2Discussion? // Expected to be non nil
    @NSManaged public private(set) var displayedContactGroup: DisplayedContactGroup? // Expected to be non nil
    @NSManaged private var rawOtherMembers: Set<PersistedGroupV2Member>
    @NSManaged private var rawOwnedIdentity: PersistedObvOwnedIdentity? // Expected to be non nil

    // Accessors
    
    public var obvGroupIdentifier: ObvGroupV2Identifier {
        get throws {
            guard let identifier = ObvGroupV2.Identifier(appGroupIdentifier: groupIdentifier) else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotParseGroupIdentifier
            }
            return .init(ownedCryptoId: try ownCryptoId, identifier: identifier)
        }
    }
    
    public var otherMembers: Set<PersistedGroupV2Member> {
        rawOtherMembers
    }
    
    public var otherMembersSorted: [PersistedGroupV2Member] {
        otherMembers.sorted(by: { $0.normalizedSortKey < $1.normalizedSortKey })
    }
    
    public var contactsAmongOtherPendingAndNonPendingMembers: Set<PersistedObvContactIdentity> {
        Set(rawOtherMembers.compactMap({ $0.contact }))
    }

    public var contactsAmongNonPendingOtherMembers: Set<PersistedObvContactIdentity> {
        Set(rawOtherMembers.filter({ !$0.isPending }).compactMap({ $0.contact }))
    }

    public var ownCryptoId: ObvCryptoId {
        get throws {
            try ObvCryptoId(identity: rawOwnedIdentityIdentity)
        }
    }
    
    var ownedIdentityIdentity: Data {
        return rawOwnedIdentityIdentity
    }
    
    /// Expected to be non nil
    public var persistedOwnedIdentity: PersistedObvOwnedIdentity? {
        return rawOwnedIdentity
    }
    
    public var ownedIdentityIsAdmin: Bool {
        return ownPermissionAdmin
    }
    
    public var ownedIdentityIsAllowedToChangeSettings: Bool {
        return ownPermissionChangeSettings
    }
    
    var ownedIdentityIsAllowedToEditOrRemoteDeleteOwnMessages: Bool {
        return ownPermissionRemoteDeleteAnything || ownPermissionEditOrRemoteDeleteOwnMessages
    }
    
    var ownedIdentityIsAllowedToRemoteDeleteAnything: Bool {
        return ownPermissionRemoteDeleteAnything
    }
    
    public var ownedIdentityIsAllowedToSendMessage: Bool {
        return ownPermissionSendMessage
    }
    
    public var discussion: PersistedGroupV2Discussion? {
        return rawDiscussion
    }
    
    public var groupType: GroupType? {
        guard let serializedGroupType else { return nil }
        return try? GroupType(serializedGroupType: serializedGroupType)
    }
    

    private(set) var publishedDetailsStatus: PublishedDetailsStatusType {
        get {
            let value = PublishedDetailsStatusType(rawValue: rawPublishedDetailsStatus)
            assert(value != nil)
            return value ?? .noNewPublishedDetails
        }
        set {
            guard self.rawPublishedDetailsStatus != newValue.rawValue else { return }
            self.rawPublishedDetailsStatus = newValue.rawValue
        }
    }
    
    
    public var circledInitialsConfiguration: CircledInitialsConfiguration {
        .groupV2(photo: .url(url: self.displayPhotoURL), groupIdentifier: groupIdentifier, showGreenShield: keycloakManaged)
    }

    
    public var circledInitialsConfigurationPublished: CircledInitialsConfiguration {
        return .groupV2(photo: .url(url: self.displayPhotoURLPublished), groupIdentifier: groupIdentifier, showGreenShield: keycloakManaged)
    }

    
    /// Used when restoring a sync snapshot or when restoring a backup to prevent any notification on insertion
    private(set) var isInsertedWhileRestoringSyncSnapshot = false

    
    // Initializer
    
    private convenience init(obvGroupV2: ObvGroupV2, shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: Bool, isRestoringSyncSnapshotOrBackup: Bool, within context: NSManagedObjectContext) throws {
        
        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvGroupV2.ownIdentity, within: context) else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotFindOwnedIdentity
        }

        guard try Self.getWithPrimaryKey(ownCryptoId: obvGroupV2.ownIdentity, groupIdentifier: obvGroupV2.appGroupIdentifier, within: context) == nil else {
            assertionFailure()
            throw ObvUICoreDataError.persistedGroupV2AlreadyExists
        }

        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedGroupV2.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.isInsertedWhileRestoringSyncSnapshot = isRestoringSyncSnapshotOrBackup

        self.rawOwnedIdentity = ownedIdentity
        updateAttributes(obvGroupV2: obvGroupV2)
        try updateRelationships(obvGroupV2: obvGroupV2,
                                shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion,
                                isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
        updateNamesOfOtherMembers()
        
    }
    
    
    private func setOwnPermissions(to permissions: Set<ObvGroupV2.Permission>, keycloakManaged: Bool) {
        for permission in ObvGroupV2.Permission.allCases {
            switch permission {
            case .groupAdmin:
                if keycloakManaged {
                    assert(!permissions.contains(permission))
                    self.ownPermissionAdmin = false
                } else {
                    let newPermissionValue = permissions.contains(permission)
                    if self.ownPermissionAdmin != newPermissionValue {
                        if newPermissionValue {
                            try? discussion?.ownedIdentityBecameAnAdmin()
                        } else {
                            try? discussion?.ownedIdentityIsNoLongerAnAdmin()
                        }
                        self.ownPermissionAdmin = newPermissionValue
                    }
                }
            case .remoteDeleteAnything:
                let newPermissionValue = permissions.contains(permission)
                if self.ownPermissionRemoteDeleteAnything != newPermissionValue {
                    self.ownPermissionRemoteDeleteAnything = newPermissionValue
                }
            case .editOrRemoteDeleteOwnMessages:
                let newPermissionValue = permissions.contains(permission)
                if self.ownPermissionEditOrRemoteDeleteOwnMessages != newPermissionValue {
                    self.ownPermissionEditOrRemoteDeleteOwnMessages = newPermissionValue
                }
            case .changeSettings:
                let newPermissionValue = permissions.contains(permission)
                if self.ownPermissionChangeSettings != newPermissionValue {
                    self.ownPermissionChangeSettings = newPermissionValue
                }
            case .sendMessage:
                let newPermissionValue = permissions.contains(permission)
                if self.ownPermissionSendMessage != newPermissionValue {
                    self.ownPermissionSendMessage = newPermissionValue
                }
            }
        }
    }
    
    
    private func updateAttributes(obvGroupV2: ObvGroupV2) {

        if self.groupIdentifier != obvGroupV2.appGroupIdentifier {
            self.groupIdentifier = obvGroupV2.appGroupIdentifier
        }

        if self.keycloakManaged != obvGroupV2.keycloakManaged {
            self.keycloakManaged = obvGroupV2.keycloakManaged
        }

        // namesOfOtherMembers is updated later

        setOwnPermissions(to: obvGroupV2.ownPermissions, keycloakManaged: obvGroupV2.keycloakManaged)

        if self.rawOwnedIdentityIdentity != obvGroupV2.ownIdentity.getIdentity() {
            self.rawOwnedIdentityIdentity = obvGroupV2.ownIdentity.getIdentity()
        }
        if self.updateInProgress != obvGroupV2.updateInProgress {
            self.updateInProgress = obvGroupV2.updateInProgress
        }
        
        if let serializedGroupType = obvGroupV2.serializedGroupType {
            do {
                if let selfSerializedGroupType = self.serializedGroupType {
                    if try GroupType(serializedGroupType: serializedGroupType) != GroupType(serializedGroupType: selfSerializedGroupType) {
                        self.serializedGroupType = serializedGroupType
                    }
                } else {
                    _ = try GroupType(serializedGroupType: serializedGroupType) // Make sure the serialized group type can be deserialized
                    self.serializedGroupType = serializedGroupType
                }
            } catch {
                assertionFailure()
                self.serializedGroupType = nil
                // In production, continue anyway
            }
        }
        
        try? createOrUpdateTheAssociatedDisplayedContactGroup()
        try? discussion?.resetTitle(to: self.displayName)

    }
    
    
    /// Returns `true` iff the personal note had to be updated in database
    func setNote(to newNote: String?) -> Bool {
        if self.personalNote != newNote {
            self.personalNote = newNote
            return true
        } else {
            return false
        }
    }

    
    /// The `namesOfOtherMembers` attribute is essentially used to display a group name when no specific name was specified.
    /// This method allows to update this attribute.
    private func updateNamesOfOtherMembers() {
        let names = otherMembers.map({ $0.displayedCustomDisplayNameOrFirstNameOrLastName ?? "" }).sorted()
        let newNamesOfOtherMembers = names.formatted(.list(type: .and, width: .short))
        if self.namesOfOtherMembers != newNamesOfOtherMembers {
            self.namesOfOtherMembers = newNamesOfOtherMembers
        }
        try? createOrUpdateTheAssociatedDisplayedContactGroup()
        try? discussion?.resetTitle(to: self.displayName)
    }
    
    
    /// This method saves the photo to a proper location.
    func updateCustomPhotoWithPhoto(_ newPhoto: UIImage?, within obvContext: ObvContext) throws {
        
        defer {
            try? createOrUpdateTheAssociatedDisplayedContactGroup()
            // No need to reset the discussion title
            discussion?.setHasUpdates() // Makes sure the photo is updated in the discussion list
        }
        
        guard self.managedObjectContext == obvContext.context else {
            assertionFailure()
            throw ObvUICoreDataError.inappropriateContext
        }
        
        // Start by removing the current custom photo if there is one.
        // We only perform this step if the context saves without error
        
        if let customPhotoURL = self.customPhotoURL, FileManager.default.fileExists(atPath: customPhotoURL.path) {
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                guard FileManager.default.fileExists(atPath: customPhotoURL.path) else { return }
                do {
                    try FileManager.default.removeItem(at: customPhotoURL)
                } catch {
                    assertionFailure("Could not remove item at url \(customPhotoURL)")
                }
            }
        }
        
        self.customPhotoFilename = nil
        
        // If received new photo is nil, there is nothing left to do
        
        guard let newPhoto else { return }

        // Create a file at a proper location

        let newCustomFilename = UUID().uuidString
        self.customPhotoFilename = newCustomFilename
        let customPhotoURL = ObvUICoreDataConstants.ContainerURL.forCustomGroupProfilePictures.appendingPathComponent(newCustomFilename)
        guard let jpegData = newPhoto.jpegData(compressionQuality: 0.75) else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotExtractJPEGData
        }
        do {
            try jpegData.write(to: customPhotoURL)
        } catch {
            assertionFailure()
            throw ObvUICoreDataError.couldNotSavePhoto
        }

        // If the context saves with an error, remove the file we just created
        
        try obvContext.addContextDidSaveCompletionHandler { error in
            if error != nil {
                try? FileManager.default.removeItem(at: customPhotoURL)
            }
        }
        
    }
    
    
    /// Returns `true` iff the group custom name had to be updated.
    func updateCustomNameWith(with newCustomName: String?) throws -> Bool {
        guard self.customName != newCustomName else {
            return false
        }
        self.customName = newCustomName
        try createOrUpdateTheAssociatedDisplayedContactGroup()
        try discussion?.resetTitle(to: self.displayName)
        return true
    }
    

    private func updateRelationships(obvGroupV2: ObvGroupV2, shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: Bool, isRestoringSyncSnapshotOrBackup: Bool) throws {
        
        guard let context = managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        
        if let publishedDetailsAndPhoto = obvGroupV2.publishedDetailsAndPhoto {
            if let detailsPublished = self.detailsPublished {
                if try detailsPublished.updateWithDetailsAndPhoto(publishedDetailsAndPhoto) {
                    if self.publishedDetailsStatus != .unseenPublishedDetails {
                        self.publishedDetailsStatus = .unseenPublishedDetails
                    }
                }
            } else {
                // Before creating new published details, we make sure that the details sent by the engine are indeed different from a "visual" point of view for the user.
                // The situation where this is necessary is when an admin updates a group by, e.g., simply changing the admin status of a member.
                // For technical reasons, the admin will "take over" the photo of the group, changing the photo infos but not the bytes of the photo.
                // In that case, we receive from the engine a first call indicating that there are new published details (since the photo infos did change) and then another call indicating that there are no published details.
                // This second call occurs because the engine "realized", after downloading the photo, that the published details can be auto trusted.
                // Here, we thus have to filter out published details that would just look the same than the trusted details to the user. We know that, evenutally, the engine will delete these published details anyway.

                let publishedCoreDetailsAreIdenticalToTrustedOnes: Bool
                if let trustedCoreDetail = self.detailsTrusted?.coreDetails, let publishedCoreDetails = try? GroupV2CoreDetails.jsonDecode(serializedGroupCoreDetails: publishedDetailsAndPhoto.serializedGroupCoreDetails), trustedCoreDetail == publishedCoreDetails {
                    publishedCoreDetailsAreIdenticalToTrustedOnes = true
                } else {
                    publishedCoreDetailsAreIdenticalToTrustedOnes = false
                }

                let engineIsStillDownloadingPhoto: Bool
                switch publishedDetailsAndPhoto.photoURLFromEngine {
                case .downloading:
                    engineIsStillDownloadingPhoto = true
                case .none, .downloaded:
                    engineIsStillDownloadingPhoto = false
                }
                
                if publishedCoreDetailsAreIdenticalToTrustedOnes && engineIsStillDownloadingPhoto {
                    // Do not create new published details
                } else {
                    self.detailsPublished = try PersistedGroupV2Details(publishedDetailsAndPhoto: publishedDetailsAndPhoto, persistedGroupV2: self)
                    if self.publishedDetailsStatus != .unseenPublishedDetails {
                        self.publishedDetailsStatus = .unseenPublishedDetails
                    }
                }
                
            }
        } else {
            if self.detailsPublished != nil {
                self.detailsPublished = nil
            }
            if self.publishedDetailsStatus != .noNewPublishedDetails {
                self.publishedDetailsStatus = .noNewPublishedDetails
            }
        }
        if let detailsTrusted = self.detailsTrusted {
            _ = try detailsTrusted.updateWithDetailsAndPhoto(obvGroupV2.trustedDetailsAndPhoto)
        } else {
            self.detailsTrusted = try PersistedGroupV2Details(trustedDetailsAndPhoto: obvGroupV2.trustedDetailsAndPhoto, persistedGroupV2: self)
        }
        
        // Normaly at this point, there is nothing left to do for the group trusted/published details.
        // There is one particular situation where we want to auto-accept the published details:
        // - When there is no photo in the trusted details
        // - There is one in the published details
        // - And both details are the same otherwise
        // In that case, we destroy any published details we might have created and ask the engine to trust the published details
        
        if let detailsTrusted = self.detailsTrusted,
           let detailsPublished = self.detailsPublished,
           detailsTrusted.photoURLFromEngine == nil,
           detailsPublished.photoURLFromEngine != nil,
           detailsTrusted.coreDetails == detailsPublished.coreDetails {
            if self.detailsPublished != nil {
                self.detailsPublished = nil
            }
            if self.publishedDetailsStatus != .noNewPublishedDetails {
                self.publishedDetailsStatus = .noNewPublishedDetails
            }
            try trustedDetailsShouldBeReplacedByPublishedDetails()
        }

        
        let receivedOtherMembersIdentities = Set(obvGroupV2.otherMembers.map({ $0.identity }))
        let currentOtherMembersIdentities = Set(self.rawOtherMembers.compactMap { $0.cryptoId })
        
        let membersToRemove = currentOtherMembersIdentities.subtracting(receivedOtherMembersIdentities)
        let membersToInsert = receivedOtherMembersIdentities.subtracting(currentOtherMembersIdentities)
        let membersToUpdate = currentOtherMembersIdentities.intersection(receivedOtherMembersIdentities)
        
        // Remove members that are not part of the group anymore
        
        for otherMember in self.rawOtherMembers {
            guard let otherMemberCryptoId = otherMember.cryptoId else { assertionFailure(); continue }
            guard membersToRemove.contains(otherMemberCryptoId) else { continue }
            try otherMember.delete()
        }
        
        // Insert new members
        
        let otherMembersToInsert = obvGroupV2.otherMembers.filter({ membersToInsert.contains($0.identity) })
        try otherMembersToInsert.forEach { memberToInsert in
            _ = try PersistedGroupV2Member(identityAndPermissionsAndDetails: memberToInsert,
                                           groupIdentifier: obvGroupV2.appGroupIdentifier,
                                           ownCryptoId: obvGroupV2.ownIdentity,
                                           persistedGroupV2: self, 
                                           isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
        }
        
        // Update existing members
        
        let otherMembersToUpdate = obvGroupV2.otherMembers.filter({ membersToUpdate.contains($0.identity) })
        try otherMembersToUpdate.forEach { memberToUpdate in
            guard let currentMember = self.rawOtherMembers.first(where: { $0.cryptoId == memberToUpdate.identity }) else { assertionFailure(); return }
            try currentMember.updateWith(identityAndPermissionsAndDetails: memberToUpdate)
        }
        
        // Remove the infos of messages that we wanted to send to members that are now deleted.
        // Note that each time we delete some infos, the corresponding sent message status is updated.
        
        if let discussion = discussion {
            for memberRemoved in membersToRemove {
                let infos = try PersistedMessageSentRecipientInfos.getAllUnprocessedForContact(
                    contactCryptoId: memberRemoved,
                    forMessagesWithinDiscussion: discussion)
                infos.forEach({ try? $0.delete() })
            }
        }

        // Create or update the DisplayedContactGroup
        
        try createOrUpdateTheAssociatedDisplayedContactGroup()
        
        // Create the discussion if required
        
        if rawDiscussion == nil {
            if let existingDiscussion = try PersistedGroupV2Discussion.getPersistedGroupV2Discussion(
                groupIdentifier: groupIdentifier,
                ownCryptoId: try ownCryptoId,
                within: context) {
                try existingDiscussion.setStatus(to: .active)
                rawDiscussion = existingDiscussion
            } else {
                rawDiscussion = try PersistedGroupV2Discussion(
                    persistedGroupV2: self,
                    shouldApplySharedConfigurationFromGlobalSettings: shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion,
                    isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
            }
        }
        
        // If the group is a keycloak group, we might have shared data pushed by the server
        
        if obvGroupV2.keycloakManaged {
            do {
                if let serializedSharedSettings = obvGroupV2.serializedSharedSettings {
                    if let serializedSharedSettingsAsData = serializedSharedSettings.data(using: .utf8) {
                        let discussionSharedConfigurationForKeycloakGroupJSON = try DiscussionSharedConfigurationForKeycloakGroupJSON.jsonDecode(serializedSharedSettingsAsData)
                        if let expirationJSON = discussionSharedConfigurationForKeycloakGroupJSON.expiration {
                            assert(rawDiscussion != nil)
                            _ = try rawDiscussion?.sharedConfiguration.replacePersistedDiscussionSharedConfiguration(with: expirationJSON)
                        }
                    } else {
                        assertionFailure("We could not parse the shared settings sent by the keycloak server") // In production, continue anyway
                    }
                }
            } catch {
                assertionFailure("We could not update the share discussion configuration for this keycloak managed group: \(error.localizedDescription)") // In production, continue anyway
            }
        }

        // Make sure the photo is updated in the list of discussions
        
        if context.hasChanges {
            discussion?.setHasUpdates()
        }

        // Update the associated displayed group
        
        try createOrUpdateTheAssociatedDisplayedContactGroup()

    }
    
    
    public func trustedDetailsShouldBeReplacedByPublishedDetails() throws {
        ObvMessengerCoreDataNotification.groupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: try ownCryptoId, groupIdentifier: groupIdentifier)
            .postOnDispatchQueue()
    }
    

    private func createOrUpdateTheAssociatedDisplayedContactGroup() throws {
        if let displayedContactGroup = self.displayedContactGroup {
            displayedContactGroup.updateUsingUnderlyingGroup()
        } else {
            self.displayedContactGroup = try DisplayedContactGroup(groupV2: self)
        }
    }
    
    
    static func createOrUpdate(obvGroupV2: ObvGroupV2, createdByMe: Bool, isRestoringSyncSnapshotOrBackup: Bool, within context: NSManagedObjectContext) throws -> PersistedGroupV2 {

        let persistedGroup: PersistedGroupV2

        if let _persistedGroup = try PersistedGroupV2.getWithObvGroupV2(obvGroupV2, within: context) {
            
            persistedGroup = _persistedGroup
            persistedGroup.updateAttributes(obvGroupV2: obvGroupV2)
            try persistedGroup.updateRelationships(
                obvGroupV2: obvGroupV2,
                shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: createdByMe,
                isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
            persistedGroup.updateNamesOfOtherMembers()
            
        } else {
            
            persistedGroup = try PersistedGroupV2(
                obvGroupV2: obvGroupV2,
                shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: createdByMe, 
                isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup,
                within: context)
            // Note that updateAttributes, updateRelationships, and updateNamesOfOtherMembers are called in the constructor of PersistedGroupV2
            
        }

        try persistedGroup.createOrUpdateTheAssociatedDisplayedContactGroup()
        
        return persistedGroup
    }
    

    public func delete() throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        if let discussion = discussion {
            try discussion.setStatus(to: .locked)
        }
        context.delete(self)
    }
    
    
    fileprivate func updateWhenPersistedGroupV2MemberIsUpdated() {
        try? createOrUpdateTheAssociatedDisplayedContactGroup()
        try? discussion?.resetTitle(to: self.displayName)
    }
    
    
    public func setUpdateInProgress() {
        assert(!keycloakManaged)
        if !self.updateInProgress {
            self.updateInProgress = true
        }
    }
    
    
    public func removeUpdateInProgress() {
        if self.updateInProgress {
            self.updateInProgress = false
        }
    }
    
    
    public func markPublishedDetailsAsSeen() {
        if detailsPublished == nil {
            publishedDetailsStatus = .noNewPublishedDetails
        } else {
            publishedDetailsStatus = .seenPublishedDetails
        }
        // Update the associated displayed group
        try? createOrUpdateTheAssociatedDisplayedContactGroup()
    }

    
    // MARK: Convenience DB getters

    struct Predicate {
        enum Key: String {
            case groupIdentifier = "groupIdentifier"
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
            case updateInProgress = "updateInProgress"
            case rawOtherMembers = "rawOtherMembers"
            case customPhotoFilename = "customPhotoFilename"
        }
        static func withOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownedIdentity.identity)
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withPrimaryKey(ownCryptoId: ObvCryptoId, groupIdentifier: Data) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownCryptoId.getIdentity()),
                NSPredicate(Key.groupIdentifier, EqualToData: groupIdentifier),
            ])
        }
        static func withObjectID(_ objectID: TypeSafeManagedObjectID<PersistedGroupV2>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
        static func otherMembersIncludeContact(_ contactIdentity: PersistedObvContactIdentity) -> NSPredicate {
            guard let ownedIdentity = contactIdentity.ownedIdentity else { assertionFailure(); return NSPredicate(value: false) }
            let predicateChain = [Key.rawOtherMembers.rawValue,
                                  PersistedGroupV2Member.Predicate.Key.rawContact.rawValue].joined(separator: ".")
            let predicateFormat = "ANY \(predicateChain) == %@"
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                withOwnedIdentity(ownedIdentity),
                NSPredicate(format: predicateFormat, contactIdentity)
            ])
        }
        public static var withCustomPhotoFilename: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.customPhotoFilename)
        }
    }

    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedGroupV2> {
        return NSFetchRequest<PersistedGroupV2>(entityName: self.entityName)
    }

    
    public static func getAllCustomPhotoURLs(within context: NSManagedObjectContext) throws -> Set<URL> {
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.withCustomPhotoFilename
        request.propertiesToFetch = [Predicate.Key.customPhotoFilename.rawValue]
        let details = try context.fetch(request)
        let photoURLs = Set(details.compactMap({ $0.customPhotoURL }))
        return photoURLs
    }

    
    public static func getWithPrimaryKey(ownCryptoId: ObvCryptoId, groupIdentifier: Data, within context: NSManagedObjectContext) throws -> PersistedGroupV2? {
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.withPrimaryKey(ownCryptoId: ownCryptoId, groupIdentifier: groupIdentifier)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    public static func get(objectID: TypeSafeManagedObjectID<PersistedGroupV2>, within context: NSManagedObjectContext) throws -> PersistedGroupV2? {
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    static func getWithObvGroupV2(_ obvGroupV2: ObvGroupV2, within context: NSManagedObjectContext) throws -> PersistedGroupV2? {
        return try get(ownIdentity: obvGroupV2.ownIdentity, appGroupIdentifier: obvGroupV2.appGroupIdentifier, within: context)
    }

    
    public static func get(ownIdentity: ObvCryptoId, appGroupIdentifier: GroupV2Identifier, within context: NSManagedObjectContext) throws -> PersistedGroupV2? {
        return try getWithPrimaryKey(ownCryptoId: ownIdentity, groupIdentifier: appGroupIdentifier, within: context)
    }

    public static func get(ownIdentity: PersistedObvOwnedIdentity, appGroupIdentifier: Data) throws -> PersistedGroupV2? {
        guard let context = ownIdentity.managedObjectContext else {
            throw ObvUICoreDataError.noContext
        }
        return try getWithPrimaryKey(ownCryptoId: ownIdentity.cryptoId, groupIdentifier: appGroupIdentifier, within: context)
    }

    public static func getAllPersistedGroupV2(ownedIdentity: PersistedObvOwnedIdentity) throws -> Set<PersistedGroupV2> {
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.withOwnedIdentity(ownedIdentity)
        return Set(try context.fetch(request))
    }
    
    
    public static func getAllPersistedGroupV2(whereContactIdentitiesInclude contactIdentity: PersistedObvContactIdentity) throws -> Set<PersistedGroupV2> {
        guard let context = contactIdentity.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.otherMembersIncludeContact(contactIdentity)
        request.fetchBatchSize = 100
        return Set(try context.fetch(request))
    }

    
    public static func getAllGroupV2Identifiers(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> Set<ObvGroupV2Identifier> {
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        request.fetchBatchSize = 1_000
        let results = try context.fetch(request)
        let groupIds: [ObvGroupV2Identifier] = results
            .compactMap { group in
                guard let groupV2Identifier = ObvGroupV2.Identifier(appGroupIdentifier: group.groupIdentifier) else {
                    assertionFailure()
                    return nil
                }
                return ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: groupV2Identifier)
            }
        return Set(groupIds)
    }
    
    
    // MARK: Displaying group information
    
    /// Used when displaying a group title in the interface
    public var displayName: String {
        if let displayNameWithNoDefault = displayNameWithNoDefault, !displayNameWithNoDefault.isEmpty {
            return displayNameWithNoDefault
        } else {
            return NSLocalizedString("GROUP_TITLE_WHEN_NO_SPECIFIC_TITLE_IS_GIVEN", comment: "")
        }
    }

    /// Used within `DisplayedContactGroup`, to set the title
    var displayNameWithNoDefault: String? {
        if let customName = customName, !customName.isEmpty {
            return customName
        } else if let trustedName = trustedName, !trustedName.isEmpty {
            return trustedName
        } else if let namesOfOtherMembers = namesOfOtherMembers, !namesOfOtherMembers.isEmpty {
            return namesOfOtherMembers
        } else {
            return nil
        }
    }

    public var trustedName: String? {
        detailsTrusted?.name
    }
    
    public var displayedDescription: String? {
        detailsTrusted?.groupDescription
    }
    
    public var trustedDescription: String? {
        detailsTrusted?.groupDescription
    }
    
    public var hasPublishedDetails: Bool {
        detailsPublished != nil
    }
    
    public var displayNamePublished: String? {
        detailsPublished?.name
    }

    public var displayedDescriptionPublished: String? {
        detailsPublished?.groupDescription
    }
    
    public var trustedPhotoURL: URL? {
        detailsTrusted?.photoURLFromEngine
    }

    public var displayPhotoURL: URL? {
        customPhotoURL ?? detailsTrusted?.photoURLFromEngine
    }

    public var displayPhotoURLPublished: URL? {
        detailsPublished?.photoURLFromEngine
    }

    public var customPhotoURL: URL? {
        guard let customPhotoFilename = customPhotoFilename else { return nil }
        let url = ObvUICoreDataConstants.ContainerURL.forCustomGroupProfilePictures.appendingPathComponent(customPhotoFilename)
        assert(FileManager.default.fileExists(atPath: url.path))
        return url
    }

    public var enginePhotoURL: URL? {
        detailsTrusted?.photoURLFromEngine
    }
    
    // MARK: Helpers for the UI
    
    public enum CanLeaveGroup {
        case canLeaveGroup
        case cannotLeaveGroupAsWeAreTheOnlyAdmin
        case cannotLeaveGroupAsThisIsKeycloakGroup
    }
    
    /// For a server group: We can always leave a group if we are not an administrator. If we are, we can only leave if there is another administrator that is not pending.
    /// For a keycloak group: We cannot leave the group.
    public var ownedIdentityCanLeaveGroup: CanLeaveGroup {
        if keycloakManaged {
            return .cannotLeaveGroupAsThisIsKeycloakGroup
        } else {
            let nonPendingOtherMembers = otherMembers.filter({ !$0.isPending })
            if !ownPermissionAdmin || !nonPendingOtherMembers.filter({ $0.isAnAdmin }).isEmpty {
                return .canLeaveGroup
            } else {
                return .cannotLeaveGroupAsWeAreTheOnlyAdmin
            }
        }
    }
    

    // MARK: On save
    
    private var changedKeys = Set<String>()

    public override func willSave() {
        super.willSave()
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }
    
    public override func didSave() {
        super.didSave()

        defer {
            changedKeys.removeAll()
            isInsertedWhileRestoringSyncSnapshot = false
        }
        
        guard !isInsertedWhileRestoringSyncSnapshot else {
            assert(isInserted)
            let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: Self.self))
            os_log("Insertion of a PersistedGroupV2 during a snapshot restore --> we don't send any notification", log: log, type: .info)
            return
        }

        if isDeleted {
            
            ObvMessengerCoreDataNotification.persistedGroupV2WasDeleted(objectID: self.typedObjectID)
                .postOnDispatchQueue()
            
        } else {
            
            if changedKeys.contains(Predicate.Key.updateInProgress.rawValue) && self.updateInProgress == false {
                if let ownedCryptoId = try? self.ownCryptoId {
                    ObvMessengerCoreDataNotification.persistedGroupV2UpdateIsFinished(objectID: self.typedObjectID, ownedCryptoId: ownedCryptoId, groupIdentifier: self.groupIdentifier)
                        .postOnDispatchQueue()
                }
            }
            
            if changedKeys.contains(Predicate.Key.rawOtherMembers.rawValue) {
                if let ownedCryptoId = try? self.ownCryptoId {
                    ObvMessengerCoreDataNotification.otherMembersOfGroupV2DidChange(ownedCryptoId: ownedCryptoId, groupIdentifier: self.groupIdentifier)
                        .postOnDispatchQueue()
                }
            }
            
        }
        
        if isInserted {
            if let ownedCryptoId = try? self.ownCryptoId {
                ObvMessengerCoreDataNotification.aPersistedGroupV2WasInsertedInDatabase(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier)
                    .postOnDispatchQueue()
            }
        }
        
    }
    
    
    // MARK: - Group type and associated permissions
    
    public enum GroupType: Codable, Equatable, Hashable {
        
        case standard
        case managed
        case readOnly
        case advanced(isReadOnly: Bool, remoteDeleteAnythingPolicy: RemoteDeleteAnythingPolicy)

        
        public enum RemoteDeleteAnythingPolicy: String, Codable, Equatable, CaseIterable, Comparable, Identifiable {
            
            case nobody = "nobody"
            case admins = "admins"
            case everyone = "everyone"
            
            public var id: Self { self }
            
            private var sortOrder: Int {
                switch self {
                case .nobody: return 0
                case .admins: return 1
                case .everyone: return 2
                }
            }
            
            public static func < (lhs: ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy, rhs: ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy) -> Bool {
                lhs.sortOrder < rhs.sortOrder
            }

        }
        
        
        private var deserializedGroupType: DeserializedGroupType {
            switch self {
            case .standard:
                return .init(type: .standard, isReadOnly: nil, remoteDeleteAnythingPolicy: nil)
            case .managed:
                return .init(type: .managed, isReadOnly: nil, remoteDeleteAnythingPolicy: nil)
            case .readOnly:
                return .init(type: .readOnly, isReadOnly: nil, remoteDeleteAnythingPolicy: nil)
            case .advanced(isReadOnly: let isReadOnly, remoteDeleteAnythingPolicy: let remoteDeleteAnythingPolicy):
                return .init(type: .advanced, isReadOnly: isReadOnly, remoteDeleteAnythingPolicy: remoteDeleteAnythingPolicy)
            }
        }
        
        
        public func encode(to encoder: Encoder) throws {
            try self.deserializedGroupType.encode(to: encoder)
        }

        
        public init(from decoder: Decoder) throws {
            let deserializedGroupType = try DeserializedGroupType(from: decoder)
            switch deserializedGroupType.type {
            case .standard:
                self = .standard
            case .managed:
                self = .managed
            case .readOnly:
                self = .readOnly
            case .advanced:
                assert(deserializedGroupType.isReadOnly != nil)
                assert(deserializedGroupType.remoteDeleteAnythingPolicy != nil)
                self = .advanced(isReadOnly: deserializedGroupType.isReadOnly ?? false, remoteDeleteAnythingPolicy: deserializedGroupType.remoteDeleteAnythingPolicy ?? .nobody)
            }
        }

        
        public func toSerializedGroupType() throws -> Data {
            let encoder = JSONEncoder()
            return try encoder.encode(self.deserializedGroupType)
        }
        
        
        init(serializedGroupType: Data) throws {
            let decoder = JSONDecoder()
            self = try decoder.decode(GroupType.self, from: serializedGroupType)
        }

        
        /// Helper struct, allowing to serialize/deserialize a ``GroupType``.
        private struct DeserializedGroupType: Codable {
            
            let type: GroupTypeValue
            let isReadOnly: Bool? // Only makes sense if type is custom
            let remoteDeleteAnythingPolicy: RemoteDeleteAnythingPolicy? // Only makes sense if type is custom

            enum GroupTypeValue: String, Codable {
                case standard = "simple"
                case managed = "private"
                case readOnly = "read_only"
                case advanced = "custom"
            }

            private enum CodingKeys: String, CodingKey {
                case type = "type"
                case isReadOnly = "ro"
                case remoteDeleteAnythingPolicy = "del"
            }
            
        }
        
    }
    
    
    public enum AdminOrRegularMember {
        case admin
        case regularMember
    }
    
    
    /// Returns the **exact** set of permissions of an admin or a regular member, for a given group type.
    public static func exactPermissions(of adminOrRegularMember: AdminOrRegularMember, forGroupType groupType: GroupType) -> Set<ObvGroupV2.Permission> {

        let permissions: [ObvGroupV2.Permission]
        let isAdmin = adminOrRegularMember == .admin

        switch groupType {

        case .standard:
            permissions = ObvGroupV2.Permission.allCases.filter { permission in
                switch permission {
                case .groupAdmin: return true
                case .remoteDeleteAnything: return false
                case .editOrRemoteDeleteOwnMessages: return true
                case .changeSettings: return true
                case .sendMessage: return true
                }
            }

        case .managed:
            permissions = ObvGroupV2.Permission.allCases.filter { permission in
                switch permission {
                case .groupAdmin: return isAdmin
                case .remoteDeleteAnything: return false
                case .editOrRemoteDeleteOwnMessages: return true
                case .changeSettings: return isAdmin
                case .sendMessage: return true
                }
            }

        case .readOnly:
            permissions = ObvGroupV2.Permission.allCases.filter { permission in
                switch permission {
                case .groupAdmin: return isAdmin
                case .remoteDeleteAnything: return false
                case .editOrRemoteDeleteOwnMessages: return true
                case .changeSettings: return isAdmin
                case .sendMessage: return isAdmin
                }
            }

        case .advanced(isReadOnly: let isReadOnly, remoteDeleteAnythingPolicy: let remoteDeleteAnythingPolicy):
            permissions = ObvGroupV2.Permission.allCases.filter { permission in
                switch permission {
                case .groupAdmin: return isAdmin
                case .remoteDeleteAnything:
                    switch remoteDeleteAnythingPolicy {
                    case .nobody:
                        return false
                    case .admins:
                        return isAdmin
                    case .everyone:
                        return true
                    }
                case .editOrRemoteDeleteOwnMessages: return true
                case .changeSettings: return isAdmin
                case .sendMessage: return isReadOnly ? isAdmin : true
                }
            }
        }
        
        return Set(permissions)
        
    }
    
    
    public var ownPermissions: Set<ObvGroupV2.Permission> {
        var permissions = Set<ObvGroupV2.Permission>()
        for permission in ObvGroupV2.Permission.allCases {
            switch permission {
            case .groupAdmin:
                if ownPermissionAdmin { permissions.insert(permission) }
            case .remoteDeleteAnything:
                if ownPermissionRemoteDeleteAnything { permissions.insert(permission) }
            case .editOrRemoteDeleteOwnMessages:
                if ownPermissionEditOrRemoteDeleteOwnMessages { permissions.insert(permission) }
            case .changeSettings:
                if ownPermissionChangeSettings { permissions.insert(permission) }
            case .sendMessage:
                if ownPermissionSendMessage { permissions.insert(permission) }
            }
        }
        return permissions
    }

    
    /// If a serialized group type is available, this the method returns its deserialized version, provided it is in adequation with the permissions of all group members (including us).
    ///
    /// Note: We don't try to infer the group type if there is no `serializedGroupType`.
    public func getAdequateGroupType() -> GroupType? {
        
        guard let serializedGroupType, let groupType = try? GroupType(serializedGroupType: serializedGroupType) else { return nil }
        
        // Make sure the returned group type is adequate given the own permissions and the other member permissions
        
        let exactPermissionsForAdmins = Self.exactPermissions(of: .admin, forGroupType: groupType)
        let exactPermissionsForRegularMembers = Self.exactPermissions(of: .regularMember, forGroupType: groupType)

        if self.ownedIdentityIsAdmin {
            guard self.ownPermissions == exactPermissionsForAdmins else { return nil }
        } else {
            guard self.ownPermissions == exactPermissionsForRegularMembers else { return nil }
        }
        
        for member in self.otherMembers {
            guard member.permissions == (member.isAnAdmin ? exactPermissionsForAdmins : exactPermissionsForRegularMembers) else { return nil }
        }
        
        // If we reach this point, we can return the group type as it is in adequation with the current permissions of all group members

        return groupType
        
    }
    
    
    // MARK: - Receiving discussion shared configurations

    /// Called when receiving a shared discussion configuration from a contact  indicating this particular group as the target. This method makes sure the contact is allowed to change the configuration.
    func mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration: PersistedDiscussion.SharedConfiguration, receivedFrom contact: PersistedObvContactIdentity) throws -> (sharedSettingHadToBeUpdated: Bool, weShouldSendBackOurSharedSettings: Bool) {
                
        let contactIdentity = contact.identity
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let initiatorAsMember = self.otherMembers.first(where: { $0.identity == contactIdentity }) else {
            throw ObvUICoreDataError.theInitiatorIsNotPartOfTheGroup
        }
        
        guard initiatorAsMember.isAllowedToChangeSettings else {
            throw ObvUICoreDataError.theInitiatorIsNotAllowedToChangeSettings
        }

        guard let discussion = self.discussion else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        let (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettingsIfAllowedTo) = try discussion.mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration)
        
        let weShouldSendBackOurSharedSettings: Bool
        if self.ownPermissionChangeSettings {
            weShouldSendBackOurSharedSettings = weShouldSendBackOurSharedSettingsIfAllowedTo
        } else {
            weShouldSendBackOurSharedSettings = false
        }
        
        return (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettings)
        
    }

    
    /// Called when receiving a shared discussion configuration from another device of an owned identity  indicating this particular group as the target. This method makes sure the contact is allowed to change the configuration.
    func mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration: PersistedDiscussion.SharedConfiguration, receivedFrom ownedIdentity: PersistedObvOwnedIdentity) throws -> (sharedSettingHadToBeUpdated: Bool, weShouldSendBackOurSharedSettings: Bool) {

        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }
        
        guard self.ownedIdentityIsAllowedToChangeSettings else {
            throw ObvUICoreDataError.theOwnedIdentityIsNoAllowedToChangeSettings
        }
        
        guard let discussion = self.discussion else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }

        let (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettingsIfAllowedTo) = try discussion.mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration)
        
        let weShouldSendBackOurSharedSettings: Bool
        if self.ownPermissionChangeSettings {
            weShouldSendBackOurSharedSettings = weShouldSendBackOurSharedSettingsIfAllowedTo
        } else {
            weShouldSendBackOurSharedSettings = false
        }

        return (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettings)
        
    }

    func replaceReceivedDiscussionSharedConfiguration(with expiration: ExpirationJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity) throws -> Bool {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }
        
        guard self.ownedIdentityIsAllowedToChangeSettings else {
            throw ObvUICoreDataError.theOwnedIdentityIsNoAllowedToChangeSettings
        }
        
        guard let discussion = self.discussion else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }

        let sharedSettingHadToBeUpdated = try discussion.replaceReceivedDiscussionSharedConfiguration(with: expiration)
        
        return sharedSettingHadToBeUpdated

    }

    
    // MARK: - Processing wipe requests from contacts and other owned devices

    func processWipeMessageRequest(of messagesToDelete: [MessageReferenceJSON], receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let requester = self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) else {
            throw ObvUICoreDataError.wipeRequestedByNonGroupMember
        }

        guard requester.isAllowedToRemoteDeleteAnything || requester.isAllowedToEditOrRemoteDeleteOwnMessages else {
            assertionFailure()
            throw ObvUICoreDataError.wipeRequestedByMemberNotAllowedToRemoteDelete
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        let infos = try discussion.processWipeMessageRequest(of: messagesToDelete, from: contact.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return infos
        
    }
    
    
    func processWipeMessageRequest(of messagesToDelete: [MessageReferenceJSON], receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }
        
        // We do not check whether the owned identity is allowed to wipe
        
        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        let infos = try discussion.processWipeMessageRequest(of: messagesToDelete, from: ownedIdentity.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return infos

    }
    
    
    // MARK: - Processing delete requests from the owned identity (made on this device)

    func processMessageDeletionRequestRequestedFromCurrentDevice(of ownedIdentity: PersistedObvOwnedIdentity, messageToDelete: PersistedMessage, deletionType: DeletionType) throws -> InfoAboutWipedOrDeletedPersistedMessage {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }
        
        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        switch deletionType {
        case .fromThisDeviceOnly:
            break
        case .fromAllOwnedDevices:
            break
        case .fromAllOwnedDevicesAndAllContactDevices:
            guard !otherMembers.isEmpty else {
                throw ObvUICoreDataError.deleteRequestMakesNoSenseAsGroupHasNoOtherMembers
            }
            guard self.ownedIdentityIsAllowedToRemoteDeleteAnything || (self.ownedIdentityIsAllowedToEditOrRemoteDeleteOwnMessages && messageToDelete is PersistedMessageSent) else {
                throw ObvUICoreDataError.ownedIdentityIsNotAllowedToDeleteThisMessage
            }
        }

        let info = try discussion.processMessageDeletionRequestRequestedFromCurrentDevice(
            of: ownedIdentity,
            messageToDelete: messageToDelete,
            deletionType: deletionType)

        return info
        
    }
    
    
    // MARK: - Receiving messages and attachments from a contact or another owned device

    func createOrOverridePersistedMessageReceived(from contact: PersistedObvContactIdentity, obvMessage: ObvMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, source: ObvMessageSource, receivedLocation: ReceivedLocation?) throws -> (discussionPermanentID: DiscussionPermanentID, messagePermanentId: MessageReceivedPermanentID?) {
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let requester = self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) else {
            throw ObvUICoreDataError.wipeRequestedByNonGroupMember
        }

        guard requester.isAllowedToSendMessage else {
            throw ObvUICoreDataError.messageReceivedByMemberNotAllowedToSendMessage
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        return try discussion.createOrOverridePersistedMessageReceived(
            from: contact,
            obvMessage: obvMessage,
            messageJSON: messageJSON,
            returnReceiptJSON: returnReceiptJSON,
            source: source,
            receivedLocation: receivedLocation)
        
    }
    
    
    func createPersistedMessageSentFromOtherOwnedDevice(from ownedIdentity: PersistedObvOwnedIdentity, obvOwnedMessage: ObvOwnedMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, sentLocation: SentLocation?) throws -> MessageSentPermanentID? {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }
        
        guard ownedIdentityIsAllowedToSendMessage else {
            throw ObvUICoreDataError.ownedIdentityIsNotAllowedToSendMessages
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        return try discussion.createPersistedMessageSentFromOtherOwnedDevice(
            from: ownedIdentity,
            obvOwnedMessage: obvOwnedMessage,
            messageJSON: messageJSON,
            returnReceiptJSON: returnReceiptJSON,
            sentLocation: sentLocation)
    }
    
    
    // MARK: - Processing edit requests

    func processUpdateMessageRequest(_ updateMessageJSON: UpdateMessageJSON, receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {

        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let requester = self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) else {
            throw ObvUICoreDataError.wipeRequestedByNonGroupMember
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }
        
        // Check that the contact is allowed to edit her messages. Note that the check whether the message was written by her is done later.
        
        guard requester.isAllowedToEditOrRemoteDeleteOwnMessages else {
            throw ObvUICoreDataError.updateRequestReceivedByMemberNotAllowedToToEditOrRemoteDeleteOwnMessages
        }
        
        // Request the update
        
        let updatedMessage = try discussion.processUpdateMessageRequest(updateMessageJSON, receivedFromContactCryptoId: contact.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        return updatedMessage
        
    }

    
    func processUpdateMessageRequest(_ updateMessageJSON: UpdateMessageJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        // Check that the owned identity is allowed to edit her messages. Note that the check whether the message was written by her is done later.

        guard ownedIdentityIsAllowedToEditOrRemoteDeleteOwnMessages else {
            throw ObvUICoreDataError.ownedIdentityIsNotAllowedToEditOrRemoteDeleteOwnMessages
        }
        
        // Request the update
        
        let updatedMessage = try discussion.processUpdateMessageRequest(updateMessageJSON, receivedFromOwnedCryptoId: ownedIdentity.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        return updatedMessage

    }
    
    
    func processLocalUpdateMessageRequest(from ownedIdentity: PersistedObvOwnedIdentity, for messageSent: PersistedMessageSent, newTextBody: String?) throws {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        // Check that the owned identity is allowed to edit her messages.

        guard ownedIdentityIsAllowedToEditOrRemoteDeleteOwnMessages else {
            throw ObvUICoreDataError.ownedIdentityIsNotAllowedToEditOrRemoteDeleteOwnMessages
        }

        // Request the update

        try discussion.processLocalUpdateMessageRequest(from: ownedIdentity, for: messageSent, newTextBody: newTextBody)
        
    }
    
//    func processLocalUpdateMessageRequest(from ownedIdentity: PersistedObvOwnedIdentity, for messageSent: PersistedMessageSent, newLocation: ObvLocation?) throws {
//        
//        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
//            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
//        }
//
//        guard let discussion else {
//            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
//        }
//
//        // Request the update
//
//        try discussion.processLocalUpdateMessageRequest(from: ownedIdentity, for: messageSent, newLocation: newLocation)
//        
//    }

    
    // MARK: - Processing discussion (all messages) remote wipe requests

    
    func processRemoteRequestToWipeAllMessagesWithinThisGroupDiscussion(from contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let requester = self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) else {
            throw ObvUICoreDataError.wipeRequestedByNonGroupMember
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }
        
        // Check that the contact is allowed to make this request
        
        guard requester.isAllowedToRemoteDeleteAnything else {
            throw ObvUICoreDataError.requestToDeleteAllMessagesWithinThisGroupDiscussionFromContactNotAllowedToDoSo
        }

        try discussion.processRemoteRequestToWipeAllMessagesWithinThisDiscussion(from: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
    }

    
    /// Return the number of "new" messages that were deleted
    func processRemoteRequestToWipeAllMessagesWithinThisGroupDiscussion(from ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> Int {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        try discussion.processRemoteRequestToWipeAllMessagesWithinThisDiscussion(from: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return discussion.numberOfNewMessages

    }
    
    
    func processDiscussionDeletionRequestFromCurrentDevice(of ownedIdentity: PersistedObvOwnedIdentity, deletionType: DeletionType) throws {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        switch deletionType {
        case .fromThisDeviceOnly:
            break
        case .fromAllOwnedDevices:
            guard ownedIdentity.hasAnotherDeviceWhichIsReachable else {
                throw ObvUICoreDataError.cannotDeleteDiscussionFromAllOwnedDevicesAsOwnedIdentityHasNoOtherReachableDevice
            }
        case .fromAllOwnedDevicesAndAllContactDevices:
            guard !otherMembers.isEmpty else {
                throw ObvUICoreDataError.deleteRequestMakesNoSenseAsGroupHasNoOtherMembers
            }
            guard self.ownedIdentityIsAllowedToRemoteDeleteAnything else {
                throw ObvUICoreDataError.ownedIdentityIsNotAllowedToDeleteDiscussion
            }
        }
        
        try discussion.processDiscussionDeletionRequestFromCurrentDevice(of: ownedIdentity, deletionType: deletionType)
        
    }

    
    // MARK: - Process reaction requests

    func processSetOrUpdateReactionOnMessageLocalRequest(from ownedIdentity: PersistedObvOwnedIdentity, for message: PersistedMessage, newEmoji: String?) throws {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        try discussion.processSetOrUpdateReactionOnMessageLocalRequest(from: ownedIdentity, for: message, newEmoji: newEmoji)
        
    }

    
    func processSetOrUpdateReactionOnMessageRequest(_ reactionJSON: ReactionJSON, receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date, overrideExistingReaction: Bool) throws -> PersistedMessage? {

        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard self.otherMembers.contains(where: { $0.identity == contact.cryptoId.getIdentity() }) else {
            throw ObvUICoreDataError.contactNeitherGroupOwnerNorPartOfGroupMembers
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }
        
        let updatedMessage = try discussion.processSetOrUpdateReactionOnMessageRequest(reactionJSON, receivedFrom: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer, overrideExistingReaction: overrideExistingReaction)
        
        return updatedMessage

    }


    func processSetOrUpdateReactionOnMessageRequest(_ reactionJSON: ReactionJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        guard ownedIdentityIsAllowedToSendMessage else {
            throw ObvUICoreDataError.ownedIdentityIsNotAllowedToSendMessages
        }
                
        let updatedMessage = try discussion.processSetOrUpdateReactionOnMessageRequest(reactionJSON, receivedFrom: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return updatedMessage

    }
    
    
    // MARK: - Process screen capture detections

    func processDetectionThatSensitiveMessagesWereCaptured(_ screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, from contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) != nil else {
            throw ObvUICoreDataError.wipeRequestedByNonGroupMember
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        try discussion.processDetectionThatSensitiveMessagesWereCaptured(screenCaptureDetectionJSON, from: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
    }
    
    
    func processDetectionThatSensitiveMessagesWereCaptured(_ screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, from ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        try discussion.processDetectionThatSensitiveMessagesWereCaptured(screenCaptureDetectionJSON, from: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

    }

    
    func processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by ownedIdentity: PersistedObvOwnedIdentity) throws {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        try discussion.processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by: ownedIdentity)
        
    }


    // MARK: - Process requests for group v2 shared settings

    func processQuerySharedSettingsRequest(from contact: PersistedObvContactIdentity, querySharedSettingsJSON: QuerySharedSettingsJSON) throws -> (weShouldSendBackOurSharedSettings: Bool, discussionId: DiscussionIdentifier) {
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) != nil else {
            throw ObvUICoreDataError.wipeRequestedByNonGroupMember
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        let discussionId = try discussion.identifier
        let weShouldSendBackOurSharedSettings = try discussion.processQuerySharedSettingsRequest(querySharedSettingsJSON: querySharedSettingsJSON)
        
        return (weShouldSendBackOurSharedSettings, discussionId)
        
    }

    
    func processQuerySharedSettingsRequest(from ownedIdentity: PersistedObvOwnedIdentity, querySharedSettingsJSON: QuerySharedSettingsJSON) throws -> (weShouldSendBackOurSharedSettings: Bool, discussionId: DiscussionIdentifier) {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvUICoreDataError.persistedGroupV2DiscussionIsNil
        }

        let discussionId = try discussion.identifier
        let weShouldSendBackOurSharedSettings = try discussion.processQuerySharedSettingsRequest(querySharedSettingsJSON: querySharedSettingsJSON)
        
        return (weShouldSendBackOurSharedSettings, discussionId)
        
    }
    
}


// MARK: - PersistedGroupV2Member

@objc(PersistedGroupV2Member)
public final class PersistedGroupV2Member: NSManagedObject, Identifiable {
    
    private static let entityName = "PersistedGroupV2Member"

    // Attributes
    
    @NSManaged private var company: String?
    @NSManaged public private(set) var firstName: String?
    @NSManaged private var groupIdentifier: Data // Part of primary key
    @NSManaged public private(set) var identity: Data // Part of primary key
    @NSManaged public private(set) var isPending: Bool
    @NSManaged public private(set) var lastName: String?
    @NSManaged fileprivate var normalizedSearchKey: String
    @NSManaged public private(set) var normalizedSortKey: String
    @NSManaged private var permissionAdmin: Bool
    @NSManaged private var permissionChangeSettings: Bool
    @NSManaged private var permissionEditOrRemoteDeleteOwnMessages: Bool
    @NSManaged private var permissionRemoteDeleteAnything: Bool
    @NSManaged private var permissionSendMessage: Bool
    @NSManaged private var position: String?
    @NSManaged private var rawOwnedIdentityIdentity: Data // Part of primary key

    // Relationships
    
    @NSManaged private var rawContact: PersistedObvContactIdentity? // Expected to be non nil for a member, potentially nil for a pending member
    @NSManaged private var rawGroup: PersistedGroupV2?

    // Accessors
    
    public var userIdentifier: ObvContactIdentifier {
        get throws {
            let ownedCryptoId = try ObvCryptoId(identity: rawOwnedIdentityIdentity)
            let cryptoId = try ObvCryptoId(identity: identity)
            return .init(contactCryptoId: cryptoId, ownedCryptoId: ownedCryptoId)
        }
    }
    
    public var asPersistedUser: PersistedUser {
        get throws {
            if let rawContact {
                return try PersistedUser(contact: rawContact)
            } else {
                return try PersistedUser(groupMember: self)
            }
        }
    }
    
    public var cryptoId: ObvCryptoId? {
        return try? ObvCryptoId(identity: identity)
    }
    
    public var forcedUnwrapCryptoId: ObvCryptoId {
        return self.cryptoId!
    }
    
    public var contact: PersistedObvContactIdentity? {
        rawContact
    }
    
    public var displayedFirstName: String? {
        if let rawContact = self.rawContact {
            return rawContact.displayedFirstName
        } else {
            return firstName
        }
    }
    
    public var isKeycloakManaged: Bool {
        if contact?.isCertifiedByOwnKeycloak == true {
            return true
        } else {
            return false
        }
    }
    
    public var displayedCustomDisplayNameOrLastName: String? {
        if let rawContact = self.rawContact {
            return rawContact.displayedCustomDisplayNameOrLastName
        } else {
            return lastName
        }
    }

    public var displayedCustomDisplayNameOrFirstNameOrLastName: String? {
        if let rawContact = self.rawContact {
            return rawContact.displayedCustomDisplayNameOrFirstNameOrLastName
        } else {
            return firstName ?? lastName
        }
    }

    public var displayedCompany: String? {
        if let rawContact = self.rawContact {
            return rawContact.displayedCompany
        } else {
            return company
        }
    }

    public var displayedPosition: String? {
        if let rawContact = self.rawContact {
            return rawContact.displayedPosition
        } else {
            return position
        }
    }
    
    var displayedCustomDisplayName: String? {
        rawContact?.customDisplayName
    }
    
    public var displayedProfilePicture: UIImage? {
        rawContact?.displayedProfilePicture
    }
    
    var displayedContactGroup: DisplayedContactGroup? {
        rawGroup?.displayedContactGroup
    }
    
    public var permissions: Set<ObvGroupV2.Permission> {
        var permissions = Set<ObvGroupV2.Permission>()
        for permission in ObvGroupV2.Permission.allCases {
            switch permission {
            case .groupAdmin:
                if permissionAdmin { permissions.insert(permission) }
            case .remoteDeleteAnything:
                if permissionRemoteDeleteAnything { permissions.insert(permission) }
            case .editOrRemoteDeleteOwnMessages:
                if permissionEditOrRemoteDeleteOwnMessages { permissions.insert(permission) }
            case .changeSettings:
                if permissionChangeSettings { permissions.insert(permission) }
            case .sendMessage:
                if permissionSendMessage { permissions.insert(permission) }
            }
        }
        return permissions
    }
    
    public var isAnAdmin: Bool {
        return permissionAdmin
    }
    
    public var isAllowedToChangeSettings: Bool {
        return permissionChangeSettings
    }
    
    public var isAllowedToEditOrRemoteDeleteOwnMessages: Bool {
        return permissionRemoteDeleteAnything || permissionEditOrRemoteDeleteOwnMessages
    }
    
    public var isAllowedToRemoteDeleteAnything: Bool {
        return permissionRemoteDeleteAnything
    }

    var isAllowedToSendMessage: Bool {
        return permissionSendMessage
    }

    public var permissionChangeSettingsIsUpdated: Bool {
        Set<String>(self.changedValues().keys).contains(Predicate.Key.permissionChangeSettings.rawValue)
    }
    
    fileprivate var cryptoIdWhenDeleted: ObvCryptoId?

    /// Used when restoring a sync snapshot or when restoring a backup to prevent any notification on insertion
    private var isInsertedWhileRestoringSyncSnapshot = false

    // Initializer
    
    fileprivate convenience init(identityAndPermissionsAndDetails: ObvGroupV2.IdentityAndPermissionsAndDetails, groupIdentifier: Data, ownCryptoId: ObvCryptoId, persistedGroupV2: PersistedGroupV2, isRestoringSyncSnapshotOrBackup: Bool) throws {
        
        guard let context = persistedGroupV2.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        
        let contact = try PersistedObvContactIdentity.get(contactCryptoId: identityAndPermissionsAndDetails.identity,
                                                          ownedIdentityCryptoId: ownCryptoId,
                                                          whereOneToOneStatusIs: .any,
                                                          within: context)
        
        guard contact != nil || identityAndPermissionsAndDetails.isPending else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotFindPersistedObvContactIdentityAlthoughMemberIsNotPending
        }

        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.isInsertedWhileRestoringSyncSnapshot = isRestoringSyncSnapshotOrBackup

        self.rawContact = contact
        self.rawGroup = persistedGroupV2
        
        // If PersistedObvContactIdentity is not nil, it means we are in contact with the member, we can add a message system telling that this member has joined the group
        if let contact {
            try? self.rawGroup?.discussion?.groupMemberHasJoined(contact)
        }

        self.groupIdentifier = groupIdentifier
        try self.updateWith(identityAndPermissionsAndDetails: identityAndPermissionsAndDetails)
        self.rawOwnedIdentityIdentity = ownCryptoId.getIdentity()
        
    }
    

    fileprivate func updateWith(identityAndPermissionsAndDetails: ObvGroupV2.IdentityAndPermissionsAndDetails) throws {
        if self.identity != identityAndPermissionsAndDetails.identity.getIdentity() {
            self.identity = identityAndPermissionsAndDetails.identity.getIdentity()
        }
        if self.isPending != identityAndPermissionsAndDetails.isPending {
            self.isPending = identityAndPermissionsAndDetails.isPending
        }
        if self.permissionAdmin != identityAndPermissionsAndDetails.permissions.contains(.groupAdmin) {
            self.permissionAdmin = identityAndPermissionsAndDetails.permissions.contains(.groupAdmin)
        }
        if self.permissionChangeSettings != identityAndPermissionsAndDetails.permissions.contains(.changeSettings) {
            self.permissionChangeSettings = identityAndPermissionsAndDetails.permissions.contains(.changeSettings)
        }
        if self.permissionEditOrRemoteDeleteOwnMessages != identityAndPermissionsAndDetails.permissions.contains(.editOrRemoteDeleteOwnMessages) {
            self.permissionEditOrRemoteDeleteOwnMessages = identityAndPermissionsAndDetails.permissions.contains(.editOrRemoteDeleteOwnMessages)
        }
        if self.permissionRemoteDeleteAnything != identityAndPermissionsAndDetails.permissions.contains(.remoteDeleteAnything) {
            self.permissionRemoteDeleteAnything = identityAndPermissionsAndDetails.permissions.contains(.remoteDeleteAnything)
        }
        if self.permissionSendMessage != identityAndPermissionsAndDetails.permissions.contains(.sendMessage) {
            self.permissionSendMessage = identityAndPermissionsAndDetails.permissions.contains(.sendMessage)
        }
        let coreDetails = try ObvIdentityCoreDetails.jsonDecode(identityAndPermissionsAndDetails.serializedIdentityCoreDetails)
        if self.firstName != coreDetails.firstName {
            self.firstName = coreDetails.firstName
        }
        if self.lastName != coreDetails.lastName {
            self.lastName = coreDetails.lastName
        }
        if self.position != coreDetails.position {
            self.position = coreDetails.position
        }
        if self.company != coreDetails.company {
            self.company = coreDetails.company
        }
        self.updateNormalizedSortAndSearchKeys(with: ObvMessengerSettings.Interface.contactsSortOrder)
    }
    

    func updateWith(persistedContact: PersistedObvContactIdentity) throws {
        guard self.rawContact != persistedContact else { return }
        guard identity == persistedContact.identity else {
            throw ObvUICoreDataError.tryingToUpdateMemberWithPersistedContactThatDoesNotHaveAppropriateIdentity
        }
        guard rawOwnedIdentityIdentity == persistedContact.ownedIdentity?.identity else {
            throw ObvUICoreDataError.tryingToUpdateMemberWithPersistedContactThatDoesNotHaveAppropriateAssociatedOwnedIdentity
        }
        self.rawContact = persistedContact
        
        // If the current groupV2Member's raw contact is being updated, it means the contact was not previously known to the owned identity, we can create an system message telling that the member has joined the group.
        try? self.rawGroup?.discussion?.groupMemberHasJoined(persistedContact)
        
        self.updateNormalizedSortAndSearchKeys(with: ObvMessengerSettings.Interface.contactsSortOrder)
    }
    
    
    /// When a contact changes, this method is called to make sure the corresponding `PersistedGroupV2Member` sortKey stays in sync.
    /// It is also used when creating a `PersistedGroupV2Member` instance, so as to use the details
    public func updateNormalizedSortAndSearchKeys(with sortOrder: ContactsSortOrder) {
        
        // Update the search key
        
        let newNormalizedSearchKey: String
        if let rawContact = rawContact {
            newNormalizedSearchKey = rawContact.sortDisplayName
        } else {
            newNormalizedSearchKey = sortOrder.computeNormalizedSortAndSearchKey(
                customDisplayName: nil,
                firstName: self.firstName,
                lastName: self.lastName,
                position: self.position,
                company: self.company,
                personalNote: nil)
        }
        // The equality test is required since this method is also called from the willSave method of PersistedObvContactIdentity
        if self.normalizedSearchKey != newNormalizedSearchKey {
            self.normalizedSearchKey = newNormalizedSearchKey
        }

        // Update the sort key (making sure we cannot have two equal sort keys for distinct objects)
        
        let newNormalizedSortKey = [newNormalizedSearchKey,
                                    groupIdentifier.hexString(),
                                    identity.hexString()].joined()

        // The equality test is required since this method is also called from the willSave method of PersistedObvContactIdentity

        if self.normalizedSortKey != newNormalizedSortKey {
            self.normalizedSortKey = newNormalizedSortKey
        }
    }
    
    
    func updateWhenPersistedObvContactIdentityIsUpdated() {
        updateNormalizedSortAndSearchKeys(with: ObvMessengerSettings.Interface.contactsSortOrder)
        rawGroup?.updateWhenPersistedGroupV2MemberIsUpdated()
    }

    
    public func setPermissions(to permissions: Set<ObvGroupV2.Permission>) {
        for permission in ObvGroupV2.Permission.allCases {
            switch permission {
            case .groupAdmin:
                let newPermissionValue = permissions.contains(permission)
                if self.permissionAdmin != newPermissionValue {
                    self.permissionAdmin = newPermissionValue
                }
            case .remoteDeleteAnything:
                let newPermissionValue = permissions.contains(permission)
                if self.permissionRemoteDeleteAnything != newPermissionValue {
                    self.permissionRemoteDeleteAnything = newPermissionValue
                }
            case .editOrRemoteDeleteOwnMessages:
                let newPermissionValue = permissions.contains(permission)
                if self.permissionEditOrRemoteDeleteOwnMessages != newPermissionValue {
                    self.permissionEditOrRemoteDeleteOwnMessages = newPermissionValue
                }
            case .changeSettings:
                let newPermissionValue = permissions.contains(permission)
                if self.permissionChangeSettings != newPermissionValue {
                    self.permissionChangeSettings = newPermissionValue
                }
            case .sendMessage:
                let newPermissionValue = permissions.contains(permission)
                if self.permissionSendMessage != newPermissionValue {
                    self.permissionSendMessage = newPermissionValue
                }
            }
        }
    }
    

    fileprivate func delete() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        cryptoIdWhenDeleted = self.cryptoId
        
        // If current member to be deleted is part of a group discussion, we create a message system to the group telling the member has left.
        if let rawContact {
            try? rawGroup?.discussion?.groupMemberHasLeft(rawContact)
        }
        
        context.delete(self)
    }

    
    // MARK: Convenience DB getters

    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedGroupV2Member> {
        return NSFetchRequest<PersistedGroupV2Member>(entityName: self.entityName)
    }

    public struct Predicate {
        public enum Key: String {
            // Attributes
            case company = "company"
            case firstName = "firstName"
            case groupIdentifier = "groupIdentifier"
            case identity = "identity"
            case isPending = "isPending"
            case lastName = "lastName"
            case normalizedSearchKey = "normalizedSearchKey"
            case normalizedSortKey = "normalizedSortKey"
            case permissionAdmin = "permissionAdmin"
            case permissionChangeSettings = "permissionChangeSettings"
            case permissionRemoteDelete = "permissionRemoteDelete"
            case permissionSendMessage = "permissionSendMessage"
            case position = "position"
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
            // Relationships
            case rawContact = "rawContact"
            case rawGroup = "rawGroup"
        }
        static func withOwnCryptoId(_ ownCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownCryptoId.getIdentity())
        }
        static var withNoAssociatedRawGroup: NSPredicate {
            NSPredicate(withNilValueForKey: Key.rawGroup)
        }
        static func withCryptoId(_ contactCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.identity, EqualToData: contactCryptoId.getIdentity())
        }
        static func withGroupIdentifier(_ groupIdentifier: Data) -> NSPredicate {
            NSPredicate(Key.groupIdentifier, EqualToData: groupIdentifier)
        }
        static var withNoAssociatedContact: NSPredicate {
            NSPredicate(withNilValueForKey: Key.rawContact)
        }
    }


    public static func getAllPersistedGroupV2MemberOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [PersistedGroupV2Member] {
        let request: NSFetchRequest<PersistedGroupV2Member> = PersistedGroupV2Member.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.normalizedSortKey.rawValue, ascending: true)]
        request.predicate = Predicate.withOwnCryptoId(ownedCryptoId)
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }


    public static func deleteOrphanedPersistedGroupV2Members(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<PersistedGroupV2Member> = PersistedGroupV2Member.fetchRequest()
        request.predicate = Predicate.withNoAssociatedRawGroup
        request.fetchBatchSize = 1_000
        let values = try context.fetch(request)
        for value in values {
            try value.delete()
        }
    }
    
    
    /// This is typically used to update all members that still aren't associated to a persisted contact because it did not exist at the time the member was created.
    /// When creating the contact, we want to update all member instances that correspond to this contact, i.e., we want to set their `rawContact` relationship.
    /// Doing so will have a side effect: we will send all the messages waiting for this member to accept the invitation.
    static func getAllPersistedGroupV2MemberOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, withIdentity identity: ObvCryptoId, within context: NSManagedObjectContext) throws -> Set<PersistedGroupV2Member> {
        let request: NSFetchRequest<PersistedGroupV2Member> = PersistedGroupV2Member.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(ownedCryptoId),
            Predicate.withCryptoId(identity),
        ])
        request.fetchBatchSize = 1_000
        let values = try context.fetch(request)
        for value in values {
            assert(value.rawContact == nil)
        }
        return Set(values)
    }

    
    public static func getPredicateForAllPersistedGroupV2MemberWithNoAssociatedContactOfGroup(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV2Identifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            Self.Predicate.withOwnCryptoId(ownedCryptoId),
            Self.Predicate.withGroupIdentifier(groupIdentifier),
            Self.Predicate.withNoAssociatedContact,
        ])
    }
    
    
    public static func getFetchRequest(withPredicate predicate: NSPredicate) -> NSFetchRequest<PersistedGroupV2Member> {
        let request: NSFetchRequest<PersistedGroupV2Member> = PersistedGroupV2Member.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.normalizedSortKey.rawValue, ascending: true)]
        request.fetchBatchSize = 1_000
        return request
    }
    
    
    // MARK: Computing changesets

    @MainActor fileprivate func computeChange() throws -> ObvGroupV2.Change? {
        guard self.hasChanges else { return nil }
        guard let cryptoId = cryptoId else { throw ObvUICoreDataError.couldNotGetAddedMemberCryptoId }
        if self.isInserted {
            return .memberAdded(contactCryptoId: cryptoId, permissions: self.permissions)
        } else if self.isDeleted {
            return .memberRemoved(contactCryptoId: cryptoId)
        } else if self.isUpdated {
            return .memberChanged(contactCryptoId: cryptoId, permissions: self.permissions)
        } else {
            assertionFailure()
            return nil
        }
    }
    
    
    // MARK: Reacting to changes
    
    private var changedKeys = Set<String>()
    
    public override func willSave() {
        super.willSave()
        
        if !isInserted && !isDeleted {
            changedKeys = Set<String>(self.changedValues().keys)
        }
        
    }
    
    public override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
            isInsertedWhileRestoringSyncSnapshot = false
        }
        
        guard !isInsertedWhileRestoringSyncSnapshot else {
            assert(isInserted)
            let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: Self.self))
            os_log("Insertion of a PersistedGroupV2 during a snapshot restore --> we don't send any notification", log: log, type: .info)
            return
        }

        if changedKeys.contains(Predicate.Key.isPending.rawValue), !self.isPending, let contactObjectID = contact?.typedObjectID {
            ObvMessengerCoreDataNotification.aPersistedGroupV2MemberChangedFromPendingToNonPending(contactObjectID: contactObjectID)
                .postOnDispatchQueue()
        }
        
    }

}


// MARK: - PersistedGroupV2Details

@objc(PersistedGroupV2Details)
public final class PersistedGroupV2Details: NSManagedObject {
    
    private static let entityName = "PersistedGroupV2Details"

    // Attributes
    
    @NSManaged private(set) var groupDescription: String?
    @NSManaged private(set) var name: String?
    @NSManaged public private(set) var photoURLFromEngine: URL?

    // Relationships

    @NSManaged private var asPublishedDetailsOfGroup: PersistedGroupV2? // Expected to be non nil if asTrustedDetailsOfGroup is nil
    @NSManaged private var asTrustedDetailsOfGroup: PersistedGroupV2? // Expected to be non nil if asPublishedDetailsOfGroup is nil
    
    // Computed variables
    
    public var coreDetails: GroupV2CoreDetails {
        return GroupV2CoreDetails(groupName: name, groupDescription: groupDescription)
    }

    // Initializer
    
    fileprivate convenience init(trustedDetailsAndPhoto: ObvGroupV2.DetailsAndPhoto, persistedGroupV2: PersistedGroupV2) throws {
        
        try self.init(detailsAndPhoto: trustedDetailsAndPhoto, persistedGroupV2: persistedGroupV2)

        self.asPublishedDetailsOfGroup = nil
        self.asTrustedDetailsOfGroup = persistedGroupV2

    }

    
    fileprivate convenience init(publishedDetailsAndPhoto: ObvGroupV2.DetailsAndPhoto, persistedGroupV2: PersistedGroupV2) throws {

        try self.init(detailsAndPhoto: publishedDetailsAndPhoto, persistedGroupV2: persistedGroupV2)

        self.asPublishedDetailsOfGroup = persistedGroupV2
        self.asTrustedDetailsOfGroup = nil

    }
    

    /// Return `true` iff details needed to be updated
    fileprivate func updateWithDetailsAndPhoto(_ detailsAndPhoto: ObvGroupV2.DetailsAndPhoto) throws -> Bool {
        let coreDetails = try GroupV2CoreDetails.jsonDecode(serializedGroupCoreDetails: detailsAndPhoto.serializedGroupCoreDetails)
        var changed = false
        if self.groupDescription != coreDetails.groupDescription {
            self.groupDescription = coreDetails.groupDescription
            changed = true
        }
        if self.name != coreDetails.groupName {
            self.name = coreDetails.groupName
            changed = true
        }
        if self.photoURLFromEngine != detailsAndPhoto.photoURLFromEngine.url {
            self.photoURLFromEngine = detailsAndPhoto.photoURLFromEngine.url
            changed = true
        }
        return changed
    }

    
    private convenience init(detailsAndPhoto: ObvGroupV2.DetailsAndPhoto, persistedGroupV2: PersistedGroupV2) throws {
        
        guard let context = persistedGroupV2.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }

        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        _ = try self.updateWithDetailsAndPhoto(detailsAndPhoto)

    }
    
}


// MARK: MentionableIdentity

/// Allows a `PersistedGroupV2Member` to be displayed in the views showing mentions.
extension PersistedGroupV2Member: MentionableIdentity {
    
    public var mentionnedCryptoId: ObvCryptoId? {
        return self.cryptoId
    }
    
    public var mentionSearchMatcher: String {
        return normalizedSortKey
    }

    public var mentionPickerTitle: String {
        if let displayedCustomDisplayName {
            return displayedCustomDisplayName
        }

        return mentionPersistedName
    }

    public var mentionPickerSubtitle: String? {
        if displayedCustomDisplayName == nil {
            return nil
        }

        return mentionPersistedName
    }

    public var circledInitialsConfiguration: CircledInitialsConfiguration {
        if let contact {
            return contact.circledInitialsConfiguration
        }

        guard let cryptoId else {
            return .icon(.lockFill)
        }

        return .contact(initial: mentionPersistedName, //ignore the nickname, the user hasn't been synced yet
                        photo: nil,
                        showGreenShield: false,
                        showRedShield: false,
                        cryptoId: cryptoId,
                        tintAdjustementMode: .disabled)
    }

    public var mentionPersistedName: String {
        
        if let contact, !contact.mentionPersistedName.isEmpty {
            return contact.mentionPersistedName
        } else {
            let components = PersonNameComponents()..{
                $0.givenName = firstName
                $0.familyName = lastName
            }

            return PersonNameComponentsFormatter.localizedString(from: components,
                                                                 style: .default)
        }
        
    }

    public var innerIdentity: MentionableIdentityTypes.InnerIdentity {
        return .groupV2Member(typedObjectID)
    }
}



// MARK: - For snapshot purposes

extension PersistedGroupV2 {
    
    var syncSnapshotNode: PersistedGroupV2SyncSnapshotNode {
        .init(customName: customName,
              personalNote: personalNote,
              discussion: discussion)
    }
    
}


struct PersistedGroupV2SyncSnapshotNode: ObvSyncSnapshotNode {
    
    private let domain: Set<CodingKeys>
    private let customName: String?
    private let personalNote: String?
    private let discussionConfiguration: PersistedDiscussionConfigurationSyncSnapshotNode?

    let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case customName = "custom_name"
        case personalNote = "personal_note"
        case discussionConfiguration = "discussion_customization"
        case domain = "domain"
    }

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    
    init(customName: String?, personalNote: String?, discussion: PersistedGroupV2Discussion?) {
        self.customName = customName
        self.personalNote = personalNote
        self.discussionConfiguration = discussion?.syncSnapshotNode
        self.domain = Self.defaultDomain
    }
    
    
    // Synthesized implementation of encode(to encoder: Encoder)


    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
        self.customName = try values.decodeIfPresent(String.self, forKey: .customName)
        self.personalNote = try values.decodeIfPresent(String.self, forKey: .personalNote)
        self.discussionConfiguration = try values.decodeIfPresent(PersistedDiscussionConfigurationSyncSnapshotNode.self, forKey: .discussionConfiguration)
    }

    
    func useToUpdate(_ group: PersistedGroupV2) {
        
        if domain.contains(.customName) {
            _  = try? group.updateCustomNameWith(with: customName)
        }
        
        if domain.contains(.personalNote) {
            _ = group.setNote(to: personalNote)
        }
        
        if domain.contains(.discussionConfiguration) {
            if let discussion = group.discussion {
                discussionConfiguration?.useToUpdate(discussion)
            }
        }
        
    }
 
}
