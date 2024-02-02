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
import ObvCrypto
import ObvEncoder
import OlvidUtils
import ObvTypes
import ObvUICoreData
import ObvSettings


final class PersistedContactGroupToDisplayedContactGroupV49ToV50: NSEntityMigrationPolicy, ObvErrorMaker {
    
    static let errorDomain = "MessengerMigrationV49ToV50"
    static let debugPrintPrefix = "[\(errorDomain)][PersistedContactGroupToDisplayedContactGroupV49ToV50]"

    // Tested
    override func end(_ mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        // This method is called once for this entity, after all relationships of all entities have been re-created.
        
        debugPrint("\(Self.debugPrintPrefix) end(_ mapping: NSEntityMapping, manager: NSMigrationManager) starts")
        defer {
            debugPrint("\(Self.debugPrintPrefix) end(_ mapping: NSEntityMapping, manager: NSMigrationManager) ends")
        }

        // Look for all PersistedContactGroup entities in the destination context
        
        let persistedContactGroups: [NSManagedObject]
        do {
            let request = NSFetchRequest<NSManagedObject>(entityName: "PersistedContactGroup")
            request.fetchBatchSize = 100
            persistedContactGroups = try manager.destinationContext.fetch(request)
        }
        
        // For each groupV1, we create a DisplayedContactGroup
        
        for groupV1 in persistedContactGroups {
            
            // To facilitate the creation of the destination object (DisplayedContactGroup), we create a `PersistedContactGroupStruct` from the source instance (PersistedContactGroup)
            
            let persistedContactGroup = try PersistedContactGroupStruct(groupV1)

            // We create the DisplayedContactGroup instance
            
            let displayedContactGroup = try createDisplayedContactGroupFromPersistedContactGroup(persistedContactGroup, manager: manager)

            // We set the relationship
            
            displayedContactGroup.setValue(groupV1, forKey: "groupV1")
            
        }
                
    }
    

    /// This private helper struct allows easy access to the values stored in a `PersistedContactGroup` managed object
    private struct PersistedContactGroupStruct: ObvErrorMaker {
        
        static let errorDomain = "MessengerMigrationV49ToV50"

        let groupName: String
        let groupUidRaw: Data
        let ownerIdentity: Data
        let rawCategory: Int
        let rawOwnedIdentityIdentity: Data
        let groupNameCustom: String? // Always nil for a group owned
        public let ownPermissionAdmin: Bool
        let customPhotoFilename: String?
        let photoURL: URL?
        let rawStatus: Int

        let contactIdentities: [PersistedObvContactIdentityStruct]
        
        var displayName: String {
            return self.groupNameCustom ?? self.groupName
        }

        var groupUid: UID {
            return UID(uid: groupUidRaw)!
        }

        var customPhotoURL: URL? {
            guard let customPhotoFilename = customPhotoFilename else { return nil }
            return ObvUICoreDataConstants.ContainerURL.forCustomGroupProfilePictures.appendingPathComponent(customPhotoFilename)
        }

        var displayPhotoURL: URL? {
            return self.customPhotoURL ?? self.photoURL
        }

