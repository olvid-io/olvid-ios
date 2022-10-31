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

@objc(DisplayedContactGroup)
final class DisplayedContactGroup: NSManagedObject, ObvErrorMaker, Identifiable {
    
    private static let entityName = "DisplayedContactGroup"
    static let errorDomain = "DisplayedContactGroup"
    
    // Attributes

    @NSManaged private(set) var normalizedSearchKey: String
    @NSManaged private(set) var normalizedSortKey: String
    @NSManaged private(set) var ownPermissionAdmin: Bool
    @NSManaged private var photoURL: URL?
    @NSManaged private var rawPublishedDetailsStatus: Int
    @NSManaged private var sectionName: String?
    @NSManaged private(set) var subtitle: String?
    @NSManaged private var title: String?
    @NSManaged private(set) var updateInProgress: Bool
    

    // Relationships
    
    @NSManaged private(set) var groupV1: PersistedContactGroup?
    @NSManaged private(set) var groupV2: PersistedGroupV2?

    // Accessors

    enum GroupKind {
        case groupV1(group: PersistedContactGroup)
        case groupV2(group: PersistedGroupV2)
    }

    var group: GroupKind? {
        if let group = groupV1 {
            assert(groupV2 == nil)
            return .groupV1(group: group)
        } else if let group = groupV2 {
            assert(groupV1 == nil)
            return .groupV2(group: group)
        } else {
            assertionFailure()
            return nil
        }
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
    
    
    var displayedTitle: String {
        guard let title = title, !title.isEmpty else {
            return NSLocalizedString("GROUP_TITLE_WHEN_NO_SPECIFIC_TITLE_IS_GIVEN", comment: "")
        }
        return title
    }
        
    var displayedImage: UIImage? {
        guard let photoURL = self.photoURL else { return nil }
        guard FileManager.default.fileExists(atPath: photoURL.path) else { assertionFailure(); return nil }
        return UIImage(contentsOfFile: photoURL.path)
    }
    
    // Initializer
    
    convenience init(groupV1: PersistedContactGroup) throws {
        guard let context = groupV1.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.groupV1 = groupV1
        self.groupV2 = nil
        updateUsingUnderlyingGroup()
    }

    convenience init(groupV2: PersistedGroupV2) throws {
        guard let context = groupV2.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.groupV1 = nil
        self.groupV2 = groupV2
        self.publishedDetailsStatus = groupV2.hasPublishedDetails ? .unseenPublishedDetails : .noNewPublishedDetails
        updateUsingUnderlyingGroup()
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        context.delete(self)
    }
    
    
    // Updates
    
    func updateUsingUnderlyingGroup() {
        let newNormalizedSearchKey: String
        let newNormalizedSortKey: String
        let newOwnPermissionAdmin: Bool
        let newPhotoURL: URL?
        let newSubtitle: String?
        let newTitle: String?
        let newSectionName: String?
        let newPublishedDetailsStatus: PublishedDetailsStatusType
        let newUpdateInProgress: Bool
        if let groupV1 = groupV1 {
            newNormalizedSearchKey = Self.normalizedSearchKeyFromGroupV1(groupV1)
            newNormalizedSortKey = Self.normalizedSortKeyFromGroupV1(groupV1)
            newOwnPermissionAdmin = (groupV1 is PersistedContactGroupOwned)
            newPhotoURL = Self.photoURLFromGroupV1(groupV1)
            newSectionName = Self.sectionNameFromGroupV1(groupV1)
            newSubtitle = Self.subtitleFromGroupV1(groupV1)
            newTitle = Self.titleFromGroupV1(groupV1)
            newPublishedDetailsStatus = Self.publishedDetailsStatusFromGroupV1(groupV1)
            newUpdateInProgress = false
        } else if let groupV2 = groupV2 {
            newNormalizedSearchKey = Self.normalizedSearchKeyFromGroupV2(groupV2)
            newNormalizedSortKey = Self.normalizedSortKeyFromGroupV2(groupV2)
            newOwnPermissionAdmin = groupV2.ownedIdentityIsAdmin
            newPhotoURL = Self.photoURLFromGroupV2(groupV2)
            newSectionName = Self.sectionNameFromGroupV2(groupV2)
            newSubtitle = Self.subtitleFromGroupV2(groupV2)
            newTitle = Self.titleFromGroupV2(groupV2)
            newPublishedDetailsStatus = Self.publishedDetailsStatusFromGroupV2(groupV2)
            newUpdateInProgress = groupV2.updateInProgress
        } else {
            assertionFailure()
            return
        }
        if self.normalizedSearchKey != newNormalizedSearchKey {
            self.normalizedSearchKey = newNormalizedSearchKey
        }
        if self.normalizedSortKey != newNormalizedSortKey {
            self.normalizedSortKey = newNormalizedSortKey
        }
        if self.ownPermissionAdmin != newOwnPermissionAdmin {
            self.ownPermissionAdmin = newOwnPermissionAdmin
        }
        if self.photoURL != newPhotoURL {
            self.photoURL = newPhotoURL
        }
        if self.sectionName != newSectionName {
            self.sectionName = newSectionName
        }
        if self.subtitle != newSubtitle {
            self.subtitle = newSubtitle
        }
        if self.title != newTitle {
            self.title = newTitle
        }
        if self.publishedDetailsStatus != newPublishedDetailsStatus {
            self.publishedDetailsStatus = newPublishedDetailsStatus
        }
        if self.updateInProgress != newUpdateInProgress {
            self.updateInProgress = newUpdateInProgress
        }
    }
    
    // Utils
    
    private static func normalizedSortKeyFromGroupV1(_ groupV1: PersistedContactGroup) -> String {
        var sortKey = groupV1 is PersistedContactGroupOwned ? "0" : "1"
        sortKey.append(normalizedSearchKeyFromGroupV1(groupV1))
        // Make sure two distinct objects have distinct sort keys
        sortKey.append(groupV1.groupUid.hexString())
        return sortKey
    }

    
    private static func normalizedSortKeyFromGroupV2(_ groupV2: PersistedGroupV2) -> String {
        var sortKey = groupV2.ownedIdentityIsAdmin ? "0" : "1"
        sortKey.append(normalizedSearchKeyFromGroupV2(groupV2))
        // Make sure two distinct objects have distinct sort keys
        sortKey.append(groupV2.groupIdentifier.hexString())
        return sortKey
    }

    
    private static func normalizedSearchKeyFromGroupV1(_ groupV1: PersistedContactGroup) -> String {
        var searchKey = ""
        searchKey.append(groupV1.displayName)
        searchKey.append(groupV1.contactIdentities.compactMap({ $0.customDisplayName }).sorted().joined(separator: "_"))
        searchKey.append(groupV1.contactIdentities.compactMap({ $0.firstName }).sorted().joined(separator: "_"))
        searchKey.append(groupV1.contactIdentities.compactMap({ $0.lastName }).sorted().joined(separator: "_"))
        searchKey.append(groupV1.contactIdentities.compactMap({ $0.displayedCompany }).sorted().joined(separator: "_"))
        searchKey.append(groupV1.contactIdentities.compactMap({ $0.displayedPosition }).sorted().joined(separator: "_"))
        return searchKey
    }

    
    private static func normalizedSearchKeyFromGroupV2(_ groupV2: PersistedGroupV2) -> String {
        var searchKey = ""
        searchKey.append(groupV2.displayNameWithNoDefault ?? "")
        searchKey.append(groupV2.customName ?? "")
        searchKey.append(groupV2.trustedName ?? "")
        searchKey.append(groupV2.trustedDescription ?? "")
        searchKey.append(groupV2.contactsAmongOtherPendingAndNonPendingMembers.compactMap({ $0.customDisplayName }).sorted().joined(separator: "_"))
        searchKey.append(groupV2.contactsAmongOtherPendingAndNonPendingMembers.compactMap({ $0.firstName }).sorted().joined(separator: "_"))
        searchKey.append(groupV2.contactsAmongOtherPendingAndNonPendingMembers.compactMap({ $0.lastName }).sorted().joined(separator: "_"))
        searchKey.append(groupV2.contactsAmongOtherPendingAndNonPendingMembers.compactMap({ $0.displayedCompany }).sorted().joined(separator: "_"))
        searchKey.append(groupV2.contactsAmongOtherPendingAndNonPendingMembers.compactMap({ $0.displayedPosition }).sorted().joined(separator: "_"))
        if searchKey.isEmpty {
            searchKey.append(contentsOf: NSLocalizedString("GROUP_TITLE_WHEN_NO_SPECIFIC_TITLE_IS_GIVEN", comment: ""))
        }
        return searchKey
    }

    
    private static func photoURLFromGroupV1(_ groupV1: PersistedContactGroup) -> URL? {
        groupV1.displayPhotoURL
    }

    
    private static func photoURLFromGroupV2(_ groupV2: PersistedGroupV2) -> URL? {
        groupV2.displayPhotoURL
    }

    
    private static func sectionNameFromGroupV1(_ groupV1: PersistedContactGroup) -> String? {
        groupV1 is PersistedContactGroupOwned ? "0" : "1"
    }

    
    private static func sectionNameFromGroupV2(_ groupV2: PersistedGroupV2) -> String? {
        groupV2.ownedIdentityIsAdmin ? "0" : "1"
    }

    
    private static func subtitleFromGroupV1(_ groupV1: PersistedContactGroup) -> String? {
        groupV1.contactIdentities
            .sorted(by: { $0.sortDisplayName < $1.sortDisplayName })
            .map({ $0.customOrNormalDisplayName })
            .joined(separator: ", ")
    }

    
    private static func subtitleFromGroupV2(_ groupV2: PersistedGroupV2) -> String? {
        groupV2.otherMembersSorted
            .map({
                $0.displayedCustomDisplayName ?? $0.displayedFirstName ?? $0.displayedCustomDisplayNameOrLastName ?? NSLocalizedString("UNKNOWN_USER", comment: "")
            })
            .joined(separator: ", ")
    }

    
    private static func titleFromGroupV1(_ groupV1: PersistedContactGroup) -> String? {
        groupV1.displayName
    }

    
    private static func publishedDetailsStatusFromGroupV1(_ groupV1: PersistedContactGroup) -> PublishedDetailsStatusType {
        if let groupJoined = groupV1 as? PersistedContactGroupJoined {
            return groupJoined.status
        } else {
            return .noNewPublishedDetails
        }
    }

    
    private static func publishedDetailsStatusFromGroupV2(_ groupV2: PersistedGroupV2) -> PublishedDetailsStatusType {
        return groupV2.publishedDetailsStatus
    }

    
    private static func titleFromGroupV2(_ groupV2: PersistedGroupV2) -> String? {
        groupV2.displayNameWithNoDefault
    }

    
    // MARK: - Convenience DB getters
    
    
    struct Predicate {
        enum Key: String {
            case normalizedSearchKey = "normalizedSearchKey"
            case normalizedSortKey = "normalizedSortKey"
            case sectionName = "sectionName"
            case groupV1 = "groupV1"
            case groupV2 = "groupV2"
        }
        private static var underlyingGroupIsV1: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.groupV1)
        }
        private static var underlyingGroupIsV2: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.groupV2)
        }
        private static func withGroupV1OwnedIdentity(_ ownedIdentity: ObvCryptoId) -> NSPredicate {
            let key = [Key.groupV1.rawValue, PersistedContactGroup.ownedIdentityIdentityKey].joined(separator: ".")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                underlyingGroupIsV1,
                NSPredicate(key, EqualToData: ownedIdentity.getIdentity())
            ])
        }
        private static func withGroupV2OwnedIdentity(_ ownedIdentity: ObvCryptoId) -> NSPredicate {
            let key = [Key.groupV2.rawValue, PersistedGroupV2.Predicate.Key.rawOwnedIdentityIdentity.rawValue].joined(separator: ".")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                underlyingGroupIsV2,
                NSPredicate(key, EqualToData: ownedIdentity.getIdentity())
            ])
        }
        static func withOwnedIdentity(_ ownedIdentity: ObvCryptoId) -> NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                withGroupV1OwnedIdentity(ownedIdentity),
                withGroupV2OwnedIdentity(ownedIdentity),
            ])
        }
        static func withContactIdentity(_ contactIdentity: ObvCryptoId) -> NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                withContactIdentityInGroupV1(contactIdentity),
                withContactIdentityInGroupV2(contactIdentity),
            ])
        }
        private static func withContactIdentityInGroupV1(_ contactIdentity: ObvCryptoId) -> NSPredicate {
            let predicateChain = [Key.groupV1.rawValue,
                                  PersistedContactGroup.Predicate.Key.contactIdentities.rawValue,
                                  PersistedObvContactIdentity.Predicate.Key.identity.rawValue].joined(separator: ".")
            let predicateFormat = "ANY \(predicateChain) == %@"
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                underlyingGroupIsV1,
                NSPredicate(format: predicateFormat, contactIdentity.cryptoIdentity.getIdentity() as NSData)
            ])
        }
        private static func withContactIdentityInGroupV2(_ contactIdentity: ObvCryptoId) -> NSPredicate {
            let predicateChain = [Key.groupV2.rawValue,
                                  PersistedGroupV2.Predicate.Key.rawOtherMembers.rawValue,
                                  PersistedGroupV2Member.Predicate.Key.rawContact.rawValue,
                                  PersistedObvContactIdentity.Predicate.Key.identity.rawValue].joined(separator: ".")
            let predicateFormat = "ANY \(predicateChain) == %@"
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                underlyingGroupIsV2,
                NSPredicate(format: predicateFormat, contactIdentity.cryptoIdentity.getIdentity() as NSData)
            ])
        }
        static func searchPredicate(_ searchedText: String) -> NSPredicate {
            NSPredicate(format: "%K contains[cd] %@", Predicate.Key.normalizedSearchKey.rawValue, searchedText)
        }
        static func displayedContactGroup(withObjectID objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(format: "SELF == %@", objectID)
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<DisplayedContactGroup> {
        return NSFetchRequest<DisplayedContactGroup>(entityName: DisplayedContactGroup.entityName)
    }

    
    static func getFetchRequestForAllDisplayedContactGroup(ownedIdentity: ObvCryptoId, andPredicate: NSPredicate?) -> NSFetchRequest<DisplayedContactGroup> {
        var predicates = [Predicate.withOwnedIdentity(ownedIdentity)]
        if andPredicate != nil {
            predicates.append(andPredicate!)
        }
        let request: NSFetchRequest<DisplayedContactGroup> = DisplayedContactGroup.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.normalizedSortKey.rawValue, ascending: true)]
        return request
    }

    
    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> DisplayedContactGroup? {
        let request: NSFetchRequest<DisplayedContactGroup> = DisplayedContactGroup.fetchRequest()
        request.predicate = Predicate.displayedContactGroup(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    // MARK: - On save

    override func willSave() {
        super.willSave()
        
        // This code is a workaround preventing a crash of the collection view showing all `DisplayedContactGroup`.
        // The crash occurs when a `DisplayedContactGroup` changes `sectionName` (a case that occurs when the owned identity admin role changes).
        // So, when the sectionName changes, instead of saving the updated `DisplayedContactGroup`, we delete it and create a new one.
        if !isInserted && !isDeleted && changedValues().keys.contains(where: { $0 == Predicate.Key.sectionName.rawValue }) {
            do {
                if let groupV1 = self.groupV1 {
                    try self.delete()
                    _ = try DisplayedContactGroup(groupV1: groupV1)
                } else if let groupV2 = groupV2 {
                    try self.delete()
                    _ = try DisplayedContactGroup(groupV2: groupV2)
                } else {
                    assertionFailure()
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
        
    }
    
    
    override func didSave() {
        super.didSave()
        
        if isInserted {
            ObvMessengerGroupV2Notifications.displayedContactGroupWasJustCreated(objectID: self.typedObjectID)
                .postOnDispatchQueue()
        }
        
    }
}
