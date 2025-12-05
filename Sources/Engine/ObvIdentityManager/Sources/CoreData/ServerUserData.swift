/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import CoreData
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils


@objc(ServerUserData)
class ServerUserData: NSManagedObject, ObvErrorMaker {

    private static let entityName = "ServerUserData"
    public static let errorDomain = "ServerUserData"
    
    static weak var delegateManager: ObvIdentityDelegateManager?

    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ServerUserData.logSubsystem, category: "ServerUserData") }()

    // MARK: Attributes

    @NSManaged private(set) var nextRefreshTimestamp: Date
    @NSManaged private var rawLabel: Data
    @NSManaged private var rawOwnedIdentity: Data

    private(set) var ownedIdentity: ObvCryptoIdentity {
        get { ObvCryptoIdentity(from: rawOwnedIdentity)! }
        set { self.rawOwnedIdentity = newValue.getIdentity() }
    }

    fileprivate convenience init(forEntityName entityName: String, ownedIdentity: ObvCryptoIdentity, label: UID, nextRefreshTimestamp: Date, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.ownedIdentity = ownedIdentity
        self.label = label
        self.nextRefreshTimestamp = nextRefreshTimestamp
    }

    func deleteServerUserData() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context") }
        context.delete(self)
    }
    
    // MARK: Other variables
    
    // Expected to be non nil
    private(set) var label: UID? {
        get {
            guard let uid = UID(uid: rawLabel) else { assertionFailure(); return nil }
            return uid
        }
        set {
            guard let value = newValue else { assertionFailure(); return }
            self.rawLabel = value.raw
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<ServerUserData> {
        return NSFetchRequest<ServerUserData>(entityName: ServerUserData.entityName)
    }

    fileprivate struct ServerUserDataPredicate {
        enum Key: String {
            case nextRefreshTimestamp = "nextRefreshTimestamp"
            case rawLabel = "rawLabel"
            case rawOwnedIdentity = "rawOwnedIdentity"
        }
        static func withLabel(_ label: UID) -> NSPredicate {
            NSPredicate(Key.rawLabel, EqualToData: label.raw)
        }
        static func forOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentity, EqualToData: ownedIdentity.getIdentity())
        }
    }

    static func getAllServerUserDatas(for ownedIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> Set<ServerUserData> {
        let request: NSFetchRequest<ServerUserData> = ServerUserData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ServerUserDataPredicate.forOwnedIdentity(ownedIdentity)
        ])
        let items = try context.fetch(request)
        return Set(items)
    }

    static func getServerUserData(for ownedIdentity: ObvCryptoIdentity, with label: UID, within context: NSManagedObjectContext) throws -> ServerUserData? {
        let request: NSFetchRequest<ServerUserData> = ServerUserData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ServerUserDataPredicate.withLabel(label),
            ServerUserDataPredicate.forOwnedIdentity(ownedIdentity)
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func updateNextRefreshTimestamp() {
        self.nextRefreshTimestamp = Date() + ObvConstants.userDataRefreshInterval
    }

    func toUserData() -> UserData? {
        if let identityUserData = self as? IdentityServerUserData {
            return identityUserData.toUserDataImpl()
        } else if let groupUserData = self as? GroupServerUserData {
            return groupUserData.toUserDataImpl()
        } else if let groupV2UserData = self as? GroupV2ServerUserData {
            return groupV2UserData.toUserDataImpl()
        } else {
            assertionFailure(); return nil
        }
    }
    
}

@objc(IdentityServerUserData)
final class IdentityServerUserData: ServerUserData {

    private static let entityName = "IdentityServerUserData"

    convenience init(ownedIdentity: ObvCryptoIdentity, label: UID, nextRefreshTimestamp: Date, within context: NSManagedObjectContext) {
        self.init(forEntityName: IdentityServerUserData.entityName,
                  ownedIdentity: ownedIdentity,
                  label: label,
                  nextRefreshTimestamp: nextRefreshTimestamp,
                  within: context)
    }

    static func createForOwnedIdentityDetails(ownedIdentity: ObvCryptoIdentity, label: UID, within context: NSManagedObjectContext) -> ServerUserData {
        return IdentityServerUserData(ownedIdentity: ownedIdentity,
                                      label: label,
                                      nextRefreshTimestamp: Date.now + ObvConstants.userDataRefreshInterval,
                                      within: context)
    }

    fileprivate func toUserDataImpl() -> UserData? {
        let kind: UserDataKind = .identity
        guard let label = label else { assertionFailure(); return nil }
        return UserData(ownedIdentity: ownedIdentity, label: label, nextRefreshTimestamp: nextRefreshTimestamp, kind: kind)
    }

}



@objc(GroupServerUserData)
final class GroupServerUserData: ServerUserData {

    private static let entityName = "GroupServerUserData"

    @NSManaged private var rawGroupUid: Data

    private(set) var groupUid: UID {
        get { UID(uid: rawGroupUid)! }
        set { rawGroupUid = newValue.raw }
    }

    convenience init(ownedIdentity: ObvCryptoIdentity, label: UID, nextRefreshTimestamp: Date, groupUid: UID, within context: NSManagedObjectContext) {
        self.init(forEntityName: GroupServerUserData.entityName,
                  ownedIdentity: ownedIdentity,
                  label: label,
                  nextRefreshTimestamp: nextRefreshTimestamp,
                  within: context)
        self.groupUid = groupUid
    }

