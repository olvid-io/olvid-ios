/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

import SwiftUI
import CoreData
import ObvLocation
import ObvDesignSystem
import ObvUICoreData
import ObvTypes
import OlvidUtils



@MainActor
final class ObvMapViewControllerAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    private var mapViewModelStreamManagerForGivenOwnedIdentityForStreamUUID = [UUID : ObvMapViewModelStreamManagerForGivenOwnedIdentity]()
    private var mapViewModelStreamManagerForGivenMessage = [UUID : ObvMapViewModelStreamManagerForGivenMessage]()

}


extension ObvMapViewControllerAppDataSource: ObvLocation.ObvMapViewDataSource {
    
    func getAsyncStreamOfObvMapViewModel(_ view: some View,
                                         kind: ObvLocation.ObvMapViewKind) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvMapViewModel>) {
        switch kind {
        case .forGivenMessage(let persistedMessageObjectID):
            let manager = try ObvMapViewModelStreamManagerForGivenMessage(messageObjectID: .init(objectID: persistedMessageObjectID), viewContext: viewContext)
            mapViewModelStreamManagerForGivenMessage[manager.streamUUID] = manager
            return try await manager.startStream()
        case .forGivenOwnedCryptoId(let ownedCryptoId):
            let manager = try ObvMapViewModelStreamManagerForGivenOwnedIdentity(ownedCryptoId: ownedCryptoId, context: backgroundContext)
            mapViewModelStreamManagerForGivenOwnedIdentityForStreamUUID[manager.streamUUID] = manager
            return try await manager.startStream()
        }
    }
    
    
    func finishAsyncStreamOfObvMapViewModel(_ view: some View, streamUUID: UUID) {
        if let manager = mapViewModelStreamManagerForGivenOwnedIdentityForStreamUUID.removeValue(forKey: streamUUID) {
            manager.finishStream()
        }
        if let manager = mapViewModelStreamManagerForGivenMessage.removeValue(forKey: streamUUID) {
            manager.finishStream()
        }
    }
    
    
}


@available(iOS 17.0, *)
extension ObvMapViewControllerAppDataSource {
    
    enum ObvError: Error {
        case delegateIsNotSet
    }
    
}

// MARK: - Internal manager when an owned crypto was specified

extension ObvMapViewControllerAppDataSource {
    
    private final class ObvMapViewModelStreamManagerForGivenOwnedIdentity: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvLocation.ObvMapViewModel, PersistedLocationContinuous, PersistedObvOwnedDevice>, @unchecked Sendable {
        
        private let ownedCryptoId: ObvCryptoId
        private var currentRefreshTask: Task<Void, any Error>?

