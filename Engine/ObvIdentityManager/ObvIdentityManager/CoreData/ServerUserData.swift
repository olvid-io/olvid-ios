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
import os.log
import CoreData
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils

@objc(ServerUserData)
class ServerUserData: NSManagedObject, ObvManagedObject {

    var obvContext: ObvContext?

    private static let entityName = "ServerUserData"

    static let rawOwnedIdentityKey = "rawOwnedIdentity"
    static let labelKey = "label"

    // MARK: Attributes

    @NSManaged private(set) var label: String
    @NSManaged private(set) var nextRefreshTimestamp: Date
    @NSManaged private var rawOwnedIdentity: Data

    private(set) var ownedIdentity: ObvCryptoIdentity {
        get { ObvCryptoIdentity(from: rawOwnedIdentity)! }
        set { self.rawOwnedIdentity = newValue.getIdentity() }
    }

    fileprivate convenience init(forEntityName entityName: String, ownedIdentity: ObvCryptoIdentity, label: String, nextRefreshTimestamp: Date, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)

        self.ownedIdentity = ownedIdentity
        self.label = label
        self.nextRefreshTimestamp = nextRefreshTimestamp
    }

    // MARK: Other variables

    @nonobjc static func fetchRequest() -> NSFetchRequest<ServerUserData> {
        return NSFetchRequest<ServerUserData>(entityName: ServerUserData.entityName)
    }

    private struct Predicate {
        static func withLabel(_ label: String) -> NSPredicate {
            NSPredicate(format: "%K == %@", ServerUserData.labelKey, label)
        }
        static func forOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(format: "%K == %@", ServerUserData.rawOwnedIdentityKey, ownedIdentity.getIdentity() as NSData)
        }
    }

    static func getAllServerUserDatas(for ownedIdentity: ObvCryptoIdentity, within context: ObvContext) throws -> Set<ServerUserData> {
        let request: NSFetchRequest<ServerUserData> = ServerUserData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forOwnedIdentity(ownedIdentity)
        ])
        let items = try context.fetch(request)
        return Set(items)
    }

    static func getServerUserData(for ownedIdentity: ObvCryptoIdentity, with label: String, within context: ObvContext) throws -> ServerUserData? {
        let request: NSFetchRequest<ServerUserData> = ServerUserData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withLabel(label),
            Predicate.forOwnedIdentity(ownedIdentity)
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
        } else {
            assertionFailure(); return nil
        }
    }

}

@objc(IdentityServerUserData)
final class IdentityServerUserData: ServerUserData {

    private static let entityName = "IdentityServerUserData"

    convenience init(ownedIdentity: ObvCryptoIdentity, label: String, nextRefreshTimestamp: Date, within obvContext: ObvContext) {
        self.init(forEntityName: IdentityServerUserData.entityName, ownedIdentity: ownedIdentity, label: label, nextRefreshTimestamp: nextRefreshTimestamp, within: obvContext)
    }

    static func createForOwnedIdentityDetails(ownedIdentity: ObvCryptoIdentity, label: String, within obvContext: ObvContext) -> ServerUserData {
        return IdentityServerUserData(ownedIdentity: ownedIdentity,
                                      label: label,
                                      nextRefreshTimestamp: Date() + ObvConstants.userDataRefreshInterval,
                                      within: obvContext)
    }

    fileprivate func toUserDataImpl() -> UserData {
        let kind: UserDataKind = .identity
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

    convenience init(ownedIdentity: ObvCryptoIdentity, label: String, nextRefreshTimestamp: Date, groupUid: UID, within obvContext: ObvContext) {
        self.init(forEntityName: GroupServerUserData.entityName, ownedIdentity: ownedIdentity, label: label, nextRefreshTimestamp: nextRefreshTimestamp, within: obvContext)
        self.groupUid = groupUid
    }

    static func createForOwnedGroupDetails(ownedIdentity: ObvCryptoIdentity, label: String, groupUid: UID, within obvContext: ObvContext) -> ServerUserData {
        return GroupServerUserData(ownedIdentity: ownedIdentity,
                                   label: label,
                                   nextRefreshTimestamp: Date() + ObvConstants.userDataRefreshInterval,
                                   groupUid: groupUid,
                                   within: obvContext)
    }

    fileprivate func toUserDataImpl() -> UserData {
        let kind: UserDataKind = .group(groupUid: groupUid)
        return UserData(ownedIdentity: ownedIdentity, label: label, nextRefreshTimestamp: nextRefreshTimestamp, kind: kind)
    }

}
