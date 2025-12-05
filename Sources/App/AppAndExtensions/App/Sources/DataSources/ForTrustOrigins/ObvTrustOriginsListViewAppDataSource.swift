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
import OlvidUtils
import ObvTypes
import ObvCells
import ObvUICoreData


protocol ObvTrustOriginsListViewAppDataSourceDelegate: AnyObject {
    func getAsyncStreamOfObvTrustOrigin(_ dataSource: ObvTrustOriginsListViewAppDataSource, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<[ObvTrustOrigin]>)
    func finishAsyncStreamOfObvTrustOrigin(_ dataSource: ObvTrustOriginsListViewAppDataSource, streamUUID: UUID)
}


final class ObvTrustOriginsListViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    weak var delegate: ObvTrustOriginsListViewAppDataSourceDelegate?
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext, delegate: ObvTrustOriginsListViewAppDataSourceDelegate) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.delegate = delegate
    }
        
    private var trustOriginsListViewModelStreamManagerForStreamUUID = [UUID: ObvTrustOriginsListViewModelStreamManager]()
    
}



// MARK: - Implementing ObvTrustOriginsListViewDataSource

extension ObvTrustOriginsListViewAppDataSource: ObvTrustOriginsListViewDataSource {
    
    func getAsyncStreamOfObvTrustOriginsListViewModel(_ view: ObvCells.ObvTrustOriginsListView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvCells.ObvTrustOriginsListView.Model>) {
        let manager = ObvTrustOriginsListViewModelStreamManager(contactIdentifier: contactIdentifier, delegate: self, context: backgroundContext)
        trustOriginsListViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try manager.startStream()
    }
    
    func finishAsyncStreamOfObvTrustOriginsListViewModel(_ view: ObvCells.ObvTrustOriginsListView, streamUUID: UUID) {
        guard let manager = trustOriginsListViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}


extension ObvTrustOriginsListViewAppDataSource: ObvTrustOriginsListViewAppDataSource.ObvTrustOriginsListViewModelStreamManagerDelegate {
    
    private func getAsyncStreamOfObvTrustOrigin(_ streamManager: ObvTrustOriginsListViewModelStreamManager, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<[ObvTypes.ObvTrustOrigin]>) {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.getAsyncStreamOfObvTrustOrigin(self, contactIdentifier: contactIdentifier)
    }
    
    
    private func finishAsyncStreamOfObvTrustOrigin(_ streamManager: ObvTrustOriginsListViewModelStreamManager, streamUUID: UUID) {
        guard let delegate else { assertionFailure(); return }
        delegate.finishAsyncStreamOfObvTrustOrigin(self, streamUUID: streamUUID)
    }
    
}


// MARK: - Internal managers

extension ObvTrustOriginsListViewAppDataSource {
    
    private protocol ObvTrustOriginsListViewModelStreamManagerDelegate: AnyObject {
        func getAsyncStreamOfObvTrustOrigin(_ streamManager: ObvTrustOriginsListViewModelStreamManager, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<[ObvTrustOrigin]>)
        func finishAsyncStreamOfObvTrustOrigin(_ streamManager: ObvTrustOriginsListViewModelStreamManager, streamUUID: UUID)
    }
    
    private final class ObvTrustOriginsListViewModelStreamManager: @unchecked Sendable {
        
        private weak var delegate: ObvTrustOriginsListViewModelStreamManagerDelegate?
        private let contactIdentifier: ObvTypes.ObvContactIdentifier
        private let context: NSManagedObjectContext
        private var engineStreamUUID: UUID?
        let streamUUID = UUID()
        private var continuation: AsyncStream<ObvTrustOriginsListView.Model>.Continuation?

        init(contactIdentifier: ObvTypes.ObvContactIdentifier, delegate: ObvTrustOriginsListViewModelStreamManagerDelegate, context: NSManagedObjectContext) {
            self.delegate = delegate
            self.contactIdentifier = contactIdentifier
            self.context = context
        }
        
        
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvCells.ObvTrustOriginsListView.Model>) {
            let stream = AsyncStream<ObvCells.ObvTrustOriginsListView.Model> { (continuation: AsyncStream<ObvTrustOriginsListView.Model>.Continuation) in
                self.continuation = continuation
                Task { await streamObvTrustOriginFromEngine() }
            }
            return (self.streamUUID, stream)
        }

