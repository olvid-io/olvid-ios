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
import ObvInvitationFlow
import ObvTypes
import ObvUICoreData
import OlvidUtils


@MainActor
final class ObvExternalInvitationHandlerViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var externalInvitationHandlerViewModelStreamManagerForStreamUUID = [UUID: ObvExternalInvitationHandlerViewModelStreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

}


// MARK: - Implementing ObvExternalInvitationHandlerViewDataSource

extension ObvExternalInvitationHandlerViewAppDataSource: ObvExternalInvitationHandlerViewDataSource {
    
    func getAsyncStreamOfObvExternalInvitationHandlerViewModel(_ view: ObvInvitationFlow.ExternalInvitationHandlerView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvInvitationFlow.ObvExternalInvitationHandlerViewModel>) {
        let manager = ObvExternalInvitationHandlerViewModelStreamManager(contactIdentifier: contactIdentifier, context: backgroundContext)
        externalInvitationHandlerViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfObvExternalInvitationHandlerViewModel(_ view: ObvInvitationFlow.ExternalInvitationHandlerView, streamUUID: UUID) {
        guard let manager = externalInvitationHandlerViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


// MARK: - Internal managers

extension ObvExternalInvitationHandlerViewAppDataSource {
    
    private final class ObvExternalInvitationHandlerViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvExternalInvitationHandlerViewModel, PersistedObvContactIdentity, PersistedOneToOneDiscussion>, @unchecked Sendable {
        
        let contactIdentifier: ObvTypes.ObvContactIdentifier
        
        init(contactIdentifier: ObvTypes.ObvContactIdentifier, context: NSManagedObjectContext) {
            self.contactIdentifier = contactIdentifier
            let frc1 = PersistedObvContactIdentity.getFetchedResultsControllerForContactIdentifier(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: context)
            let frc2 = PersistedOneToOneDiscussion.getFetchedResultControllerOfPersistedDiscussionOneToOneContactID(contactId: contactIdentifier, within: context)
            super.init(frc1: frc1, frc2: frc2)
        }
        
        public var persistedContactIdentity: PersistedObvContactIdentity? {
            get throws {
                let frc = self.frc1
                
                guard let fetchedObjects = frc.fetchedObjects else {
                    assertionFailure()
                    throw ObvError.couldNotFetchObjects
                }
                
                assert(fetchedObjects.count <= 1)
                
                guard let persistedContactIdentity = fetchedObjects.first else {
                    return nil
                }
                
                return persistedContactIdentity
            }
        }
        
        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedOneToOneDiscussion]) throws -> ObvExternalInvitationHandlerViewModel {
            
            let persistedContactIdentity = try persistedContactIdentity
            
            let scanValidationViewModel: ScanValidationViewModel
            if let persistedContactIdentity {
                scanValidationViewModel = try .init(persistedContactIdentity: persistedContactIdentity)
            } else {
                scanValidationViewModel = .init(contactStatus: .contactNotAddedYet,
                                                contactAvatarModel: .init(contactCryptoId: contactIdentifier.contactCryptoId, contactFullDisplayName: ""),
                                                contactFullDisplayName: "", // Since contactStatus is .contactNotAddedYet, the UI will discard the streamed model anyway
                                                contactIdentifier: contactIdentifier)
            }
            
            return .init(scanValidationViewModel: scanValidationViewModel)

        }
        
        enum ObvError: Error {
            case couldNotFetchObjects
        }

    }
    
}
