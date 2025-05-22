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
import ObvLocation
import ObvDesignSystem
import ObvUICoreData
import ObvTypes



@available(iOS 17.0, *)
protocol ObvMapViewControllerAppDataSourceDelegate: AnyObject {
    func fetchAvatar(_ vc: ObvMapViewControllerAppDataSource, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
}


@available(iOS 17.0, *)
@MainActor
final class ObvMapViewControllerAppDataSource {
    
    private enum StreamManagerKind {
        case forGivenMessage(ObvMapViewModelStreamManagerForGivenMessage)
        case forGivenOwnedCryptoId(ObvMapViewModelStreamManagerForGivenOwnedCryptoIdentity)
    }
    
    private let streamManagerKind: StreamManagerKind
    private weak var delegate: ObvMapViewControllerAppDataSourceDelegate?
    
    init(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, delegate: ObvMapViewControllerAppDataSourceDelegate) throws {
        let streamManager = try ObvMapViewModelStreamManagerForGivenMessage(messageObjectID: messageObjectID)
        self.streamManagerKind = .forGivenMessage(streamManager)
        self.delegate = delegate
    }
     
    
    init(ownedCryptoId: ObvCryptoId, delegate: ObvMapViewControllerAppDataSourceDelegate) {
        let streamManager = ObvMapViewModelStreamManagerForGivenOwnedCryptoIdentity(ownedCryptoId: ownedCryptoId)
        self.streamManagerKind = .forGivenOwnedCryptoId(streamManager)
        self.delegate = delegate
    }
    
}


@available(iOS 17.0, *)
extension ObvMapViewControllerAppDataSource: ObvMapViewControllerDataSource {
    
    func getAsyncStreamOfObvMapViewModel(_ vc: ObvMapViewController) throws -> AsyncStream<ObvMapViewModel> {
        switch streamManagerKind {
        case .forGivenMessage(let streamManager):
            let (_, stream) = try streamManager.startStream()
            return stream
        case .forGivenOwnedCryptoId(let streamManager):
            let (_, stream) = try streamManager.startStream()
            return stream
        }
    }
    
    func fetchAvatar(_ vc: ObvLocation.ObvMapViewController, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNotSet }
        return try await delegate.fetchAvatar(self, photoURL: photoURL, avatarSize: avatarSize)
    }

}


@available(iOS 17.0, *)
extension ObvMapViewControllerAppDataSource {
    
    enum ObvError: Error {
        case delegateIsNotSet
    }
    
}

// MARK: - Internal manager when an owned crypto was specified

@available(iOS 17.0, *)
extension ObvMapViewControllerAppDataSource {
    
    private final class ObvMapViewModelStreamManagerForGivenOwnedCryptoIdentity: NSObject, NSFetchedResultsControllerDelegate {

        let streamUUID = UUID()
        let ownedCryptoId: ObvCryptoId
        private let frcForCurrentOwnedDevice: NSFetchedResultsController<PersistedObvOwnedDevice>
        private let frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice: NSFetchedResultsController<PersistedLocationContinuous>
        private var stream: AsyncStream<ObvLocation.ObvMapViewModel>?
        private var continuation: AsyncStream<ObvLocation.ObvMapViewModel>.Continuation?

        @MainActor
        init(ownedCryptoId: ObvCryptoId) {
            self.ownedCryptoId = ownedCryptoId
            self.frcForCurrentOwnedDevice = PersistedObvOwnedDevice.getFetchedResultsControllerForCurrentOwnedDevice(ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext)
            self.frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice = PersistedLocationContinuous.getFetchedResultsControllerForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice(ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext)
        }
        
        
        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvLocation.ObvMapViewModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice.delegate = self
            frcForCurrentOwnedDevice.delegate = self
            try frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice.performFetch()
            try frcForCurrentOwnedDevice.performFetch()
            let stream = AsyncStream(ObvLocation.ObvMapViewModel.self) { [weak self] (continuation: AsyncStream<ObvLocation.ObvMapViewModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    continuation.yield(model)
                } catch {
                    assertionFailure()
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }

        func finishStream() {
            continuation?.finish()
        }
     
        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                assertionFailure()
            }
        }