        init(_ persistedContactGroup: NSManagedObject) throws {
            guard let groupName = persistedContactGroup.value(forKey: "groupName") as? String else {
                assertionFailure()
                throw Self.makeError(message: "Could not extract the groupName of a PersistedContactGroup")
            }
            guard let groupUidRaw = persistedContactGroup.value(forKey: "groupUidRaw") as? Data else {
                assertionFailure()
                throw Self.makeError(message: "Could not extract the groupUidRaw of a PersistedContactGroup")
            }
            guard let ownerIdentity = persistedContactGroup.value(forKey: "ownerIdentity") as? Data else {
                assertionFailure()
                throw Self.makeError(message: "Could not extract the ownerIdentity of a PersistedContactGroup")
            }
            guard let rawCategory = persistedContactGroup.value(forKey: "rawCategory") as? Int else {
                assertionFailure()
                throw Self.makeError(message: "Could not extract the rawCategory of a PersistedContactGroup")
            }
            guard let rawOwnedIdentityIdentity = persistedContactGroup.value(forKey: "rawOwnedIdentityIdentity") as? Data else {
                assertionFailure()
                throw Self.makeError(message: "Could not extract the rawOwnedIdentityIdentity of a PersistedContactGroup")
            }
            let groupNameCustom = persistedContactGroup.primitiveValue(forKey: "groupNameCustom") as? String
            let ownPermissionAdmin = persistedContactGroup.entity.name == "PersistedContactGroupOwned"
            guard let contactIdentities = try (persistedContactGroup.value(forKey: "contactIdentities") as? Set<NSManagedObject>)?.map({
                try PersistedObvContactIdentityStruct($0)
            }) else {
                throw Self.makeError(message: "Could not extract the contactIdentities of a PersistedContactGroup")
            }
            let customPhotoFilename = persistedContactGroup.primitiveValue(forKey: "customPhotoFilename") as? String
            let photoURL = persistedContactGroup.value(forKey: "photoURL") as? URL
            let rawStatus = persistedContactGroup.value(forKey: "rawStatus") as? Int ?? 0
            self.groupName = groupName
            self.groupUidRaw = groupUidRaw
            self.ownerIdentity = ownerIdentity
            self.rawCategory = rawCategory
            self.rawOwnedIdentityIdentity = rawOwnedIdentityIdentity
            self.groupNameCustom = groupNameCustom
            self.ownPermissionAdmin = ownPermissionAdmin
            self.contactIdentities = contactIdentities
            self.customPhotoFilename = customPhotoFilename
            self.photoURL = photoURL
            self.rawStatus = rawStatus
        }

    }
    
    
    /// This private helper struct allows easy access to the values stored in a `PersistedObvContactIdentity` managed object
    private struct PersistedObvContactIdentityStruct: ObvErrorMaker {
        
        static let errorDomain = "MessengerMigrationV49ToV50"

        let customDisplayName: String?
        let identityCoreDetails: ObvIdentityCoreDetails
        let sortDisplayName: String
        
        var firstName: String? {
            return identityCoreDetails.firstName
        }

        var lastName: String? {
            return identityCoreDetails.lastName
        }

        var displayedCompany: String? {
            return identityCoreDetails.company
        }

        var displayedPosition: String? {
            return identityCoreDetails.position
        }
        
        var customOrNormalDisplayName: String {
            return customDisplayName ?? mediumOriginalName
        }

        var personNameComponents: PersonNameComponents {
            var pnc = identityCoreDetails.personNameComponents
            pnc.nickname = customDisplayName
            return pnc
        }

        var mediumOriginalName: String {
            let formatter = PersonNameComponentsFormatter()
            formatter.style = .medium
            return formatter.string(from: personNameComponents)
        }

