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
import CoreData
import OlvidUtils
import ObvTypes
import CryptoKit
import os.log
import Platform_Base
import ObvEngine
import UI_ObvCircledInitials
import ObvSettings


@objc(PersistedGroupV2)
public final class PersistedGroupV2: NSManagedObject, ObvErrorMaker {
    
    private static let entityName = "PersistedGroupV2"
    public static let errorDomain = "PersistedGroupV2"

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

    // Relationships
    
    @NSManaged private var detailsPublished: PersistedGroupV2Details? // Non-nil iff there are untrusted new details
    @NSManaged public private(set) var detailsTrusted: PersistedGroupV2Details? // Expected to be non nil
    @NSManaged private var rawDiscussion: PersistedGroupV2Discussion? // Expected to be non nil
    @NSManaged public private(set) var displayedContactGroup: DisplayedContactGroup? // Expected to be non nil
    @NSManaged private var rawOtherMembers: Set<PersistedGroupV2Member>
    @NSManaged private var rawOwnedIdentity: PersistedObvOwnedIdentity? // Expected to be non nil

    // Accessors
    
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
        self.keycloakManaged = obvGroupV2.keycloakManaged
        self.namesOfOtherMembers = nil // Updated later
        if obvGroupV2.keycloakManaged {
            self.ownPermissionAdmin = false
        } else {
            let newOwnPermissionAdmin = obvGroupV2.ownPermissions.contains(.groupAdmin)
            if newOwnPermissionAdmin != self.ownPermissionAdmin {
                if newOwnPermissionAdmin {
                    try? discussion?.ownedIdentityBecameAnAdmin()
                } else {
                    try? discussion?.ownedIdentityIsNoLongerAnAdmin()
                }
                self.ownPermissionAdmin = newOwnPermissionAdmin
            }
        }
        self.ownPermissionChangeSettings = obvGroupV2.ownPermissions.contains(.changeSettings)
        self.ownPermissionEditOrRemoteDeleteOwnMessages = obvGroupV2.ownPermissions.contains(.editOrRemoteDeleteOwnMessages)
        self.ownPermissionRemoteDeleteAnything = obvGroupV2.ownPermissions.contains(.remoteDeleteAnything)
        self.ownPermissionSendMessage = obvGroupV2.ownPermissions.contains(.sendMessage)
        self.rawOwnedIdentityIdentity = obvGroupV2.ownIdentity.getIdentity()
        self.updateInProgress = obvGroupV2.updateInProgress
        displayedContactGroup?.updateUsingUnderlyingGroup()
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
        self.namesOfOtherMembers = names.formatted(.list(type: .and, width: .short))
        displayedContactGroup?.updateUsingUnderlyingGroup()
        try? discussion?.resetTitle(to: self.displayName)
    }
    
    
    /// This method saves the photo to a proper location.
    func updateCustomPhotoWithPhoto(_ newPhoto: UIImage?, within obvContext: ObvContext) throws {
        
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
        
        // If received new photo is nil, there is nothing left to do
        
        guard let newPhoto else { return }

        // Create a file at a proper location

        let newCustomFilename = UUID().uuidString
        self.customPhotoFilename = newCustomFilename
        let customPhotoURL = ObvUICoreDataConstants.ContainerURL.forCustomGroupProfilePictures.appendingPathComponent(newCustomFilename)
        guard let jpegData = newPhoto.jpegData(compressionQuality: 0.75) else {
            assertionFailure()
            throw Self.makeError(message: "Could not extract jpeg data for custom group photo")
        }
        do {
            try jpegData.write(to: customPhotoURL)
        } catch {
            assertionFailure()
            throw Self.makeError(message: "Could not write custom photo to file")
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
        displayedContactGroup?.updateUsingUnderlyingGroup()
        try discussion?.resetTitle(to: self.displayName)
        return true
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
                    shouldApplySharedConfigurationFromGlobalSettings: shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion)
            }
        } else {
            // If a discussion already existed, display a message indicating that the group members did change
            if !membersToRemove.isEmpty || !membersToInsert.isEmpty {
                try? discussion?.groupMembersWereUpdated()
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
        
        discussion?.setHasUpdates()

        // Update the associated displayed group
        
        displayedContactGroup?.updateUsingUnderlyingGroup()

    }
    
    
    public func trustedDetailsShouldBeReplacedByPublishedDetails() throws {
        ObvMessengerCoreDataNotification.groupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: try ownCryptoId, groupIdentifier: groupIdentifier)
            .postOnDispatchQueue()
    }
    
    
    public func createOrUpdateTheAssociatedDisplayedContactGroup() throws {
        if let displayedContactGroup = self.displayedContactGroup {
            displayedContactGroup.updateUsingUnderlyingGroup()
        } else {
            self.displayedContactGroup = try DisplayedContactGroup(groupV2: self)
        }
    }
    
    
    static func createOrUpdate(obvGroupV2: ObvGroupV2, createdByMe: Bool, within context: NSManagedObjectContext) throws -> PersistedGroupV2 {
        if let persistedGroup = try PersistedGroupV2.getWithObvGroupV2(obvGroupV2, within: context) {
            persistedGroup.updateAttributes(obvGroupV2: obvGroupV2)
            try persistedGroup.updateRelationships(obvGroupV2: obvGroupV2,
                                                   shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: createdByMe)
            persistedGroup.updateNamesOfOtherMembers()
            return persistedGroup
        } else {
            return try PersistedGroupV2(obvGroupV2: obvGroupV2,
                                        shouldApplySharedConfigurationFromGlobalSettingsWhenCreatingTheDiscussion: createdByMe,
                                        within: context)
        }
    }

    
    public func delete() throws {
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
    public func addGroupMembers(contactObjectIDs: Set<TypeSafeManagedObjectID<PersistedObvContactIdentity>>) throws {
        assert(Thread.isMainThread)
        try contactObjectIDs.forEach { contactObjectID in
            // If there already a PersistedGroupV2Member for this contact, do not add her twice
            guard !self.contactsAmongOtherPendingAndNonPendingMembers.map({ $0.typedObjectID }).contains(contactObjectID) else {
                return // Continue with next contactObjectID
            }
            _ = try PersistedGroupV2Member(contactObjectID: contactObjectID,
                                           persistedGroupV2: self)
        }
    }
    
    
    fileprivate func updateWhenPersistedGroupV2MemberIsUpdated() {
        displayedContactGroup?.updateUsingUnderlyingGroup()
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
        displayedContactGroup?.updateUsingUnderlyingGroup()
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
            throw Self.makeError(message: "Cannot find context")
        }
        return try getWithPrimaryKey(ownCryptoId: ownIdentity.cryptoId, groupIdentifier: appGroupIdentifier, within: context)
    }

    public static func getAllPersistedGroupV2(ownedIdentity: PersistedObvOwnedIdentity) throws -> Set<PersistedGroupV2> {
        guard let context = ownedIdentity.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.withOwnedIdentity(ownedIdentity)
        return Set(try context.fetch(request))
    }
    
    
    public static func getAllPersistedGroupV2(whereContactIdentitiesInclude contactIdentity: PersistedObvContactIdentity) throws -> Set<PersistedGroupV2> {
        guard let context = contactIdentity.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedGroupV2> = PersistedGroupV2.fetchRequest()
        request.predicate = Predicate.otherMembersIncludeContact(contactIdentity)
        request.fetchBatchSize = 100
        return Set(try context.fetch(request))
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
    

    // MARK: Computing changesets
    
    @MainActor
    public func computeChangeset(with referenceGroup: PersistedGroupV2) throws -> ObvGroupV2.Changeset {
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
        defer { changedKeys.removeAll() }
        
        if isDeleted {
            ObvMessengerCoreDataNotification.persistedGroupV2WasDeleted(objectID: self.typedObjectID)
                .postOnDispatchQueue()
        } else if changedKeys.contains(Predicate.Key.updateInProgress.rawValue) && self.updateInProgress == false {
            if let ownedCryptoId = try? self.ownCryptoId {
                ObvMessengerCoreDataNotification.persistedGroupV2UpdateIsFinished(objectID: self.typedObjectID, ownedCryptoId: ownedCryptoId, groupIdentifier: self.groupIdentifier)
                    .postOnDispatchQueue()
            }
        }
        
        if isInserted {
            if let ownedCryptoId = try? self.ownCryptoId {
                ObvMessengerCoreDataNotification.aPersistedGroupV2WasInsertedInDatabase(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier)
                    .postOnDispatchQueue()
            }
        }
        
    }
    
    
    // MARK: - Receiving discussion shared configurations

    /// Called when receiving a shared discussion configuration from a contact  indicating this particular group as the target. This method makes sure the contact is allowed to change the configuration.
    func mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration: PersistedDiscussion.SharedConfiguration, receivedFrom contact: PersistedObvContactIdentity) throws -> (sharedSettingHadToBeUpdated: Bool, weShouldSendBackOurSharedSettings: Bool) {
                
        let contactIdentity = contact.identity
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw Self.makeError(message: "Owned identity is not part of group")
        }

        guard let initiatorAsMember = self.otherMembers.first(where: { $0.identity == contactIdentity }) else {
            throw Self.makeError(message: "The initiator is not part of the group")
        }
        
        guard initiatorAsMember.isAllowedToChangeSettings else {
            throw Self.makeError(message: "The initiator is not allowed to change settings")
        }

        guard let discussion = self.discussion else {
            throw Self.makeError(message: "Could not find discussion")
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
            throw Self.makeError(message: "Owned identity is not part of group")
        }
        
        guard self.ownedIdentityIsAllowedToChangeSettings else {
            throw Self.makeError(message: "The owned identity is not allowed to change settings")
        }
        
        guard let discussion = self.discussion else {
            throw Self.makeError(message: "Could not find discussion")
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
            throw Self.makeError(message: "Owned identity is not part of group")
        }
        
        guard self.ownedIdentityIsAllowedToChangeSettings else {
            throw Self.makeError(message: "The owned identity is not allowed to change settings")
        }
        
        guard let discussion = self.discussion else {
            throw Self.makeError(message: "Could not find discussion")
        }

        let sharedSettingHadToBeUpdated = try discussion.replaceReceivedDiscussionSharedConfiguration(with: expiration)
        
        return sharedSettingHadToBeUpdated

    }

    
    // MARK: - Processing wipe requests from contacts and other owned devices

    func processWipeMessageRequest(of messagesToDelete: [MessageReferenceJSON], receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let requester = self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) else {
            throw ObvError.wipeRequestedByNonGroupMember
        }

        guard requester.isAllowedToRemoteDeleteAnything || requester.isAllowedToEditOrRemoteDeleteOwnMessages else {
            assertionFailure()
            throw ObvError.wipeRequestedByMemberNotAllowedToRemoteDelete
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        let infos = try discussion.processWipeMessageRequest(of: messagesToDelete, from: contact.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return infos
        
    }
    
    
    func processWipeMessageRequest(of messagesToDelete: [MessageReferenceJSON], receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }
        
        // We do not check whether the owned identity is allowed to wipe
        
        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        let infos = try discussion.processWipeMessageRequest(of: messagesToDelete, from: ownedIdentity.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return infos

    }
    
    
    // MARK: - Processing delete requests from the owned identity (made on this device)

    func processMessageDeletionRequestRequestedFromCurrentDevice(of ownedIdentity: PersistedObvOwnedIdentity, messageToDelete: PersistedMessage, deletionType: DeletionType) throws -> InfoAboutWipedOrDeletedPersistedMessage {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }
        
        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        switch deletionType {
        case .local:
            break
        case .global:
            guard self.ownedIdentityIsAllowedToRemoteDeleteAnything || (self.ownedIdentityIsAllowedToEditOrRemoteDeleteOwnMessages && messageToDelete is PersistedMessageSent) else {
                assertionFailure()
                throw ObvError.ownedIdentityIsNotAllowedToDeleteThisMessage
            }
        }

        let info = try discussion.processMessageDeletionRequestRequestedFromCurrentDevice(
            of: ownedIdentity,
            messageToDelete: messageToDelete,
            deletionType: deletionType)

        return info
        
    }
    
    
    // MARK: - Receiving messages and attachments from a contact or another owned device

    func createOrOverridePersistedMessageReceived(from contact: PersistedObvContactIdentity, obvMessage: ObvMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, overridePreviousPersistedMessage: Bool) throws -> (discussionPermanentID: DiscussionPermanentID, attachmentFullyReceivedOrCancelledByServer: [ObvAttachment]) {
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let requester = self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) else {
            throw ObvError.wipeRequestedByNonGroupMember
        }

        guard requester.isAllowedToSendMessage else {
            throw ObvError.messageReceivedByMemberNotAllowedToSendMessage
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        return try discussion.createOrOverridePersistedMessageReceived(
            from: contact,
            obvMessage: obvMessage,
            messageJSON: messageJSON,
            returnReceiptJSON: returnReceiptJSON,
            overridePreviousPersistedMessage: overridePreviousPersistedMessage)
        
    }
    
    
    func createPersistedMessageSentFromOtherOwnedDevice(from ownedIdentity: PersistedObvOwnedIdentity, obvOwnedMessage: ObvOwnedMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?) throws -> [ObvOwnedAttachment] {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }
        
        guard ownedIdentityIsAllowedToSendMessage else {
            throw ObvError.ownedIdentityIsNotAllowedToSendMessages
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        let attachmentFullyReceivedOrCancelledByServer = try discussion.createPersistedMessageSentFromOtherOwnedDevice(
            from: ownedIdentity,
            obvOwnedMessage: obvOwnedMessage,
            messageJSON: messageJSON,
            returnReceiptJSON: returnReceiptJSON)
        
        return attachmentFullyReceivedOrCancelledByServer
        
    }
    
    
    // MARK: - Processing edit requests

    func processUpdateMessageRequest(_ updateMessageJSON: UpdateMessageJSON, receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {

        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let requester = self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) else {
            throw ObvError.wipeRequestedByNonGroupMember
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }
        
        // Check that the contact is allowed to edit her messages. Note that the check whether the message was written by her is done later.
        
        guard requester.isAllowedToEditOrRemoteDeleteOwnMessages else {
            throw ObvError.updateRequestReceivedByMemberNotAllowedToToEditOrRemoteDeleteOwnMessages
        }
        
        // Request the update
        
        let updatedMessage = try discussion.processUpdateMessageRequest(updateMessageJSON, receivedFromContactCryptoId: contact.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        return updatedMessage
        
    }

    
    func processUpdateMessageRequest(_ updateMessageJSON: UpdateMessageJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        // Check that the owned identity is allowed to edit her messages. Note that the check whether the message was written by her is done later.

        guard ownedIdentityIsAllowedToEditOrRemoteDeleteOwnMessages else {
            throw ObvError.ownedIdentityIsNotAllowedToEditOrRemoteDeleteOwnMessages
        }
        
        // Request the update
        
        let updatedMessage = try discussion.processUpdateMessageRequest(updateMessageJSON, receivedFromOwnedCryptoId: ownedIdentity.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        return updatedMessage

    }
    
    
    func processLocalUpdateMessageRequest(from ownedIdentity: PersistedObvOwnedIdentity, for messageSent: PersistedMessageSent, newTextBody: String?) throws {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        // Check that the owned identity is allowed to edit her messages.

        guard ownedIdentityIsAllowedToEditOrRemoteDeleteOwnMessages else {
            throw ObvError.ownedIdentityIsNotAllowedToEditOrRemoteDeleteOwnMessages
        }

        // Request the update

        try discussion.processLocalUpdateMessageRequest(from: ownedIdentity, for: messageSent, newTextBody: newTextBody)
        
    }

    
    // MARK: - Processing discussion (all messages) remote wipe requests

    
    func processRemoteRequestToWipeAllMessagesWithinThisGroupDiscussion(from contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let requester = self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) else {
            throw ObvError.wipeRequestedByNonGroupMember
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }
        
        // Check that the contact is allowed to make this request
        
        guard requester.isAllowedToRemoteDeleteAnything else {
            throw ObvError.requestToDeleteAllMessagesWithinThisGroupDiscussionFromContactNotAllowedToDoSo
        }

        try discussion.processRemoteRequestToWipeAllMessagesWithinThisDiscussion(from: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
    }

    
    func processRemoteRequestToWipeAllMessagesWithinThisGroupDiscussion(from ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        // Check that the owned identity is allowed to perform a remote deletion
        guard self.ownedIdentityIsAllowedToRemoteDeleteAnything else {
            throw ObvError.ownedIdentityIsNotAllowedToDeleteDiscussion
        }
        
        try discussion.processRemoteRequestToWipeAllMessagesWithinThisDiscussion(from: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

    }
    
    
    func processDiscussionDeletionRequestFromCurrentDevice(of ownedIdentity: PersistedObvOwnedIdentity, deletionType: DeletionType) throws {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        switch deletionType {
        case .local:
            break
        case .global:
            guard self.ownedIdentityIsAllowedToRemoteDeleteAnything else {
                throw ObvError.ownedIdentityIsNotAllowedToDeleteDiscussion
            }
        }
        
        try discussion.processDiscussionDeletionRequestFromCurrentDevice(of: ownedIdentity, deletionType: deletionType)
        
    }

    
    // MARK: - Process reaction requests

    func processSetOrUpdateReactionOnMessageLocalRequest(from ownedIdentity: PersistedObvOwnedIdentity, for message: PersistedMessage, newEmoji: String?) throws {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        guard ownedIdentityIsAllowedToSendMessage else {
            throw ObvError.ownedIdentityIsNotAllowedToSendMessages
        }
        
        try discussion.processSetOrUpdateReactionOnMessageLocalRequest(from: ownedIdentity, for: message, newEmoji: newEmoji)
        
    }

    
    func processSetOrUpdateReactionOnMessageRequest(_ reactionJSON: ReactionJSON, receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {

        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let requester = self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) else {
            throw ObvError.wipeRequestedByNonGroupMember
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }
        
        // Check that the contact is allowed to react
        
        guard requester.isAllowedToSendMessage else {
            throw ObvError.messageReceivedByMemberNotAllowedToSendMessage
        }

        let updatedMessage = try discussion.processSetOrUpdateReactionOnMessageRequest(reactionJSON, receivedFrom: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return updatedMessage

    }


    func processSetOrUpdateReactionOnMessageRequest(_ reactionJSON: ReactionJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        guard ownedIdentityIsAllowedToSendMessage else {
            throw ObvError.ownedIdentityIsNotAllowedToSendMessages
        }
                
        let updatedMessage = try discussion.processSetOrUpdateReactionOnMessageRequest(reactionJSON, receivedFrom: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return updatedMessage

    }
    
    
    // MARK: - Process screen capture detections

    func processDetectionThatSensitiveMessagesWereCaptured(_ screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, from contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) != nil else {
            throw ObvError.wipeRequestedByNonGroupMember
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        try discussion.processDetectionThatSensitiveMessagesWereCaptured(screenCaptureDetectionJSON, from: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
    }
    
    
    func processDetectionThatSensitiveMessagesWereCaptured(_ screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, from ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        try discussion.processDetectionThatSensitiveMessagesWereCaptured(screenCaptureDetectionJSON, from: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

    }

    
    func processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by ownedIdentity: PersistedObvOwnedIdentity) throws {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        try discussion.processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by: ownedIdentity)
        
    }


    // MARK: - Process requests for group v2 shared settings

    func processQuerySharedSettingsRequest(from contact: PersistedObvContactIdentity, querySharedSettingsJSON: QuerySharedSettingsJSON) throws -> (weShouldSendBackOurSharedSettings: Bool, discussionId: DiscussionIdentifier) {
        
        guard self.ownedIdentityIdentity == contact.ownedIdentity?.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard self.otherMembers.first(where: { $0.identity == contact.cryptoId.getIdentity() }) != nil else {
            throw ObvError.wipeRequestedByNonGroupMember
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        let discussionId = try discussion.identifier
        let weShouldSendBackOurSharedSettings = try discussion.processQuerySharedSettingsRequest(querySharedSettingsJSON: querySharedSettingsJSON)
        
        return (weShouldSendBackOurSharedSettings, discussionId)
        
    }

    
    func processQuerySharedSettingsRequest(from ownedIdentity: PersistedObvOwnedIdentity, querySharedSettingsJSON: QuerySharedSettingsJSON) throws -> (weShouldSendBackOurSharedSettings: Bool, discussionId: DiscussionIdentifier) {
        
        guard self.ownedIdentityIdentity == ownedIdentity.identity else {
            throw ObvError.ownedIdentityIsNotPartOfThisGroup
        }

        guard let discussion else {
            throw ObvError.couldNotFindGroupDiscussion
        }

        let discussionId = try discussion.identifier
        let weShouldSendBackOurSharedSettings = try discussion.processQuerySharedSettingsRequest(querySharedSettingsJSON: querySharedSettingsJSON)
        
        return (weShouldSendBackOurSharedSettings, discussionId)
        
    }

    
    // MARK: - ObvError
    
    public enum ObvError: LocalizedError {
        
        case wipeRequestedByNonGroupMember
        case wipeRequestedByMemberNotAllowedToRemoteDelete
        case couldNotFindGroupDiscussion
        case messageReceivedByMemberNotAllowedToSendMessage
        case ownedIdentityIsNotPartOfThisGroup
        case ownedIdentityIsNotAllowedToSendMessages
        case ownedIdentityIsNotAllowedToDeleteThisMessage
        case updateRequestReceivedByMemberNotAllowedToToEditOrRemoteDeleteOwnMessages
        case ownedIdentityIsNotAllowedToEditOrRemoteDeleteOwnMessages
        case requestToDeleteAllMessagesWithinThisGroupDiscussionFromContactNotAllowedToDoSo
        case ownedIdentityIsNotAllowedToDeleteDiscussion
        
        public var errorDescription: String? {
            switch self {
            case .wipeRequestedByNonGroupMember:
                return "Wipe requested by non group member"
            case .wipeRequestedByMemberNotAllowedToRemoteDelete:
                return "Wipe requested by member not allowed to remote delete"
            case .couldNotFindGroupDiscussion:
                return "Could not find group discussion"
            case .messageReceivedByMemberNotAllowedToSendMessage:
                return "Message received by a group member not allowed to send messages"
            case .ownedIdentityIsNotPartOfThisGroup:
                return "Owned identity is not part of this group"
            case .ownedIdentityIsNotAllowedToSendMessages:
                return "Owned identity is not allowed to send messages"
            case .ownedIdentityIsNotAllowedToDeleteThisMessage:
                return "Owned identity is not allowed to delete this message"
            case .updateRequestReceivedByMemberNotAllowedToToEditOrRemoteDeleteOwnMessages:
                return "Update request received from a group member who is not allowed to update her messages"
            case .ownedIdentityIsNotAllowedToEditOrRemoteDeleteOwnMessages:
                return "Owned identity is not allowed to edit or remote delete own messages"
            case .requestToDeleteAllMessagesWithinThisGroupDiscussionFromContactNotAllowedToDoSo:
                return "Request to delete all messages within this group discussion received from a contact who is not allowed to do so"
            case .ownedIdentityIsNotAllowedToDeleteDiscussion:
                return "Owned identity is not allowed to delete this group discussion"
            }
        }
        
    }

}


// MARK: - PersistedGroupV2Member

@objc(PersistedGroupV2Member)
public final class PersistedGroupV2Member: NSManagedObject, Identifiable, ObvErrorMaker {
    
    private static let entityName = "PersistedGroupV2Member"
    public static let errorDomain = "PersistedGroupV2Member"

    // Attributes
    
    @NSManaged private var company: String?
    @NSManaged private var firstName: String?
    @NSManaged private var groupIdentifier: Data // Part of primary key
    @NSManaged public private(set) var identity: Data // Part of primary key
    @NSManaged public private(set) var isPending: Bool
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
    
    public var cryptoId: ObvCryptoId? {
        return try? ObvCryptoId(identity: identity)
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
        guard let contactIdentityCoreDetails = contact.identityCoreDetails else {
            throw Self.makeError(message: "Could not get contact identity core details")
        }
        let identityAndPermissionsAndDetails = ObvGroupV2.IdentityAndPermissionsAndDetails(
            identity: contact.cryptoId,
            permissions: ObvUICoreDataConstants.defaultObvGroupV2PermissionsForNewGroupMembers,
            serializedIdentityCoreDetails: try contactIdentityCoreDetails.jsonEncode(),
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
    public func setPermissionAdmin(to newValue: Bool) {
        let newPermissions: Set<ObvGroupV2.Permission>
        if newValue {
            newPermissions = ObvUICoreDataConstants.defaultObvGroupV2PermissionsForAdmin
        } else {
            newPermissions = ObvUICoreDataConstants.defaultObvGroupV2PermissionsForNewGroupMembers
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
    public func delete() throws {
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
    
    public override func willSave() {
        super.willSave()
        
        if !isInserted && !isDeleted {
            changedKeys = Set<String>(self.changedValues().keys)
        }
        
    }
    
    public override func didSave() {
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
public final class PersistedGroupV2Details: NSManagedObject, ObvErrorMaker {
    
    private static let entityName = "PersistedGroupV2Details"
    public static let errorDomain = "PersistedGroupV2Details"

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
            throw Self.makeError(message: "Could not find context")
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
