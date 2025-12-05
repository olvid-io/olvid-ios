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
import ObvLicenceActivationFlow
import ObvTypes
import ObvUICoreData
import OlvidUtils


protocol NewLicenseActivationViewControllerAppDataSourceDelegate: AnyObject {
    func getApiKeyElementsFromServer(_ dataSource: NewLicenseActivationViewControllerAppDataSource, ownedCryptoId: ObvCryptoId, apiKey: UUID) async throws -> ObvTypes.APIKeyElements
}



@MainActor
final class NewLicenseActivationViewControllerAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    weak var delegate: NewLicenseActivationViewControllerAppDataSourceDelegate?
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext, delegate: NewLicenseActivationViewControllerAppDataSourceDelegate) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.delegate = delegate
    }
    
    deinit {
        debugPrint("Deinit NewLicenseActivationViewControllerAppDataSource")
    }
    
    private var newLicenseActivationViewModelStreamManagerForStreamUUID = [UUID: NewLicenseActivationViewModelStreamManager]()
    
}


// MARK: - Implementing NewLicenseActivationViewDataSource

extension NewLicenseActivationViewControllerAppDataSource: NewLicenseActivationViewDataSource {
    
//    func getInitialNewLicenseActivationViewModel(_ vc: ObvLicenceActivationFlow.NewLicenseActivationViewController, ownedCryptoId: ObvTypes.ObvCryptoId) -> ObvLicenceActivationFlow.NewLicenseActivationViewModel? {
//        guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: viewContext) else {
//            assertionFailure()
//            return nil
//        }
//        return NewLicenseActivationViewModel(ownedIdentity: ownedIdentity)
//    }
    
    
    func getAsyncStreamOfNewLicenseActivationViewModel(_ view: NewLicenseActivationView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvLicenceActivationFlow.NewLicenseActivationViewModel>) {
        let manager = NewLicenseActivationViewModelStreamManager(ownedCryptoId: ownedCryptoId, context: backgroundContext)
        newLicenseActivationViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfNewLicenseActivationViewModel(_ view: NewLicenseActivationView, streamUUID: UUID) {
        guard let manager = newLicenseActivationViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    func getApiKeyElementsFromServer(_ view: NewLicenseActivationView, ownedCryptoId: ObvCryptoId, apiKey: UUID) async throws -> ObvTypes.APIKeyElements {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.getApiKeyElementsFromServer(self, ownedCryptoId: ownedCryptoId, apiKey: apiKey)
    }
    
}


// MARK: - Errors

extension NewLicenseActivationViewControllerAppDataSource {
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}


// MARK: - Internal managers

extension NewLicenseActivationViewControllerAppDataSource {
    
    private final class NewLicenseActivationViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvLicenceActivationFlow.NewLicenseActivationViewModel, PersistedObvOwnedIdentity>, @unchecked Sendable {
        
        let ownedCryptoId: ObvTypes.ObvCryptoId
        
        init(ownedCryptoId: ObvTypes.ObvCryptoId, context: NSManagedObjectContext) {
            self.ownedCryptoId = ownedCryptoId
            let frc = PersistedObvOwnedIdentity.getFetchedResultsController(ownedCryptoId: ownedCryptoId, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedObvOwnedIdentity]) throws -> NewLicenseActivationViewModel {
            assert(fetchedObjects.count == 1)
            guard let ownedIdentity = fetchedObjects.first else {
                assertionFailure()
                throw ObvError.couldNotFindOwnedIdentity
            }
            let model = NewLicenseActivationViewModel(ownedIdentity: ownedIdentity)
            return model
        }
        
        enum ObvError: Error {
            case couldNotFindOwnedIdentity
        }
        
    }
    
}



// MARK: - Helpers

extension NewLicenseActivationViewModel {
    
    init(ownedIdentity: PersistedObvOwnedIdentity) {

        let isKeycloakManaged = ownedIdentity.isKeycloakManaged
        let isActive: Bool = ownedIdentity.isActive
        
        // This owned identity might benefit from the subscription of another profil (for making calls).
        // So we re-compute the appropriate APIKeyElements
        let currentAPIKeyElements: APIKeyElements = ownedIdentity.apiKeyElements
        let effectiveAPIPermissions: APIPermissions = ownedIdentity.effectiveAPIPermissions
        let effectiveAPIKeyElements = APIKeyElements(
            status: currentAPIKeyElements.status,
            permissions: currentAPIKeyElements.permissions.union(effectiveAPIPermissions),
            expirationDate: currentAPIKeyElements.expirationDate)
        
        self.init(isKeycloakManaged: isKeycloakManaged,
                  currentAPIKeyElements: effectiveAPIKeyElements,
                  isActive: isActive)
        
    }
    
}
