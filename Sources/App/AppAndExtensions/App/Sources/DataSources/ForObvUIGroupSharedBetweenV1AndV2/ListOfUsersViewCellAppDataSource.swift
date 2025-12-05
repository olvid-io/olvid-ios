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
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes
import ObvAppTypes
import ObvUICoreData
import ObvDesignSystem
import OlvidUtils

@MainActor
final class ListOfUsersViewCellAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var selectUsersToAddViewModelUserStreamManagerForStreamUUID = [UUID: SelectUsersToAddViewModelUserStreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}


extension ListOfUsersViewCellAppDataSource: ListOfUsersViewCellDataSource {
    
    func getAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: ObvUIGroupSharedBetweenV1AndV2.HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User>) {
        let streamManager = try SelectUsersToAddViewModelUserStreamManager(contactIdentifier: identifier, context: backgroundContext)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.selectUsersToAddViewModelUserStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func finishAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: ObvUIGroupSharedBetweenV1AndV2.HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier, streamUUID: UUID) {
        guard let streamManager = selectUsersToAddViewModelUserStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }
    
}


// MARK: - Stream Manager for SelectUsersToAddViewModel.User

extension ListOfUsersViewCellAppDataSource {
    
    private final class SelectUsersToAddViewModelUserStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User, PersistedObvContactIdentity>, @unchecked Sendable {
        
        init(contactIdentifier: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier, context: NSManagedObjectContext) throws {
            let objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>
            switch contactIdentifier {
            case .contactIdentifier(contactIdentifier: _):
                assertionFailure()
                throw ObvError.unexpectedIdentifier
            case .objectIDOfPersistedObvContactIdentity(objectID: let _objectID):
                objectID = .init(objectID: _objectID)
            }
            let frc = PersistedObvContactIdentity.getFetchedResultsController(objectID: objectID, within: context)
            super.init(frc: frc)
        }

        override func createModel(fetchedObjects: [PersistedObvContactIdentity]) throws -> SelectUsersToAddViewModel.User {
            guard let persistedContact = fetchedObjects.first else {
                assertionFailure()
                throw ObvError.contactNotFound
            }
            let model = try ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User(persistedContact: persistedContact)
            return model
        }
        
        enum ObvError: Error {
            case unexpectedIdentifier
            case fetchedObjectsIsNil
            case contactNotFound
        }

    }
        
}


// MARK: - ObvUIGroupV2.SelectUsersToAddViewModel.User from a PersistedObvContactIdentity

extension ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User {

    init(persistedContact: PersistedObvContactIdentity) throws {
        self.init(identifier: .objectIDOfPersistedObvContactIdentity(objectID: persistedContact.objectID),
                  isKeycloakManaged: persistedContact.isCertifiedByOwnKeycloak,
                  profilePictureInitial: persistedContact.circledInitialsConfiguration.initials?.text,
                  circleColors: .init(background: persistedContact.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: persistedContact.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  identityDetails: try persistedContact.identityDetails,
                  isRevokedAsCompromised: false,
                  customDisplayName: persistedContact.customDisplayNameSanitized,
                  customPhotoURL: persistedContact.customPhotoURL)
    }

}
