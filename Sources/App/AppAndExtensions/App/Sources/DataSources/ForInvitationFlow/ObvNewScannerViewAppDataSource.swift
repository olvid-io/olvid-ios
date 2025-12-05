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
import OlvidUtils
import ObvUICoreData
import ObvEngine



final class ObvNewScannerViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var scannerViewModelStreamManagerForStreamUUID = [UUID: ObvNewScannerViewModelStreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}


// MARK: - Implementing ObvNewScannerViewDataSource

extension ObvNewScannerViewAppDataSource: ObvNewScannerViewDataSource {
    
    func getAsyncStreamOfObvNewScannerViewModel(_ view: ObvInvitationFlow.NewScannerView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvInvitationFlow.ObvNewScannerViewModel>) {
        let manager = ObvNewScannerViewModelStreamManager(contactIdentifier: contactIdentifier, context: backgroundContext)
        scannerViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfObvNewScannerViewModel(_ view: ObvInvitationFlow.NewScannerView, streamUUID: UUID) {
        guard let manager = scannerViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


// MARK: - Internal managers

extension ObvNewScannerViewAppDataSource {
    
    private final class ObvNewScannerViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvNewScannerViewModel, PersistedObvContactIdentity, PersistedOneToOneDiscussion>, @unchecked Sendable {
        
        let contactIdentifier: ObvTypes.ObvContactIdentifier
        private var observationTokens = [NSObjectProtocol]()
        private var aNewDirectTrustOriginWasCreated = false

        init(contactIdentifier: ObvTypes.ObvContactIdentifier, context: NSManagedObjectContext) {
            self.contactIdentifier = contactIdentifier
            let frc1 = PersistedObvContactIdentity.getFetchedResultsControllerForContactIdentifier(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: context)
            let frc2 = PersistedOneToOneDiscussion.getFetchedResultControllerOfPersistedDiscussionOneToOneContactID(contactId: contactIdentifier, within: context)
            super.init(frc1: frc1, frc2: frc2)
            observeNewTrustOrigin()
        }
        
        
        /// Observes engine notifications for new `TrustOrigin` insertions.
        ///
        /// This observation is necessary when scanning an invitation link for an existing one-to-one contact.
        /// In such cases, a direct discussion with the contact already exists, but a double-scan protocol may be required
        /// to add an additional trust origin to that contact.
        ///
        /// The view waits for two conditions to be met before displaying the confirmation view:
        /// 1. A one-to-one discussion exists.
        /// 2. A new trust origin is added.
        ///
        /// When a new trust origin is inserted, the engine sends a notification.
        /// Upon receiving this notification, the local property `aNewDirectTrustOriginWasCreated` is set to `true`,
        /// and a new version of the model is yielded. All subsequent model versions will reflect this change.
        ///
        /// - Note: This method ensures the confirmation view is only shown after both conditions are satisfied.
        private func observeNewTrustOrigin() {
            observationTokens.append(contentsOf: [
                ObvEngineNotificationNew.observeAPersistedTrustOriginWasInserted(within: NotificationCenter.default) { [weak self] trustOrigin in
                    Task {
                        guard let self else { return }
                        switch trustOrigin {
                        case .direct(contactIdentifier: let contactIdentifier, _):
                            guard self.contactIdentifier == contactIdentifier else { return }
                            if !self.aNewDirectTrustOriginWasCreated {
                                self.aNewDirectTrustOriginWasCreated = true
                                Task { [weak self] in
                                    guard let self else { return }
                                    do {
                                        try await getFetchedObjectsAndYieldModelIfNeeded()
                                    } catch {
                                        assertionFailure(error.localizedDescription)
                                    }
                                }
                            }
                        case .group, .introduction, .keycloak, .serverGroupV2:
                            return
                        }
                    }
                }
            ])
        }
        
        
        override func finishStream() {
            super.finishStream()
            observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
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
        
        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedOneToOneDiscussion]) throws -> ObvNewScannerViewModel {
            
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
            
            return .init(scanValidationViewModel: scanValidationViewModel,
                         aNewDirectTrustOriginWasCreated: aNewDirectTrustOriginWasCreated)

        }
        
        enum ObvError: Error {
            case couldNotFetchObjects
        }
    }

}