        func finishStream() {
            if let engineStreamUUID {
                delegate?.finishAsyncStreamOfObvTrustOrigin(self, streamUUID: engineStreamUUID)
            }
        }

        private func streamObvTrustOriginFromEngine() async {
            do {
                assert(engineStreamUUID == nil)
                guard let delegate else {
                    assertionFailure()
                    throw ObvError.delegateIsNil
                }
                let (engineStreamUUID, streamFromEngine) = try await delegate.getAsyncStreamOfObvTrustOrigin(self, contactIdentifier: contactIdentifier)
                self.engineStreamUUID = engineStreamUUID
                for await trustOrigins in streamFromEngine {
                    await context.perform { [weak self] in
                        guard let self else { return }
                        do {
                            let model = try createModel(trustOrigins: trustOrigins)
                            continuation?.yield(model)
                        } catch {
                            assertionFailure(error.localizedDescription)
                            // In production, continue with the next engine's update
                        }
                    }
                }
            } catch {
                assertionFailure()
            }
        }
        
        
        private func createModel(trustOrigins: [ObvTrustOrigin]) throws -> ObvCells.ObvTrustOriginsListView.Model {
            let trustOriginCellViewModel: [ObvTrustOriginCellView.Model] = trustOrigins.map { obvTrustOrigin in
                    .init(trustOrigin: obvTrustOrigin, context: context)
            }
            return .init(trustOrigins: trustOriginCellViewModel)
        }
        
    }
    
}


// MARK: - ObvTrustOriginCellView.Model from ObvTrustOrigin

extension ObvTrustOriginCellView.Model {
    
    init(trustOrigin: ObvTrustOrigin, context: NSManagedObjectContext) {
        
        let kind: TrustOriginKind
        switch trustOrigin {
            
        case .direct:
            kind = .direct
            
        case .group(contactIdentifier: _, timestamp: _, groupOwner: let groupOwner):
            let groupOwnerName: String?
            if let groupOwner = try? PersistedObvContactIdentity.get(
                persisted: .init(contactCryptoId: groupOwner,
                                 ownedCryptoId: trustOrigin.contactIdentifier.ownedCryptoId),
                whereOneToOneStatusIs: .any,
                within: context) {
                groupOwnerName = groupOwner.customOrShortDisplayName
            } else {
                groupOwnerName = nil
            }
            kind = .groupV1(groupOwner: groupOwner, groupOwnerName: groupOwnerName)
            
        case .introduction(contactIdentifier: _, timestamp: _, mediator: let mediator):
            let mediatorName: String?
            if let mediator = try? PersistedObvContactIdentity.get(
                persisted: .init(contactCryptoId: mediator,
                                 ownedCryptoId: trustOrigin.contactIdentifier.ownedCryptoId),
                whereOneToOneStatusIs: .any,
                within: context) {
                mediatorName = mediator.customOrShortDisplayName
            } else {
                mediatorName = nil
            }
            kind = .introduction(mediator: mediator, mediatorName: mediatorName)
            
        case .keycloak:
            kind = .keycloak
            
        case .serverGroupV2(contactIdentifier: _, timestamp: _, groupIdentifier: let groupIdentifier):
            let groupName: String?
            if let group = try? PersistedGroupV2.get(ownIdentity: trustOrigin.contactIdentifier.ownedCryptoId, appGroupIdentifier: groupIdentifier.appGroupIdentifier, within: context) {
                groupName = group.displayName
            } else {
                groupName = nil
            }
            kind = .groupV2Server(groupIdentifier: groupIdentifier, groupName: groupName)
            
        }
        
        self.init(
            contactIdentifier: trustOrigin.contactIdentifier,
            date: trustOrigin.date,
            kind: kind)
    }
    
}
