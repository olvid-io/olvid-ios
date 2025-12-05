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
import ObvUICoreData
import ObvDesignSystem
import OlvidUtils
import ObvOwnedIdentityChooser


@MainActor
public final class OwnedIdentityChooserViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let anyContext: NSManagedObjectContext

    private var ownedIdentityChooserViewModelStreamManagerForStreamUUID = [UUID: OwnedIdentityChooserViewModelStreamManager]()

    public init(viewContext: NSManagedObjectContext, anyContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        self.viewContext = viewContext
        self.anyContext = anyContext
    }
    
}


// MARK: - Implementing ObvProfilePictureBarButtonItemViewDataSource

extension OwnedIdentityChooserViewAppDataSource: OwnedIdentityChooserViewDataSource {
    
    // For the view allowing to choose a profile among all profiles
    
    public func getAsyncStreamOfOwnedIdentityChooserViewModel(_ view: ObvOwnedIdentityChooser.OwnedIdentityChooserView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvOwnedIdentityChooser.OwnedIdentityChooserViewModel>) {
        let manager = OwnedIdentityChooserViewModelStreamManager(currentOwnedCryptoId: currentOwnedCryptoId, context: anyContext)
        ownedIdentityChooserViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    public func finishAsyncStreamOfOwnedIdentityChooserViewModel(_ view: ObvOwnedIdentityChooser.OwnedIdentityChooserView, streamUUID: UUID) {
        guard let manager = ownedIdentityChooserViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    

}


extension OwnedIdentityChooserViewAppDataSource {
    
    enum ObvError: Error {
        case delegateNotSet
    }
    
}


// MARK: - Internal Managers

extension OwnedIdentityChooserViewAppDataSource {
    
    private final class OwnedIdentityChooserViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvOwnedIdentityChooser.OwnedIdentityChooserViewModel, PersistedObvOwnedIdentity>, @unchecked Sendable {
        
        let currentOwnedCryptoId: ObvCryptoId // Always include the current owned crypto in the stream (as it might correspond to a hidden identity)
        
        init(currentOwnedCryptoId: ObvCryptoId, context: NSManagedObjectContext) {
            self.currentOwnedCryptoId = currentOwnedCryptoId
            let frc = PersistedObvOwnedIdentity.getFetchedResultsControllerForAllOwnedIdentities(within: context)
            super.init(frc: frc)
        }
        
        
        override func createModel(fetchedObjects: [PersistedObvOwnedIdentity]) throws -> OwnedIdentityChooserViewModel {
            
            let ownedIdentities: [OwnedIdentityChooserViewModel.OwnedIdentity] = fetchedObjects
                .filter { ownedIdentity in
                    // We always keep the current crypto id. Otherwise, we sure the profile is not hidden
                    ownedIdentity.cryptoId == currentOwnedCryptoId || !ownedIdentity.isHidden
                }
                .map { ownedIdentity in
                    OwnedIdentityChooserViewModel.OwnedIdentity(ownedIdentity: ownedIdentity)
                }

            return .init(ownedIdentities: ownedIdentities)
            
        }

        enum ObvError: Error {
            case couldNotFindPersistedObvOwnedIdentity
        }

    }
        
}


extension OwnedIdentityChooserViewModel.OwnedIdentity {
    
    init(ownedIdentity: PersistedObvOwnedIdentity) {

        let title: String
        let subtitle: String
        if let customDisplayName = ownedIdentity.customDisplayName {
            title = customDisplayName
            let name = ownedIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
            let positionAtCompany = ownedIdentity.identityCoreDetails.getDisplayNameWithStyle(.positionAtCompany)
            if positionAtCompany.isEmpty {
                subtitle = name
            } else {
                subtitle = "\(name) (\(positionAtCompany))"
            }
        } else {
             title = ownedIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
             subtitle = ownedIdentity.identityCoreDetails.getDisplayNameWithStyle(.positionAtCompany)
        }

        self.init(ownedCryptoId: ownedIdentity.cryptoId,
                  avatarViewModel: ObvAvatarViewModel(ownedIdentity: ownedIdentity),
                  title: title,
                  subtitle: subtitle,
                  totalBadgeCount: ownedIdentity.totalBadgeCount,
                  showGreenShield: ownedIdentity.circledInitialsConfiguration.showGreenShield,
                  showRedShield: ownedIdentity.circledInitialsConfiguration.showRedShield,
                  showHiddenProfileIcon: ownedIdentity.isHidden)
        
    }
    
}