        private func createModel() throws -> ObvLocation.ObvMapViewModel {
            guard let persistedCurrentOwnedDevice = frcForCurrentOwnedDevice.fetchedObjects?.first else {
                assertionFailure()
                throw ObvError.couldNotFetchObjects
            }
            // Note that we don't need to filter out the location from the current owned device, as the frc is configured to exclude it from the fetched objects.
            guard let allContinousLocations = frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice.fetchedObjects else {
                assertionFailure()
                throw ObvError.couldNotFetchObjects
            }
            
            let currentOwnedDevice = try ObvMapViewModel.CurrentOwnedDevice(currentOwnedDevice: persistedCurrentOwnedDevice)
            let deviceLocations = try allContinousLocations.map { try ObvMapViewModel.DeviceLocation(continousLocation: $0) }
            
            let model = ObvLocation.ObvMapViewModel(
                currentOwnedDevice: currentOwnedDevice,
                deviceLocations: deviceLocations)
            
            return model
            
        }

        enum ObvError: Error {
            case messageNotFound
            case discussionNotFound
            case couldNotFetchObjects
            case ownedCryptoIdNotFound
        }

    }
    
}


// MARK: - Internal manager when a message was specified

@available(iOS 17.0, *)
extension ObvMapViewControllerAppDataSource {
    
    private final class ObvMapViewModelStreamManagerForGivenMessage: NSObject, NSFetchedResultsControllerDelegate {
        
        let streamUUID = UUID()
        private let frcForPersistedLocationContinuous: NSFetchedResultsController<PersistedLocationContinuous>
        private let frcForCurrentOwnedDevice: NSFetchedResultsController<PersistedObvOwnedDevice>
        private var stream: AsyncStream<ObvLocation.ObvMapViewModel>?
        private var continuation: AsyncStream<ObvLocation.ObvMapViewModel>.Continuation?

        @MainActor
        init(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) throws {
            guard let message = try PersistedMessage.get(with: messageObjectID, within: ObvStack.shared.viewContext) else {
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
            self.frcForPersistedLocationContinuous = try PersistedLocationContinuous.getFetchedResultsControllerForContinuousLocations(in: discussion)
            self.frcForCurrentOwnedDevice = PersistedObvOwnedDevice.getFetchedResultsControllerForCurrentOwnedDevice(ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext)
            super.init()
        }
        
        
        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvLocation.ObvMapViewModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            frcForPersistedLocationContinuous.delegate = self
            frcForCurrentOwnedDevice.delegate = self
            try frcForPersistedLocationContinuous.performFetch()
            try frcForCurrentOwnedDevice.performFetch()
            let stream = AsyncStream(ObvLocation.ObvMapViewModel.self) { [weak self] (continuation: AsyncStream<ObvLocation.ObvMapViewModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    continuation.yield(model)
                } catch {
                    assertionFailure()
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }

        func finishStream() {
            continuation?.finish()
        }


        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                assertionFailure()
            }
        }

        private func createModel() throws -> ObvLocation.ObvMapViewModel {
            guard let persistedCurrentOwnedDevice = frcForCurrentOwnedDevice.fetchedObjects?.first else {
                assertionFailure()
                throw ObvError.couldNotFetchObjects
            }
            // Note that we filter out the location from the current owned device, as the map knows how to locate the current device.
            guard let allContinousLocations = frcForPersistedLocationContinuous.fetchedObjects?.filter({ ($0 as? PersistedLocationContinuousSent)?.ownedDevice?.objectID != persistedCurrentOwnedDevice.objectID }) else {
                assertionFailure()
                throw ObvError.couldNotFetchObjects
            }
            
            let currentOwnedDevice = try ObvMapViewModel.CurrentOwnedDevice(currentOwnedDevice: persistedCurrentOwnedDevice)
            let deviceLocations = try allContinousLocations.map { try ObvMapViewModel.DeviceLocation(continousLocation: $0) }
            
            let model = ObvLocation.ObvMapViewModel(
                currentOwnedDevice: currentOwnedDevice,
                deviceLocations: deviceLocations)
            
            return model
            
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
