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
import ObvDesignSystem



/// Data source for the `ScanValidationView`, providing dynamic updates during the double-scan flow.
///
/// The `ScanValidationView` requires real-time state changes to reflect the progress of the double-scan process:
/// - Initially, it displays a loading state while the contact and discussion are being prepared.
/// - Once the one-to-one discussion is available, it updates to enable navigation to the discussion.
///
/// This data source streams the necessary model updates to drive these UI changes.
final class ObvScanValidationViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    private var scanValidationViewModelStreamManagerForStreamUUID = [UUID: ScanValidationViewModelStreamManager]()

    
}


// MARK: - Implementing ObvScanValidationViewDataSource

extension ObvScanValidationViewAppDataSource: ObvScanValidationViewDataSource {
    
    func getAsyncStreamOfScanValidationViewModel(_ view: ObvInvitationFlow.ScanValidationView, contactIdentifier: ObvTypes.ObvContactIdentifier, contactFullDisplayName: String) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvInvitationFlow.ScanValidationViewModel>) {
        let manager = try ScanValidationViewModelStreamManager(contactIdentifier: contactIdentifier, contactFullDisplayName: contactFullDisplayName, context: backgroundContext)
        scanValidationViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfScanValidationViewModel(_ view: ScanValidationView, streamUUID: UUID) {
        guard let manager = scanValidationViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}

// MARK: - Internal manager

@available(iOS 16.0, *)
extension ObvScanValidationViewAppDataSource {
    
    private final class ScanValidationViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ScanValidationViewModel, PersistedObvContactIdentity, PersistedOneToOneDiscussion>, @unchecked Sendable {
        
        let contactIdentifier: ObvTypes.ObvContactIdentifier
        let contactFullDisplayName: String
        
        init(contactIdentifier: ObvTypes.ObvContactIdentifier, contactFullDisplayName: String, context: NSManagedObjectContext) throws {
            self.contactIdentifier = contactIdentifier
            self.contactFullDisplayName = contactFullDisplayName
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
        
        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedOneToOneDiscussion]) throws -> ScanValidationViewModel {
            
            let persistedContactIdentity = try persistedContactIdentity
            
            if let persistedContactIdentity {
                return try ScanValidationViewModel(persistedContactIdentity: persistedContactIdentity)
            } else {
                return .init(contactStatus: .contactNotAddedYet,
                             contactAvatarModel: .init(contactCryptoId: contactIdentifier.contactCryptoId, contactFullDisplayName: contactFullDisplayName),
                             contactFullDisplayName: contactFullDisplayName,
                             contactIdentifier: contactIdentifier)
            }
        }
        
        enum ObvError: Error {
            case couldNotFetchObjects
        }
    }
    
}


// MARK: - ScanValidationViewModel from a PersistedObvContactIdentity

extension ScanValidationViewModel {
    
    init(persistedContactIdentity: PersistedObvContactIdentity) throws {
        let avatarModel = ObvAvatarViewModel(contact: persistedContactIdentity)
        let contactFullDisplayName = persistedContactIdentity.fullDisplayName
        let contactFirstName = persistedContactIdentity.firstName ?? persistedContactIdentity.shortOriginalName
        self.init(contactStatus: .contactAdded(activeOneToOneDiscussionAvailable: persistedContactIdentity.oneToOneDiscussion != nil && persistedContactIdentity.oneToOneDiscussion?.status == .active, contactFirstName: contactFirstName),
                  contactAvatarModel: avatarModel,
                  contactFullDisplayName: contactFullDisplayName,
                  contactIdentifier: try persistedContactIdentity.obvContactIdentifier)
    }
    
}


// MARK: - ObvAvatarViewModel from a contactCryptoId and a contactFullDisplayName

extension ObvAvatarViewModel {

    init(contactCryptoId: ObvCryptoId, contactFullDisplayName: String) {
        let colors = ObvDesignSystem.AppTheme.shared.identityColors(for: contactCryptoId, using: .hue)
        let characterOrIcon: ObvAvatarViewModel.CharacterOrIcon
        if let character = contactFullDisplayName.trimmingWhitespacesAndNewlines().first {
            characterOrIcon = .character(character)
        } else {
            characterOrIcon = .icon(.person)
        }
        self.init(characterOrIcon: characterOrIcon, colors: .init(foreground: colors.text, background: colors.background), photoURL: nil)
    }

}
