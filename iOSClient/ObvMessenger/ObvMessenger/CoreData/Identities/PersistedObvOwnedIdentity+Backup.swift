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

extension PersistedObvOwnedIdentity {

    var backupItem: PersistedObvOwnedIdentityBackupItem {
        let contacts = self.contacts.map { $0.backupItem }.filter { !$0.isEmpty }
        let groups = self.contactGroups.map { $0.backupItem }.filter { !$0.isEmpty }
        return PersistedObvOwnedIdentityBackupItem(
            identity: self.identity,
            contacts: contacts.isEmpty ? nil : contacts,
            groups: groups.isEmpty ? nil : groups)
    }

}


extension PersistedObvOwnedIdentityBackupItem {

    func updateExistingInstance(within context: NSManagedObjectContext) throws {

        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(identity: self.identity, within: context) else {
            assertionFailure()
            throw PersistedObvOwnedIdentityBackupItem.makeError(message: "Could not find owned identity corresponding to backup item")
        }
        for contact in self.contacts ?? [] {
            guard let persistedContact = ownedIdentity.contacts.first(where: {
                $0.cryptoId.getIdentity() == contact.identity })
            else {
                assertionFailure()
                continue
            }
            contact.updateExistingInstance(persistedContact)
        }
        for group in groups ?? [] {
            guard let persistedGroup = ownedIdentity.contactGroups.first(where: {
                $0.groupUid == group.groupUid &&
                $0.ownerIdentity == group.groupOwnerIdentity })
            else {
                assertionFailure()
                continue
            }
            group.updateExistingInstance(persistedGroup)
        }

    }

}
