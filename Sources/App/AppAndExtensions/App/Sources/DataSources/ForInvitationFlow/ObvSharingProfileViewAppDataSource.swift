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
import ObvTypes
import ObvInvitationFlow
import ObvUICoreData
import OlvidUtils
import ObvDesignSystem
import ObvEngine

@MainActor
final class ObvSharingProfileViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    private let obvEngine: ObvEngine
    
    private var invitationFlowViewModelStreamManagerForStreamUUID = [UUID: InvitationFlowViewModelStreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext, obvEngine: ObvEngine) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.obvEngine = obvEngine
    }
    
}


// MARK: - Implementing ObvSharingProfileViewDataSource

extension ObvSharingProfileViewAppDataSource: ObvSharingProfileViewDataSource {
    
    func getAsyncStreamOfInvitationFlowViewModel(_ view: ObvInvitationFlow.SharingProfileView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvInvitationFlow.SharingProfileViewModel>) {
        let manager = try InvitationFlowViewModelStreamManager(currentOwnedCryptoId: currentOwnedCryptoId, context: backgroundContext, obvEngine: obvEngine)
        invitationFlowViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfInvitationFlowViewModel(_ view: ObvInvitationFlow.SharingProfileView, streamUUID: UUID) {
        guard let manager = invitationFlowViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
        
}

// MARK: - Internal managers

extension ObvSharingProfileViewAppDataSource {
    
    private final class InvitationFlowViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<SharingProfileViewModel, PersistedObvOwnedIdentity>, @unchecked Sendable {
        
        let obvEngine: ObvEngine
            
        @MainActor
        init(currentOwnedCryptoId: ObvCryptoId, context: NSManagedObjectContext, obvEngine: ObvEngine) throws {
            self.obvEngine = obvEngine
            let frc = PersistedObvOwnedIdentity.getFetchedResultsController(ownedCryptoId: currentOwnedCryptoId, within: context)
            super.init(frc: frc)
        }
        
        public var persistedOwnedIdentity: PersistedObvOwnedIdentity {
            get throws {
                let frc = self.frc
                
                guard let fetchedObjects = frc.fetchedObjects else {
                    assertionFailure()
                    throw ObvError.couldNotFetchObjects
                }
                
                assert(fetchedObjects.count <= 1)
                
                guard let persistedOwnedIdentity = fetchedObjects.first else {
                    // This happens when the discussion gets deleted
                    throw ObvError.objectDoesNotExist
                }
                
                return persistedOwnedIdentity
            }
        }
        
        override func createModel(fetchedObjects: [PersistedObvOwnedIdentity]) throws -> SharingProfileViewModel {
            
            let persistedOwnedIdentity = try persistedOwnedIdentity
            
            guard let model = SharingProfileViewModel(persistedOwnedIdentity: persistedOwnedIdentity, urlScanned: false, obvEngine: obvEngine) else {
                throw ObvError.couldNotCreateModel
            }
            
            return model
        }
        
        enum ObvError: Error {
            case couldNotFetchObjects
            case objectDoesNotExist
            case couldNotCreateModel
        }
    }
}

// MARK: -

extension SharingProfileViewModel {
    init?(persistedOwnedIdentity: PersistedObvOwnedIdentity, urlScanned: Bool, obvEngine: ObvEngine) {
        
        guard let obvOwnedIdentity = try? obvEngine.getOwnedIdentity(with: persistedOwnedIdentity.cryptoId) else {
            return nil
        }
                
        let avatarModel = ObvAvatarViewModel(ownedIdentity: persistedOwnedIdentity)
        let fullName = persistedOwnedIdentity.customOrNormalDisplayName
        let role = persistedOwnedIdentity.identityCoreDetails.positionAtCompany()
        
        self.init(fullName: fullName,
                  role: role,
                  urlIdentityRepresentation: obvOwnedIdentity.getGenericIdentity().getObvURLIdentity().urlRepresentation(for: .sharing),
                  avatarModel: avatarModel,
                  scanStep: .noScan,
                  isURLScanned: urlScanned)
        
    }
    
}