        init(ownedCryptoId: ObvCryptoId, context: NSManagedObjectContext) throws {
            self.ownedCryptoId = ownedCryptoId
            let frc1 = PersistedLocationContinuous.getFetchedResultsControllerForNotExpiredContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice(ownedCryptoId: ownedCryptoId, within: context)
            let frc2 = PersistedObvOwnedDevice.getFetchedResultsControllerForCurrentOwnedDevice(ownedCryptoId: ownedCryptoId, within: context)
            super.init(frc1: frc1, frc2: frc2)
        }
        
        
        override func createModel(fetchedObjects1: [PersistedLocationContinuous], fetchedObjects2: [PersistedObvOwnedDevice]) throws -> ObvMapViewModel {

            // Note that we don't need to filter out the location from the current owned device, as the frc is configured to exclude it from the fetched objects.
            // The first fetch request filters out expired shared location, but only wrt the date when the request was created. So we must also filter out expired locations here.
            
            let locations = fetchedObjects1.filter { !$0.isSharingLocationExpired }
            guard let persistedCurrentOwnedDevice = fetchedObjects2.first else { assertionFailure(); throw ObvError.couldNotFetchObjects }

            // If one of the received continuous shared locations expires in the future, we should request a refresh in the future.
            
            if let minExpirationDate = locations.compactMap({ $0.sharingExpiration }).filter({ $0 > .now }).min() {
                refresh(at: minExpirationDate)
            }

            // Create an return the model
            
            let currentOwnedDevice = try ObvMapViewModel.CurrentOwnedDevice(currentOwnedDevice: persistedCurrentOwnedDevice)
            let deviceLocations = try locations.map { try ObvMapViewModel.DeviceLocation(continousLocation: $0) }
            
            let model = ObvLocation.ObvMapViewModel(
                currentOwnedDevice: currentOwnedDevice,
                deviceLocations: deviceLocations)
            
            return model

        }
        
        
        private func createAndYieldModelIfNeeded() {
            let context = frc1.managedObjectContext
            context.perform { [weak self] in
                guard let self else { return }
                guard let fetchedObjects1 = self.frc1.fetchedObjects, let fetchedObjects2 = self.frc2.fetchedObjects else { return }
                guard let model = try? createModel(fetchedObjects1: fetchedObjects1, fetchedObjects2: fetchedObjects2) else { assertionFailure(); return }
                self.yieldModelIfNeeded(model: model, within: context)
            }
        }

        
        /// Schedules a refresh at the earliest expiration date among all continuous locations.
        ///
        /// When continuous locations have expiration dates, this method receives the nearest
        /// expiration and schedules a refresh to occur at that time, ensuring expired
        /// locations are removed promptly.
        private func refresh(at date: Date) {
            let timeIntervalSinceNow = date.timeIntervalSinceNow
            guard timeIntervalSinceNow > 0 else { return }
            currentRefreshTask?.cancel()
            currentRefreshTask = Task { [weak self] in
                try await Task.sleep(seconds: timeIntervalSinceNow)
                guard let self else { return }
                createAndYieldModelIfNeeded()
            }
        }
            
        enum ObvError: Error {
            case couldNotFetchObjects
        }

    }
    
}


// MARK: - Internal manager when a message was specified

extension ObvMapViewControllerAppDataSource {

    
    private final class ObvMapViewModelStreamManagerForGivenMessage: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvLocation.ObvMapViewModel, PersistedLocationContinuous, PersistedObvOwnedDevice>, @unchecked Sendable {
        
        private var currentRefreshTask: Task<Void, any Error>?

        @MainActor
        init(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, viewContext: NSManagedObjectContext) throws {
            assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
            guard let message = try PersistedMessage.get(with: messageObjectID, within: viewContext) else {
                assertionFailure()
                throw ObvError.messageNotFound
            }
            guard let discussion = message.discussion else {
                assertionFailure()
                throw ObvError.discussionNotFound
            }
            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId else {
                assertionFailure()
                throw ObvError.ownedCryptoIdNotFound
            }
            let frc1 = try PersistedLocationContinuous.getFetchedResultsControllerForContinuousLocations(in: discussion)
            let frc2 = PersistedObvOwnedDevice.getFetchedResultsControllerForCurrentOwnedDevice(ownedCryptoId: ownedCryptoId, within: viewContext)
            super.init(frc1: frc1, frc2: frc2)
        }

        
        override func createModel(fetchedObjects1: [PersistedLocationContinuous], fetchedObjects2: [PersistedObvOwnedDevice]) throws -> ObvMapViewModel {
            
            // The first fetch request filters out expired shared location, but only wrt the date when the request was created. So we must also filter out expired locations here.
            // Note that we filter out the location from the current owned device, as the map knows how to locate the current device.

            guard let persistedCurrentOwnedDevice = fetchedObjects2.first else { assertionFailure(); throw ObvError.couldNotFetchObjects }
            let locations = fetchedObjects1
                .filter({ !$0.isSharingLocationExpired })
                .filter({ ($0 as? PersistedLocationContinuousSent)?.ownedDevice?.objectID != persistedCurrentOwnedDevice.objectID })

            // If one of the received continuous shared locations expires in the future, we should request a refresh in the future.
            
            if let minExpirationDate = locations.compactMap({ $0.sharingExpiration }).filter({ $0 > .now }).min() {
                refresh(at: minExpirationDate)
            }

            // Create an return the model
            
            let currentOwnedDevice = try ObvMapViewModel.CurrentOwnedDevice(currentOwnedDevice: persistedCurrentOwnedDevice)
            let deviceLocations = try locations.map { try ObvMapViewModel.DeviceLocation(continousLocation: $0) }
            
            let model = ObvLocation.ObvMapViewModel(
                currentOwnedDevice: currentOwnedDevice,
                deviceLocations: deviceLocations)
            
            return model

            
        }
        
        
        private func createAndYieldModelIfNeeded() {
            let context = frc1.managedObjectContext
            context.perform { [weak self] in
                guard let self else { return }
                guard let fetchedObjects1 = self.frc1.fetchedObjects, let fetchedObjects2 = self.frc2.fetchedObjects else { return }
                guard let model = try? createModel(fetchedObjects1: fetchedObjects1, fetchedObjects2: fetchedObjects2) else { assertionFailure(); return }
                self.yieldModelIfNeeded(model: model, within: context)
            }
        }

        
        /// Schedules a refresh at the earliest expiration date among all continuous locations.
        ///
        /// When continuous locations have expiration dates, this method receives the nearest
        /// expiration and schedules a refresh to occur at that time, ensuring expired
        /// locations are removed promptly.
        private func refresh(at date: Date) {
            let timeIntervalSinceNow = date.timeIntervalSinceNow
            guard timeIntervalSinceNow > 0 else { return }
            currentRefreshTask?.cancel()
            currentRefreshTask = Task { [weak self] in
                try await Task.sleep(seconds: timeIntervalSinceNow)
                guard let self else { return }
                createAndYieldModelIfNeeded()
            }
        }

        
        enum ObvError: Error {
            case messageNotFound
            case discussionNotFound
            case couldNotFetchObjects
            case ownedCryptoIdNotFound
        }

    }
    
}


