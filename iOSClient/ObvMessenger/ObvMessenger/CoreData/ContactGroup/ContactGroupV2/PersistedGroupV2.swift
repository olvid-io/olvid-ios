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
import CoreData
import OlvidUtils
import ObvTypes
import CryptoKit
import os.log


@objc(PersistedGroupV2)
final class PersistedGroupV2: NSManagedObject, ObvErrorMaker {
    
    private static let entityName = "PersistedGroupV2"
    static let errorDomain = "PersistedGroupV2"

    // Attributes
    
    @NSManaged private(set) var customName: String?
    @NSManaged private var customPhotoFilename: String?
    @NSManaged private(set) var groupIdentifier: Data // Part of primary key
    @NSManaged private var keycloakManaged: Bool
    @NSManaged private var namesOfOtherMembers: String?
    @NSManaged private var ownPermissionAdmin: Bool
    @NSManaged private var ownPermissionChangeSettings: Bool
    @NSManaged private var ownPermissionEditOrRemoteDeleteOwnMessages: Bool
    @NSManaged private var ownPermissionRemoteDeleteAnything: Bool
    @NSManaged private var ownPermissionSendMessage: Bool
    @NSManaged private var personalNote: String?
    @NSManaged private var rawOwnedIdentityIdentity: Data // Part of primary key
    @NSManaged private var rawPublishedDetailsStatus: Int
    @NSManaged private(set) var updateInProgress: Bool

    // Relationships
    
    @NSManaged private var detailsPublished: PersistedGroupV2Details? // Non-nil iff there are untrusted new details
    @NSManaged private(set) var detailsTrusted: PersistedGroupV2Details? // Expected to be non nil
    @NSManaged private var rawDiscussion: PersistedGroupV2Discussion? // Expected to be non nil
    @NSManaged private(set) var displayedContactGroup: DisplayedContactGroup? // Expected to be non nil
    @NSManaged private var rawOtherMembers: Set<PersistedGroupV2Member>
    @NSManaged private var rawOwnedIdentity: PersistedObvOwnedIdentity? // Expected to be non nil

    // Accessors
    
    var otherMembers: Set<PersistedGroupV2Member> {
        rawOtherMembers
    }
    
    var otherMembersSorted: [PersistedGroupV2Member] {
        otherMembers.sorted(by: { $0.normalizedSortKey < $1.normalizedSortKey })
    }
    
    var contactsAmongOtherPendingAndNonPendingMembers: Set<PersistedObvContactIdentity> {
        Set(rawOtherMembers.compactMap({ $0.contact }))
    }

    var contactsAmongNonPendingOtherMembers: Set<PersistedObvContactIdentity> {
        Set(rawOtherMembers.filter({ !$0.isPending }).compactMap({ $0.contact }))
    }

    var ownCryptoId: ObvCryptoId {
        get throws {
            try ObvCryptoId(identity: rawOwnedIdentityIdentity)
        }
    }
    
    var ownedIdentityIdentity: Data {
        return rawOwnedIdentityIdentity
    }
    
    /// Expected to be non nil
    var persistedOwnedIdentity: PersistedObvOwnedIdentity? {
        return rawOwnedIdentity
    }
    
    var ownedIdentityIsAdmin: Bool {
        return ownPermissionAdmin
    }
    
    var ownedIdentityIsAllowedToChangeSettings: Bool {
        return ownPermissionChangeSettings
    }
    
    var ownedIdentityIsAllowedToEditOrRemoteDeleteOwnMessages: Bool {
        return ownPermissionRemoteDeleteAnything || ownPermissionEditOrRemoteDeleteOwnMessages
    }
    
    var ownedIdentityIsAllowedToRemoteDeleteAnything: Bool {
        return ownPermissionRemoteDeleteAnything
    }
    
    var ownedIdentityIsAllowedToSendMessage: Bool {
        return ownPermissionSendMessage
    }
    
