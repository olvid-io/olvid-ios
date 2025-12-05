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
import CoreData
import ObvUIGroupV1
import ObvUIGroupV2
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes
import ObvUICoreData


final class GroupCreationNavigationStackAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

}


extension GroupCreationNavigationStackAppDataSource: GroupCreationNavigationStackDataSource {
    
    @MainActor
    func getContactIdentifierOfGroupMember(_ view: ObvUIGroupV2.GroupV2CreationNavigationStack, contactIdentifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier) async throws -> ObvTypes.ObvContactIdentifier {
        switch contactIdentifier {
        case .contactIdentifierForExistingGroupForPreviews(groupIdentifier: _, contactIdentifier: let contactIdentifier):
            assertionFailure("This identifier kind should only be used in previews")
            return contactIdentifier
        case .objectIDOfPersistedGroupV2Member(groupIdentifier: _, objectID: let objectID):
            guard let persistedMember = try PersistedGroupV2Member.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindGroupMember
            }
            let memberCryptoId = persistedMember.cryptoId
            let ownedCryptoId = try persistedMember.persistedGroup.ownCryptoId
            return ObvContactIdentifier(contactCryptoId: memberCryptoId, ownedCryptoId: ownedCryptoId)
        case .contactIdentifierForCreatingGroupForPreviews(contactIdentifier: let contactIdentifier):
            assertionFailure("This identifier kind should only be used in previews")
            return contactIdentifier
        case .objectIDOfPersistedContact(objectID: let objectID, usageContext: let usageContext):
            switch usageContext {
            case .groupCreation:
                break
            case .groupV1Display:
                assertionFailure("This identifier kind is unexpected during a group v2 creation")
                throw ObvError.unexpectedContactIdentifier
            }
            guard let persistedContact = try PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindContact
            }
            return try persistedContact.obvContactIdentifier
        case .objectIDOfPersistedPendingGroupMember:
            assertionFailure("This identifier kind is unexpected during a group v2 creation")
            throw ObvError.unexpectedContactIdentifier
        }
    }
    
    @MainActor
    func getContactIdentifierOfGroupMember(_ view: ObvUIGroupV2.GroupV2CreationNavigationStack, contactIdentifier: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier) async throws -> ObvTypes.ObvContactIdentifier {
        return try await self.getContactIdentifierOfGroupMember(contactIdentifier: contactIdentifier)
    }
    
}


extension GroupCreationNavigationStackAppDataSource: GroupV1CreationNavigationStackDataSource {
    
    func getContactIdentifierOfGroupMember(_ view: ObvUIGroupV1.GroupV1CreationNavigationStack, contactIdentifier: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier) async throws -> ObvTypes.ObvContactIdentifier {
        return try await self.getContactIdentifierOfGroupMember(contactIdentifier: contactIdentifier)
    }
    
}

// MARK: - Private helpers

extension GroupCreationNavigationStackAppDataSource {
    
    @MainActor
    func getContactIdentifierOfGroupMember(contactIdentifier: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier) async throws -> ObvTypes.ObvContactIdentifier {
        switch contactIdentifier {
        case .contactIdentifier(contactIdentifier: let contactIdentifier):
            return contactIdentifier
        case .objectIDOfPersistedObvContactIdentity(objectID: let objectID):
            guard let persistedContact = try PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindContact
            }
            return try persistedContact.obvContactIdentifier
        }
    }

    
}


extension GroupCreationNavigationStackAppDataSource {
    
    enum ObvError: Error {
        case couldNotFindGroupMember
        case couldNotFindContact
        case unexpectedContactIdentifier
    }
    
}