fileprivate extension ObvLocation.ObvMapViewModel.DeviceLocation {
    
    init(continousLocation: PersistedLocationContinuous) throws {
        
        let coordinate = ObvLocationCoordinate2D(location: continousLocation)
        let avatarViewModel = try continousLocation.avatarViewModel

        let deviceIdentifier: ObvDeviceIdentifier
        
        if let continuousLocationSend = continousLocation as? PersistedLocationContinuousSent {
            guard let ownedDevice = continuousLocationSend.ownedDevice else {
                assertionFailure()
                throw ObvErrorForCoreDataInitializer.ownedDeviceIsNil
            }
            deviceIdentifier = try ownedDevice.obvDeviceIdentifier
        } else if let continuousLocationReceived = continousLocation as? PersistedLocationContinuousReceived {
            guard let contactDevice = continuousLocationReceived.contactDevice else {
                assertionFailure()
                throw ObvErrorForCoreDataInitializer.contactDeviceIsNil
            }
            deviceIdentifier = try contactDevice.obvDeviceIdentifier
        } else {
            assertionFailure()
            throw ObvErrorForCoreDataInitializer.unexpectedPersistedLocationContinuousType
        }
        
        self.init(deviceIdentifier: deviceIdentifier,
                  coordinate: coordinate,
                  avatarViewModel: avatarViewModel)

        
    }
    
    enum ObvErrorForCoreDataInitializer: Error {
        case unexpectedPersistedLocationContinuousType
        case ownedDeviceIsNil
        case contactDeviceIsNil
    }

}


fileprivate extension ObvMapViewModel.CurrentOwnedDevice {
    
    init(currentOwnedDevice: PersistedObvOwnedDevice) throws {
        guard currentOwnedDevice.secureChannelStatus == .currentDevice else {
            assertionFailure()
            throw ObvErrorForCoreDataInitializer.ownedDeviceIsNotTheCurrentOne
        }
        self.init(deviceIdentifier: try currentOwnedDevice.obvDeviceIdentifier,
                  avatarViewModel: try currentOwnedDevice.avatarViewModel)
    }
    
    enum ObvErrorForCoreDataInitializer: Error {
        case ownedDeviceIsNotTheCurrentOne
    }
    
}


fileprivate extension ObvLocation.ObvLocationCoordinate2D {
    
    init(location: PersistedLocation) {
        self.init(latitude: location.latitude, longitude: location.longitude)
    }
    
}