    var discussion: PersistedGroupV2Discussion? {
        return rawDiscussion
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

    // Initializer
    
    private convenience init(obvGroupV2: ObvGroupV2, shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: Bool, within context: NSManagedObjectContext) throws {
        
        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvGroupV2.ownIdentity, within: context) else {
            assertionFailure()
            throw Self.makeError(message: "Could not find owned identity")
        }

        guard try Self.getWithPrimaryKey(ownCryptoId: obvGroupV2.ownIdentity, groupIdentifier: obvGroupV2.appGroupIdentifier, within: context) == nil else {
            assertionFailure()
            throw Self.makeError(message: "PersistedGroupV2 already exists")
        }

        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedGroupV2.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.rawOwnedIdentity = ownedIdentity
        updateAttributes(obvGroupV2: obvGroupV2)
        try updateRelationships(obvGroupV2: obvGroupV2,
                                shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion)
        updateNamesOfOtherMembers()
        
    }
    
    
    private func updateAttributes(obvGroupV2: ObvGroupV2) {
        self.groupIdentifier = obvGroupV2.appGroupIdentifier
        self.keycloakManaged = false
        self.namesOfOtherMembers = nil // Updated later
        let newOwnPermissionAdmin = obvGroupV2.ownPermissions.contains(.groupAdmin)
        if newOwnPermissionAdmin != self.ownPermissionAdmin {
            if newOwnPermissionAdmin {
                try? discussion?.ownedIdentityBecameAnAdmin()
            } else {
                try? discussion?.ownedIdentityIsNoLongerAnAdmin()
            }
            self.ownPermissionAdmin = newOwnPermissionAdmin
        }
        self.ownPermissionChangeSettings = obvGroupV2.ownPermissions.contains(.changeSettings)
        self.ownPermissionEditOrRemoteDeleteOwnMessages = obvGroupV2.ownPermissions.contains(.editOrRemoteDeleteOwnMessages)
        self.ownPermissionRemoteDeleteAnything = obvGroupV2.ownPermissions.contains(.remoteDeleteAnything)
        self.ownPermissionSendMessage = obvGroupV2.ownPermissions.contains(.sendMessage)
        self.personalNote = nil
        self.rawOwnedIdentityIdentity = obvGroupV2.ownIdentity.getIdentity()
        self.updateInProgress = obvGroupV2.updateInProgress
        displayedContactGroup?.updateUsingUnderlyingGroup()
        try? discussion?.resetTitle(to: self.displayName)
    }
    
    
    /// The `namesOfOtherMembers` attribute is essentially used to display a group name when no specific name was specified.
    /// This method allows to update this attribute.
    private func updateNamesOfOtherMembers() {
        let names = otherMembers.map({ $0.displayedCustomDisplayNameOrFirstNameOrLastName ?? "" }).sorted()
        if #available(iOS 15, *) {
            self.namesOfOtherMembers = names.formatted(.list(type: .and, width: .short))
        } else {
            self.namesOfOtherMembers = names.joined(separator: ", ")
        }
        displayedContactGroup?.updateUsingUnderlyingGroup()
        try? discussion?.resetTitle(to: self.displayName)
    }
    
    
    /// This method moves the photo at the indicated URL to a proper location.
    func updateCustomPhotoWithPhotoAtURL(_ url: URL?, within obvContext: ObvContext) throws {
        
        defer {
            displayedContactGroup?.updateUsingUnderlyingGroup()
            // No need to reset the discussion title
            discussion?.setHasUpdates() // Makes sure the photo is updated in the discussion list
        }
        
        guard self.managedObjectContext == obvContext.context else {
            throw Self.makeError(message: "Unexpected context")
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
        
        // If received url is nil, there is nothing left to do
        
        guard let url = url else { return }

        // Make sure there is a file a the received URL
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Self.makeError(message: "Could not find file at url \(url.debugDescription)")
        }
        
        // Move the file at the received URL to a proper location (if the context saves without error)

        let newCustomFilename = UUID().uuidString
        self.customPhotoFilename = newCustomFilename
        let customPhotoURL = ObvMessengerConstants.containerURL.forCustomGroupProfilePictures.appendingPathComponent(newCustomFilename)

        do {
            try FileManager.default.linkItem(at: url, to: customPhotoURL)
        } catch {
            try FileManager.default.copyItem(at: url, to: customPhotoURL)
        }
        
        // If the context saves with an error, remove the file we just created
        
        try obvContext.addContextDidSaveCompletionHandler { error in
            if error != nil {
                try? FileManager.default.removeItem(at: customPhotoURL)
            }
        }
        
    }
    
    
    func updateCustomNameWith(with newCustomName: String?) throws {
        guard self.customName != newCustomName else { return }
        self.customName = newCustomName
        displayedContactGroup?.updateUsingUnderlyingGroup()
        try discussion?.resetTitle(to: self.displayName)
    }
    

    private func updateRelationships(obvGroupV2: ObvGroupV2, shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: Bool) throws {
        
        guard let context = managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        
        if let publishedDetailsAndPhoto = obvGroupV2.publishedDetailsAndPhoto {
            if let detailsPublished = self.detailsPublished {
                if try detailsPublished.updateWithDetailsAndPhoto(publishedDetailsAndPhoto) {
                    self.publishedDetailsStatus = .unseenPublishedDetails
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
                    self.publishedDetailsStatus = .unseenPublishedDetails
                }
                
            }
        } else {
            self.detailsPublished = nil
            self.publishedDetailsStatus = .noNewPublishedDetails
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
            self.detailsPublished = nil
            self.publishedDetailsStatus = .noNewPublishedDetails
            ObvMessengerGroupV2Notifications.groupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: try ownCryptoId, groupIdentifier: groupIdentifier)
                .postOnDispatchQueue()
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
                                           persistedGroupV2: self)
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
                    insertDiscussionIsEndToEndEncryptedSystemMessage: true,
                    shouldApplySharedConfigurationFromGlobalSettings: shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion)
            }
        } else {
            // If a discussion already existed, display a message indicating that the group members did change
            if !membersToRemove.isEmpty || !membersToInsert.isEmpty {
                try? discussion?.groupMembersWereUpdated()
            }
        }

        // Make sure the photo is updated in the list of discussions
        
        discussion?.setHasUpdates()

        // Update the associated displayed group
        
        displayedContactGroup?.updateUsingUnderlyingGroup()

    }
    
    
    func createOrUpdateTheAssociatedDisplayedContactGroup() throws {
        if let displayedContactGroup = self.displayedContactGroup {
            displayedContactGroup.updateUsingUnderlyingGroup()
        } else {
            self.displayedContactGroup = try DisplayedContactGroup(groupV2: self)
        }
    }
    
    
    static func createOrUpdate(obvGroupV2: ObvGroupV2, createdByMe: Bool, within context: NSManagedObjectContext) throws -> PersistedGroupV2 {
        if let persistedGroup = try PersistedGroupV2.getWithObvGroupV2(obvGroupV2, within: context) {
            persistedGroup.updateAttributes(obvGroupV2: obvGroupV2)
            try persistedGroup.updateRelationships(obvGroupV2: obvGroupV2, shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: createdByMe)
            persistedGroup.updateNamesOfOtherMembers()
            return persistedGroup
        } else {
            return try PersistedGroupV2(obvGroupV2: obvGroupV2, shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: createdByMe, within: context)
        }
    }

    
    func delete() throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw Self.makeError(message: "Could not find context")
        }
        if let discussion = discussion {
            try discussion.setStatus(to: .locked)
        }
        context.delete(self)
    }
    
    
    /// Called exclusively from the UI, when updating the scratch object during an edition of a `PersistedGroupV2`.
    func addGroupMembers(contactObjectIDs: Set<TypeSafeManagedObjectID<PersistedObvContactIdentity>>) throws {
        assert(Thread.isMainThread)
        try contactObjectIDs.forEach { contactObjectID in
            // If there already a PersistedGroupV2Member for this contact, do not add her twice
            guard !self.contactsAmongOtherPendingAndNonPendingMembers.map({ $0.typedObjectID }).contains(contactObjectID) else {
                return // Continue with next contactObjectID
            }
            _ = try PersistedGroupV2Member(contactObjectID: contactObjectID, persistedGroupV2: self)
        }
    }
    
    
    fileprivate func updateWhenPersistedGroupV2MemberIsUpdated() {
        displayedContactGroup?.updateUsingUnderlyingGroup()
        try? discussion?.resetTitle(to: self.displayName)
    }
    
    
    func setUpdateInProgress() {
        self.updateInProgress = true
    }
    
    
    func removeUpdateInProgress() {
        self.updateInProgress = false
    }
    
    
    func markPublishedDetailsAsSeen() {
        if detailsPublished == nil {
            publishedDetailsStatus = .noNewPublishedDetails
        } else {
            publishedDetailsStatus = .seenPublishedDetails
        }
        // Update the associated displayed group
        displayedContactGroup?.updateUsingUnderlyingGroup()
    }

    
    // MARK: Convenience DB getters

    struct Predicate {
        enum Key: String {
            case groupIdentifier = "groupIdentifier"
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
            case updateInProgress = "updateInProgress"
            case rawOtherMembers = "rawOtherMembers"
        }
        static func withOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownedIdentity.identity)
        }
        static func withPrimaryKey(ownCryptoId: ObvCryptoId, groupIdentifier: Data) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownCryptoId.getIdentity()),
                NSPredicate(Key.groupIdentifier, EqualToData: groupIdentifier),
            ])
        }
        static func withObjectID(_ objectID: TypeSafeManagedObjectID<PersistedGroupV2>) -> NSPredicate {
            NSPredicate.init(format: "SELF = %@", objectID.objectID)
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
    }

    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedGroupV2> {
        return NSFetchRequest<PersistedGroupV2>(entityName: self.entityName)
    }

    
    static func getWithPrimaryKey(ownCryptoId: ObvCryptoId, groupIdentifier: Data, within context: NSManagedObjectContext) throws -> PersistedGroupV2? {
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.withPrimaryKey(ownCryptoId: ownCryptoId, groupIdentifier: groupIdentifier)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    static func get(objectID: TypeSafeManagedObjectID<PersistedGroupV2>, within context: NSManagedObjectContext) throws -> PersistedGroupV2? {
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    static func getWithObvGroupV2(_ obvGroupV2: ObvGroupV2, within context: NSManagedObjectContext) throws -> PersistedGroupV2? {
        return try get(ownIdentity: obvGroupV2.ownIdentity, appGroupIdentifier: obvGroupV2.appGroupIdentifier, within: context)
    }

    
    static func get(ownIdentity: ObvCryptoId, appGroupIdentifier: Data, within context: NSManagedObjectContext) throws -> PersistedGroupV2? {
        return try getWithPrimaryKey(ownCryptoId: ownIdentity, groupIdentifier: appGroupIdentifier, within: context)
    }

    static func get(ownIdentity: PersistedObvOwnedIdentity, appGroupIdentifier: Data) throws -> PersistedGroupV2? {
        guard let context = ownIdentity.managedObjectContext else {
            throw Self.makeError(message: "Cannot find context")
        }
        return try getWithPrimaryKey(ownCryptoId: ownIdentity.cryptoId, groupIdentifier: appGroupIdentifier, within: context)
    }

    static func getAllPersistedGroupV2(ownedIdentity: PersistedObvOwnedIdentity) throws -> Set<PersistedGroupV2> {
        guard let context = ownedIdentity.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.withOwnedIdentity(ownedIdentity)
        return Set(try context.fetch(request))
    }
    
    
    static func getAllPersistedGroupV2(whereContactIdentitiesInclude contactIdentity: PersistedObvContactIdentity) throws -> Set<PersistedGroupV2> {
        guard let context = contactIdentity.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.otherMembersIncludeContact(contactIdentity)
        request.fetchBatchSize = 100
        return Set(try context.fetch(request))
    }

    
    // MARK: Displaying group information
    
    /// Used when displaying a group title in the interface
    var displayName: String {
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

    var trustedName: String? {
        detailsTrusted?.name
    }
    
    var displayedDescription: String? {
        detailsTrusted?.groupDescription
    }
    
    var trustedDescription: String? {
        detailsTrusted?.groupDescription
    }
    
    var hasPublishedDetails: Bool {
        detailsPublished != nil
    }
    
    var displayNamePublished: String? {
        detailsPublished?.name
    }

    var displayedDescriptionPublished: String? {
        detailsPublished?.groupDescription
    }
    
    var trustedPhotoURL: URL? {
        detailsTrusted?.photoURLFromEngine
    }

    var displayPhotoURL: URL? {
        customPhotoURL ?? detailsTrusted?.photoURLFromEngine
    }
    
    var displayPhotoURLPublished: URL? {
        detailsPublished?.photoURLFromEngine
    }

    var customPhotoURL: URL? {
        guard let customPhotoFilename = customPhotoFilename else { return nil }
        let url = ObvMessengerConstants.containerURL.forCustomGroupProfilePictures.appendingPathComponent(customPhotoFilename)
        assert(FileManager.default.fileExists(atPath: url.path))
        return url
    }
    
    var enginePhotoURL: URL? {
        detailsTrusted?.photoURLFromEngine
    }
    
    // MARK: Helpers for the UI
    
    /// We can always leave a group if we are not administrator. If we are, we can only leave if there is another administrator that is not pending.
    var ownedIdentityCanLeaveGroup: Bool {
        let nonPendingOtherMembers = otherMembers.filter({ !$0.isPending })
        return !ownPermissionAdmin || !nonPendingOtherMembers.filter({ $0.isAnAdmin }).isEmpty
    }
    
    // MARK: For SwiftUI previews

    private convenience init(mocObjectWithCustomName customName: String?, groupIdentifier: Data, keycloakManaged: Bool, ownPermissionAdmin: Bool, rawOwnedIdentityIdentity: Data, updateInProgress: Bool, otherMembers: Set<PersistedGroupV2Member>) {
        try? ObvStack.initSharedInstance(transactionAuthor: ObvMessengerConstants.AppType.mainApp.transactionAuthor, runningLog: RunningLogError(), enableMigrations: false)
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: ObvStack.shared.viewContext)!
        self.init(entity: entityDescription, insertInto: ObvStack.shared.viewContext)
        self.customName = customName
        self.customPhotoFilename = nil
        self.groupIdentifier = groupIdentifier
        self.keycloakManaged = keycloakManaged
        self.ownPermissionAdmin = ownPermissionAdmin
        self.ownPermissionChangeSettings = false
        self.ownPermissionEditOrRemoteDeleteOwnMessages = false
        self.ownPermissionRemoteDeleteAnything = false
        self.ownPermissionSendMessage = false
        self.personalNote = nil
        self.rawOwnedIdentityIdentity = rawOwnedIdentityIdentity
        self.updateInProgress = updateInProgress

        self.detailsPublished = nil
        self.detailsTrusted = nil
        self.displayedContactGroup = nil
        self.rawOtherMembers = otherMembers
        self.rawOwnedIdentity = nil
        
    }
    
    static func mocObject(customName: String?, groupIdentifier: Data, keycloakManaged: Bool, ownPermissionAdmin: Bool, rawOwnedIdentityIdentity: Data, updateInProgress: Bool, otherMembers: Set<PersistedGroupV2Member>) -> PersistedGroupV2 {
        return self.init(mocObjectWithCustomName: customName,
                         groupIdentifier: groupIdentifier,
                         keycloakManaged: keycloakManaged,
                         ownPermissionAdmin: ownPermissionAdmin,
                         rawOwnedIdentityIdentity: rawOwnedIdentityIdentity,
                         updateInProgress: updateInProgress,
                         otherMembers: otherMembers)
    }

    
    // MARK: Computing changesets
    
    @MainActor
    func computeChangeset(with referenceGroup: PersistedGroupV2) throws -> ObvGroupV2.Changeset {
        assert(Thread.isMainThread)
        guard let context = self.managedObjectContext, let referenceContext = referenceGroup.managedObjectContext, context.concurrencyType == .mainQueueConcurrencyType, referenceContext.concurrencyType == .mainQueueConcurrencyType else {
            assertionFailure()
            throw Self.makeError(message: "Unexpected context")
        }
        guard !context.updatedObjects.contains(referenceGroup) && !referenceGroup.hasChanges else {
            assertionFailure()
            throw Self.makeError(message: "The reference group has changes")
        }
        var changes = Set<ObvGroupV2.Change>()
        // Augment the changeset with changes made to the group details and photo
        if let change = try computeChangeForGroupDetails(with: referenceGroup) {
            changes.insert(change)
        }
        if let change = try computeChangeForGroupPhoto(with: referenceGroup) {
            changes.insert(change)
        }
        // Augment the changeset with changes made to the members
        for member in self.otherMembers {
            if let change = try member.computeChange() {
                changes.insert(change)
            }
        }
        if let changesForDeletedMembers = try computeChangesForDeletedMembers(with: referenceGroup) {
            changes.formUnion(changesForDeletedMembers)
        }
        return try ObvGroupV2.Changeset(changes: changes)
    }
    
    
    @MainActor private func computeChangeForGroupDetails(with referenceGroup: PersistedGroupV2) throws -> ObvGroupV2.Change? {
        guard self.hasChanges else { return nil }
        guard let detailsTrusted = self.detailsTrusted, let referenceDetailsTrusted = referenceGroup.detailsTrusted else {
            throw Self.makeError(message: "Could not get trusted details")
        }
        // Check whether the core details did change
        let coreDetails = detailsTrusted.coreDetails
        let referenceCoreDetails = referenceDetailsTrusted.coreDetails
        let coreDetailsWereChanged = coreDetails != referenceCoreDetails
        // Return a change if necessary
        guard coreDetailsWereChanged else { return nil }
        let serializedGroupCoreDetails = try coreDetails.jsonEncode()
        return ObvGroupV2.Change.groupDetails(serializedGroupCoreDetails: serializedGroupCoreDetails)
    }

    
    @MainActor private func computeChangeForGroupPhoto(with referenceGroup: PersistedGroupV2) throws -> ObvGroupV2.Change? {
        guard self.hasChanges else { return nil }
        guard let detailsTrusted = self.detailsTrusted, let referenceDetailsTrusted = referenceGroup.detailsTrusted else {
            throw Self.makeError(message: "Could not get trusted details")
        }
        // Check whether the photo did change.
        let photoURLFromEngine = detailsTrusted.photoURLFromEngine
        let referencePhotoURLFromEngine = referenceDetailsTrusted.photoURLFromEngine
        let photoWasChanged = photoURLFromEngine != referencePhotoURLFromEngine
        // Return a change if necessary
        guard photoWasChanged else { return nil }
        return ObvGroupV2.Change.groupPhoto(photoURL: photoURLFromEngine)
    }

    
    @MainActor private func computeChangesForDeletedMembers(with referenceGroup: PersistedGroupV2) throws -> Set<ObvGroupV2.Change>? {
        assert(Thread.isMainThread)
        guard let context = self.managedObjectContext, context.concurrencyType == .mainQueueConcurrencyType else {
            throw Self.makeError(message: "Unexpected context")
        }
        // To compute the deleted members, we take all the `PersistedGroupV2Member` objects that are deleted from the context.
        // We filter out those that are not part of the group. This is necessary in the case the user deletes a first member (which creates a first entry in the context's deletedObjects), and then deletes another member (creating a *second* entry in the context's deletedObjects). During the second deletion, we thus want to filter out the first deleted `PersistedGroupV2Member`.
        let deletedMembers = context.deletedObjects.compactMap({ $0 as? PersistedGroupV2Member }).filter({ referenceGroup.otherMembers.compactMap({ $0.cryptoId }).contains($0.cryptoId) })
        guard !deletedMembers.isEmpty else { return nil }
        let contactCryptoIds = deletedMembers.compactMap { $0.cryptoIdWhenDeleted }
        assert(!contactCryptoIds.isEmpty)
        return Set(contactCryptoIds.map({ ObvGroupV2.Change.memberRemoved(contactCryptoId: $0) }))
    }
    
    
    // MARK: - Thread safe struct

        
    struct Structure {
        
        let typedObjectID: TypeSafeManagedObjectID<PersistedGroupV2>
        let groupIdentifier: Data
        let displayName: String
        let displayPhotoURL: URL?
        let contactIdentities: Set<PersistedObvContactIdentity.Structure>
        
        private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedGroupV2.Structure")
        
    }
        
        func toStruct() throws -> Structure {
            let contactIdentities = Set(try self.contactsAmongOtherPendingAndNonPendingMembers.map({ try $0.toStruct() }))
            return Structure(typedObjectID: self.typedObjectID,
                             groupIdentifier: self.groupIdentifier,
                             displayName: self.displayName,
                             displayPhotoURL: self.displayPhotoURL,
                             contactIdentities: contactIdentities)
        }
        

    
    
    // MARK: On save
    
    private var changedKeys = Set<String>()

    override func willSave() {
        super.willSave()
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }
    
    override func didSave() {
        super.didSave()
        defer { changedKeys.removeAll() }
        
        if isDeleted {
            ObvMessengerCoreDataNotification.persistedGroupV2WasDeleted(objectID: self.typedObjectID)
                .postOnDispatchQueue()
        } else if changedKeys.contains(Predicate.Key.updateInProgress.rawValue) && self.updateInProgress == false {
            ObvMessengerCoreDataNotification.persistedGroupV2UpdateIsFinished(objectID: self.typedObjectID)
                .postOnDispatchQueue()
        }
        
    }
    
}


// MARK: - PersistedGroupV2Member

@objc(PersistedGroupV2Member)
final class PersistedGroupV2Member: NSManagedObject, Identifiable, ObvErrorMaker {
    
    private static let entityName = "PersistedGroupV2Member"
    static let errorDomain = "PersistedGroupV2Member"

    // Attributes
    
    @NSManaged private var company: String?
    @NSManaged private var firstName: String?
    @NSManaged private var groupIdentifier: Data // Part of primary key
    @NSManaged private(set) var identity: Data // Part of primary key
    @NSManaged private(set) var isPending: Bool
    @NSManaged private var lastName: String?
    @NSManaged fileprivate var normalizedSearchKey: String
    @NSManaged fileprivate var normalizedSortKey: String
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
    
    var cryptoId: ObvCryptoId? {
        return try? ObvCryptoId(identity: identity)
    }
    
    var contact: PersistedObvContactIdentity? {
        rawContact
    }
    
    var displayedFirstName: String? {
        if let rawContact = self.rawContact {
            return rawContact.displayedFirstName
        } else {
            return firstName
        }
    }
    
    var displayedCustomDisplayNameOrLastName: String? {
        if let rawContact = self.rawContact {
            return rawContact.displayedCustomDisplayNameOrLastName
        } else {
            return lastName
        }
    }

    var displayedCustomDisplayNameOrFirstNameOrLastName: String? {
        if let rawContact = self.rawContact {
            return rawContact.displayedCustomDisplayNameOrFirstNameOrLastName
        } else {
            return firstName ?? lastName
        }
    }

    var displayedCompany: String? {
        if let rawContact = self.rawContact {
            return rawContact.displayedCompany
        } else {
            return company
        }
    }

    var displayedPosition: String? {
        if let rawContact = self.rawContact {
            return rawContact.displayedPosition
        } else {
            return position
        }
    }
    
    var displayedCustomDisplayName: String? {
        rawContact?.customDisplayName
    }
    
    var displayedProfilePicture: UIImage? {
        rawContact?.displayedProfilePicture
    }
    
    var displayedContactGroup: DisplayedContactGroup? {
        rawGroup?.displayedContactGroup
    }
    
    var permissions: Set<ObvGroupV2.Permission> {
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
    
    var isAnAdmin: Bool {
        return permissionAdmin
    }
    
    var isAllowedToChangeSettings: Bool {
        return permissionChangeSettings
    }
    
    var isAllowedToEditOrRemoteDeleteOwnMessages: Bool {
        return permissionRemoteDeleteAnything || permissionEditOrRemoteDeleteOwnMessages
    }
    
    var isAllowedToRemoteDeleteAnything: Bool {
        return permissionRemoteDeleteAnything
    }

    var isAllowedToSendMessage: Bool {
        return permissionSendMessage
    }

    var permissionChangeSettingsIsUpdated: Bool {
        Set<String>(self.changedValues().keys).contains(Predicate.Key.permissionChangeSettings.rawValue)
    }
    
    fileprivate var cryptoIdWhenDeleted: ObvCryptoId?
    
    // Initializer
    
    fileprivate convenience init(identityAndPermissionsAndDetails: ObvGroupV2.IdentityAndPermissionsAndDetails, groupIdentifier: Data, ownCryptoId: ObvCryptoId, persistedGroupV2: PersistedGroupV2) throws {
        
        guard let context = persistedGroupV2.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        
        let contact = try PersistedObvContactIdentity.get(contactCryptoId: identityAndPermissionsAndDetails.identity,
                                                                ownedIdentityCryptoId: ownCryptoId,
                                                                whereOneToOneStatusIs: .any,
                                                                within: context)
        
        guard contact != nil || identityAndPermissionsAndDetails.isPending else {
            assertionFailure()
            throw Self.makeError(message: "Could not find PersistedObvContactIdentity although the member is not pending")
        }

        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.rawContact = contact
        self.rawGroup = persistedGroupV2

        self.groupIdentifier = groupIdentifier
        try self.updateWith(identityAndPermissionsAndDetails: identityAndPermissionsAndDetails)
        self.rawOwnedIdentityIdentity = ownCryptoId.getIdentity()
        
    }
    
    /// Used exclusively from the UI, when updating the scratch object
    fileprivate convenience init(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, persistedGroupV2: PersistedGroupV2) throws {
        assert(Thread.isMainThread)
        guard let context = persistedGroupV2.managedObjectContext, context.concurrencyType == .mainQueueConcurrencyType else {
            assertionFailure()
            throw Self.makeError(message: "Unexpected context")
        }
        guard let contact = try PersistedObvContactIdentity.get(objectID: contactObjectID, within: context) else {
            throw Self.makeError(message: "Could not find PersistedObvContactIdentity")
        }
        guard try persistedGroupV2.ownCryptoId == contact.ownedIdentity?.cryptoId else {
            assertionFailure()
            throw Self.makeError(message: "Owned identities do not match")
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.groupIdentifier = groupIdentifier
        let identityAndPermissionsAndDetails = ObvGroupV2.IdentityAndPermissionsAndDetails(
            identity: contact.cryptoId,
            permissions: ObvMessengerConstants.defaultObvGroupV2PermissionsForNewGroupMembers,
            serializedIdentityCoreDetails: try contact.identityCoreDetails.jsonEncode(),
            isPending: true)
        try self.updateWith(identityAndPermissionsAndDetails: identityAndPermissionsAndDetails)
        guard let ownedIdentity = contact.ownedIdentity?.cryptoId else { throw Self.makeError(message: "Could not determine owned identity") }
        self.rawOwnedIdentityIdentity = ownedIdentity.getIdentity()

        self.rawContact = contact
        self.rawGroup = persistedGroupV2
    }
    
    
    fileprivate func updateWith(identityAndPermissionsAndDetails: ObvGroupV2.IdentityAndPermissionsAndDetails) throws {
        self.identity = identityAndPermissionsAndDetails.identity.getIdentity()
        self.isPending = identityAndPermissionsAndDetails.isPending
        self.permissionAdmin = identityAndPermissionsAndDetails.permissions.contains(.groupAdmin)
        self.permissionChangeSettings = identityAndPermissionsAndDetails.permissions.contains(.changeSettings)
        self.permissionEditOrRemoteDeleteOwnMessages = identityAndPermissionsAndDetails.permissions.contains(.editOrRemoteDeleteOwnMessages)
        self.permissionRemoteDeleteAnything = identityAndPermissionsAndDetails.permissions.contains(.remoteDeleteAnything)
        self.permissionSendMessage = identityAndPermissionsAndDetails.permissions.contains(.sendMessage)
        let coreDetails = try ObvIdentityCoreDetails.jsonDecode(identityAndPermissionsAndDetails.serializedIdentityCoreDetails)
        self.firstName = coreDetails.firstName
        self.lastName = coreDetails.lastName
        self.position = coreDetails.position
        self.company = coreDetails.company
        self.updateNormalizedSortAndSearchKeys(with: ObvMessengerSettings.Interface.contactsSortOrder)
    }
    
    
    func updateWith(persistedContact: PersistedObvContactIdentity) throws {
        guard self.rawContact != persistedContact else { return }
        guard identity == persistedContact.identity else {
            throw Self.makeError(message: "Trying to update member with a contact that does not have the appropriate identity")
        }
        guard rawOwnedIdentityIdentity == persistedContact.ownedIdentity?.identity else {
            throw Self.makeError(message: "Trying to update member with a contact that does not have the appropriate associted owned identity")
        }
        self.rawContact = persistedContact
        self.updateNormalizedSortAndSearchKeys(with: ObvMessengerSettings.Interface.contactsSortOrder)
    }
    
    
    /// When a contact changes, this method is called to make sure the corresponding `PersistedGroupV2Member` sortKey stays in sync.
    /// It is also used when creating a `PersistedGroupV2Member` instance, so as to use the details
    func updateNormalizedSortAndSearchKeys(with sortOrder: ContactsSortOrder) {
        
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
                company: self.company)
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

    
    /// Setting the admin permission actually resets all the permissions to the default values of new admins.
    /// Removing the admin permission resets all the permissions to the default values of new members.
    func setPermissionAdmin(to newValue: Bool) {
        let newPermissions: Set<ObvGroupV2.Permission>
        if newValue {
            newPermissions = ObvMessengerConstants.defaultObvGroupV2PermissionsForAdmin
        } else {
            newPermissions = ObvMessengerConstants.defaultObvGroupV2PermissionsForNewGroupMembers
        }
        for permission in ObvGroupV2.Permission.allCases {
            switch permission {
            case .groupAdmin:
                let newPermissionValue = newPermissions.contains(permission)
                if self.permissionAdmin != newPermissionValue {
                    self.permissionAdmin = newPermissionValue
                }
            case .remoteDeleteAnything:
                let newPermissionValue = newPermissions.contains(permission)
                if self.permissionRemoteDeleteAnything != newPermissionValue {
                    self.permissionRemoteDeleteAnything = newPermissionValue
                }
            case .editOrRemoteDeleteOwnMessages:
                let newPermissionValue = newPermissions.contains(permission)
                if self.permissionEditOrRemoteDeleteOwnMessages != newPermissionValue {
                    self.permissionEditOrRemoteDeleteOwnMessages = newPermissionValue
                }
            case .changeSettings:
                let newPermissionValue = newPermissions.contains(permission)
                if self.permissionChangeSettings != newPermissionValue {
                    self.permissionChangeSettings = newPermissionValue
                }
            case .sendMessage:
                let newPermissionValue = newPermissions.contains(permission)
                if self.permissionSendMessage != newPermissionValue {
                    self.permissionSendMessage = newPermissionValue
                }
            }
        }
    }

    
    /// Also called from the UI to remove a member for the PersistedGroupV2 scratch object.
    func delete() throws {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        cryptoIdWhenDeleted = self.cryptoId
        context.delete(self)
    }

    
    // MARK: Convenience DB getters

    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedGroupV2Member> {
        return NSFetchRequest<PersistedGroupV2Member>(entityName: self.entityName)
    }

    struct Predicate {
        enum Key: String {
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
    }


    static func getAllPersistedGroupV2MemberOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [PersistedGroupV2Member] {
        let request: NSFetchRequest<PersistedGroupV2Member> = PersistedGroupV2Member.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.normalizedSortKey.rawValue, ascending: true)]
        request.predicate = Predicate.withOwnCryptoId(ownedCryptoId)
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }

    
    static func deleteOrphanedPersistedGroupV2Members(within context: NSManagedObjectContext) throws {
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
    
    
    // MARK: For SwiftUI previews

    private convenience init(mocObjectWithCompany: String?, firstName: String?, groupIdentifier: Data, identity: Data, isPending: Bool, lastName: String?, permissionAdmin: Bool, position: String?, rawOwnedIdentityIdentity: Data) {
        try? ObvStack.initSharedInstance(transactionAuthor: ObvMessengerConstants.AppType.mainApp.transactionAuthor, runningLog: RunningLogError(), enableMigrations: false)
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: ObvStack.shared.viewContext)!
        self.init(entity: entityDescription, insertInto: ObvStack.shared.viewContext)
        self.company = company
        self.firstName = firstName
        self.groupIdentifier = groupIdentifier
        self.identity = identity
        self.isPending = isPending
        self.lastName = lastName
        self.permissionAdmin = permissionAdmin
        self.permissionChangeSettings = false
        self.permissionEditOrRemoteDeleteOwnMessages = false
        self.permissionRemoteDeleteAnything = false
        self.permissionSendMessage = false
        self.position = position
        self.rawOwnedIdentityIdentity = rawOwnedIdentityIdentity
    }
    
    
    static func mocObject(company: String?, firstName: String?, groupIdentifier: Data, identity: Data, isPending: Bool, lastName: String?, permissionAdmin: Bool, position: String?, rawOwnedIdentityIdentity: Data) -> PersistedGroupV2Member {
        return self.init(mocObjectWithCompany: company,
                         firstName: firstName,
                         groupIdentifier: groupIdentifier,
                         identity: identity,
                         isPending: isPending,
                         lastName: lastName,
                         permissionAdmin: permissionAdmin,
                         position: position,
                         rawOwnedIdentityIdentity: rawOwnedIdentityIdentity)
    }

    // MARK: Computing changesets

    @MainActor fileprivate func computeChange() throws -> ObvGroupV2.Change? {
        guard self.hasChanges else { return nil }
        guard let cryptoId = cryptoId else { throw Self.makeError(message: "Could not get added member crypto Id") }
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
    
    override func willSave() {
        super.willSave()
        
        if !isInserted && !isDeleted {
            changedKeys = Set<String>(self.changedValues().keys)
        }
        
    }
    
    override func didSave() {
        super.didSave()
        
        defer { changedKeys.removeAll() }
        
        if changedKeys.contains(Predicate.Key.isPending.rawValue), !self.isPending, let contactObjectID = contact?.typedObjectID {
            ObvMessengerCoreDataNotification.aPersistedGroupV2MemberChangedFromPendingToNonPending(contactObjectID: contactObjectID)
                .postOnDispatchQueue()
        }
        
    }

}


// MARK: - PersistedGroupV2Details

@objc(PersistedGroupV2Details)
final class PersistedGroupV2Details: NSManagedObject, ObvErrorMaker {
    
    private static let entityName = "PersistedGroupV2Details"
    static let errorDomain = "PersistedGroupV2Details"

    // Attributes
    
    @NSManaged private(set) var groupDescription: String?
    @NSManaged private(set) var name: String?
    @NSManaged private(set) var photoURLFromEngine: URL?

    // Relationships

    @NSManaged private var asPublishedDetailsOfGroup: PersistedGroupV2? // Expected to be non nil if asTrustedDetailsOfGroup is nil
    @NSManaged private var asTrustedDetailsOfGroup: PersistedGroupV2? // Expected to be non nil if asPublishedDetailsOfGroup is nil
    
    // Computed variables
    
    var coreDetails: GroupV2CoreDetails {
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
            throw Self.makeError(message: "Could not find context")
        }

        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        _ = try self.updateWithDetailsAndPhoto(detailsAndPhoto)

    }
    
}