    static func createForOwnedGroupDetails(ownedIdentity: ObvCryptoIdentity, label: UID, groupUid: UID, within context: NSManagedObjectContext) -> ServerUserData {
        return GroupServerUserData(ownedIdentity: ownedIdentity,
                                   label: label,
                                   nextRefreshTimestamp: Date() + ObvConstants.userDataRefreshInterval,
                                   groupUid: groupUid,
                                   within: context)
    }

    fileprivate func toUserDataImpl() -> UserData? {
        let kind: UserDataKind = .group(groupUid: groupUid)
        guard let label = self.label else { assertionFailure(); return nil }
        return UserData(ownedIdentity: ownedIdentity, label: label, nextRefreshTimestamp: nextRefreshTimestamp, kind: kind)
    }

}



@objc(GroupV2ServerUserData)
final class GroupV2ServerUserData: ServerUserData {

    private static let entityName = "GroupV2ServerUserData"

    @NSManaged private var rawCategory: Int  // Part of GroupV2.Identifier
    @NSManaged private var rawGroupUID: Data  // Part of GroupV2.Identifier
    @NSManaged private var rawServerURL: URL // Part of GroupV2.Identifier

    private(set) var groupIdentifier: GroupV2.Identifier? {
        get {
            guard let category = GroupV2.Identifier.Category(rawValue: rawCategory),
                  let groupUID = UID(uid: rawGroupUID)  else { assertionFailure(); return nil }
            return GroupV2.Identifier(groupUID: groupUID, serverURL: rawServerURL, category: category)
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawGroupUID = newValue.groupUID.raw
            self.rawServerURL = newValue.serverURL
            self.rawCategory = newValue.category.rawValue
        }
    }

    convenience init(ownedIdentity: ObvCryptoIdentity, label: UID, nextRefreshTimestamp: Date, groupIdentifier: GroupV2.Identifier, within context: NSManagedObjectContext) {
        self.init(forEntityName: GroupV2ServerUserData.entityName,
                  ownedIdentity: ownedIdentity,
                  label: label,
                  nextRefreshTimestamp: nextRefreshTimestamp,
                  within: context)
        self.groupIdentifier = groupIdentifier
    }

    static func getOrCreateIfRequiredForAdministratedGroupV2Details(ownedIdentity: ObvCryptoIdentity, label: UID, groupIdentifier: GroupV2.Identifier, nextRefreshTimestampOnCreation: Date? = nil, within context: NSManagedObjectContext) throws -> ServerUserData {
        if let groupV2ServerUserData = try GroupV2ServerUserData.getGroupV2ServerUserData(ownedIdentity: ownedIdentity, label: label, groupIdentifier: groupIdentifier, within: context) {
            return groupV2ServerUserData
        } else {
            let nextRefreshTimestamp: Date
            if let nextRefreshTimestampOnCreation {
                nextRefreshTimestamp = nextRefreshTimestampOnCreation
            } else {
                nextRefreshTimestamp = Date() + ObvConstants.userDataRefreshInterval
            }
            return GroupV2ServerUserData(ownedIdentity: ownedIdentity,
                                         label: label,
                                         nextRefreshTimestamp: nextRefreshTimestamp,
                                         groupIdentifier: groupIdentifier,
                                         within: context)
        }
    }

    fileprivate func toUserDataImpl() -> UserData? {
        guard let groupIdentifier else { assertionFailure(); return nil }
        let kind: UserDataKind = .groupV2(groupIdentifier: groupIdentifier)
        guard let label = self.label else { assertionFailure(); return nil }
        return UserData(ownedIdentity: ownedIdentity, label: label, nextRefreshTimestamp: nextRefreshTimestamp, kind: kind)
    }

    
    // Convenience DB methods
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<GroupV2ServerUserData> {
        return NSFetchRequest<GroupV2ServerUserData>(entityName: GroupV2ServerUserData.entityName)
    }

    private struct Predicate {
        enum Key: String {
            case rawCategory = "rawCategory"
            case rawGroupUID = "rawGroupUID"
            case rawServerURL = "rawServerURL"
        }
        static func withGroupV2Identifier(_ groupIdentifier: GroupV2.Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.rawCategory, EqualToInt: groupIdentifier.category.rawValue),
                NSPredicate(Key.rawGroupUID, EqualToData: groupIdentifier.groupUID.raw),
                NSPredicate(Key.rawServerURL, EqualToUrl: groupIdentifier.serverURL),
            ])
        }
    }

    static func getGroupV2ServerUserData(ownedIdentity: ObvCryptoIdentity, label: UID, groupIdentifier: GroupV2.Identifier, within context: NSManagedObjectContext) throws -> ServerUserData? {
        let request: NSFetchRequest<ServerUserData> = ServerUserData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ServerUserDataPredicate.forOwnedIdentity(ownedIdentity),
            ServerUserDataPredicate.withLabel(label),
            Predicate.withGroupV2Identifier(groupIdentifier),
        ])
        request.fetchLimit = 1
        let items = try context.fetch(request)
        return items.first
    }
    
}