        init(_ persistedObvContactIdentity: NSManagedObject) throws {
            let customDisplayName = persistedObvContactIdentity.value(forKey: "customDisplayName") as? String
            guard let serializedIdentityCoreDetails = persistedObvContactIdentity.value(forKey: "serializedIdentityCoreDetails") as? Data else {
                assertionFailure()
                throw Self.makeError(message: "Could not extract the serializedIdentityCoreDetails of a PersistedObvContactIdentity")
            }
            guard let identityCoreDetails = try? ObvIdentityCoreDetails(serializedIdentityCoreDetails) else {
                assertionFailure()
                throw Self.makeError(message: "Could not deserialize the serializedIdentityCoreDetails of a PersistedObvContactIdentity")
            }
            let sortDisplayName = [customDisplayName,
                                   identityCoreDetails.firstName,
                                   identityCoreDetails.lastName,
                                   identityCoreDetails.position,
                                   identityCoreDetails.company]
                .compactMap { $0 }
                .joined(separator: "_")
            self.customDisplayName = customDisplayName
            self.identityCoreDetails = identityCoreDetails
            self.sortDisplayName = sortDisplayName
        }
        
    }
    
    
    private static func normalizedSearchKeyFromGroupV1(_ groupV1: PersistedContactGroupStruct) -> String {
        var searchKey = ""
        searchKey.append(groupV1.displayName)
        searchKey.append(groupV1.contactIdentities.compactMap({ $0.customDisplayName }).sorted().joined(separator: "_"))
        searchKey.append(groupV1.contactIdentities.compactMap({ $0.firstName }).sorted().joined(separator: "_"))
        searchKey.append(groupV1.contactIdentities.compactMap({ $0.lastName }).sorted().joined(separator: "_"))
        searchKey.append(groupV1.contactIdentities.compactMap({ $0.displayedCompany }).sorted().joined(separator: "_"))
        searchKey.append(groupV1.contactIdentities.compactMap({ $0.displayedPosition }).sorted().joined(separator: "_"))
        return searchKey
    }

    
    private static func normalizedSortKeyFromGroupV1(_ groupV1: PersistedContactGroupStruct) -> String {
        var sortKey = groupV1.ownPermissionAdmin ? "0" : "1"
        sortKey.append(normalizedSearchKeyFromGroupV1(groupV1))
        // Make sure two distinct objects have distinct sort keys
        sortKey.append(groupV1.groupUid.hexString())
        return sortKey
    }

    
    private static func photoURLFromGroupV1(_ groupV1: PersistedContactGroupStruct) -> URL? {
        groupV1.displayPhotoURL
    }

    
    private static func subtitleFromGroupV1(_ groupV1: PersistedContactGroupStruct) -> String? {
        groupV1.contactIdentities
            .sorted(by: { $0.sortDisplayName < $1.sortDisplayName })
            .map({ $0.customOrNormalDisplayName })
            .joined(separator: ", ")
    }

    
    private static func titleFromGroupV1(_ groupV1: PersistedContactGroupStruct) -> String? {
        groupV1.displayName
    }

    
    private static func sectionNameFromGroupV1(_ groupV1: PersistedContactGroupStruct) -> String? {
        groupV1.ownPermissionAdmin ? "0" : "1"
    }

    
    private static func rawPublishedDetailsStatusFromGroupV1(_ groupV1: PersistedContactGroupStruct) -> Int {
        return groupV1.rawStatus
    }

    
    
    private func createDisplayedContactGroupFromPersistedContactGroup(_ groupV1: PersistedContactGroupStruct, manager: NSMigrationManager) throws -> NSManagedObject {
        
        let newNormalizedSearchKey: String = Self.normalizedSearchKeyFromGroupV1(groupV1)
        let newNormalizedSortKey: String = Self.normalizedSortKeyFromGroupV1(groupV1)
        let newOwnPermissionAdmin: Bool = groupV1.ownPermissionAdmin
        let newPhotoURL: URL? = Self.photoURLFromGroupV1(groupV1)
        let newSubtitle: String? = Self.subtitleFromGroupV1(groupV1)
        let newTitle: String? = Self.titleFromGroupV1(groupV1)
        let newSectionName: String? = Self.sectionNameFromGroupV1(groupV1)
        let newRawPublishedDetailsStatus: Int = Self.rawPublishedDetailsStatusFromGroupV1(groupV1)
        let newUpdateInProgress: Bool = false
        
        let dInstance: NSManagedObject
        do {
            let dEntityName = "DisplayedContactGroup"
            guard let description = NSEntityDescription.entity(forEntityName: dEntityName, in: manager.destinationContext) else {
                throw Self.makeError(message: "Invalid entity name: \(dEntityName)")
            }
            dInstance = NSManagedObject(entity: description, insertInto: manager.destinationContext)
        }

        dInstance.setValue(newNormalizedSearchKey, forKey: "normalizedSearchKey")
        dInstance.setValue(newNormalizedSortKey, forKey: "normalizedSortKey")
        dInstance.setValue(newOwnPermissionAdmin, forKey: "ownPermissionAdmin")
        dInstance.setValue(newPhotoURL, forKey: "photoURL")
        dInstance.setValue(newUpdateInProgress, forKey: "rawPublishedDetailsStatus")
        dInstance.setValue(newSectionName, forKey: "sectionName")
        dInstance.setValue(newSubtitle, forKey: "subtitle")
        dInstance.setValue(newTitle, forKey: "title")
        dInstance.setValue(newRawPublishedDetailsStatus, forKey: "updateInProgress")

        return dInstance
        
    }

}
