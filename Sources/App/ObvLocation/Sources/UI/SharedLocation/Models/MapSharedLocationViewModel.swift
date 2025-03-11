/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvUICoreData
import SwiftUI
import Combine
import CoreLocation

final class MapSharedLocationViewModel: ObservableObject {

    private(set) var ownedIdentity: PersistedObvOwnedIdentity
    let currentUserCanUseLocation: Bool

    // Publisher used to update location messages directly from Messenger App.
    @MainActor
    private(set) var locationsPublisher: AnyPublisher<[PersistedLocationContinuous], Never>
    
    @Published var usersToDisplay: [MapUserPositionContentViewModel] = []
    
    @Published var centeredUserContent: MapUserPositionContentViewModel? = nil
    
    @Published var centeredToCurrentUser: Bool = false
    
    @Published var mapCameraChanged: Bool = false
    
    var centeredMessageId: TypeSafeManagedObjectID<PersistedMessage>?
    
    private var cancellables = [AnyCancellable]()

    @MainActor
    init(ownedIdentity: PersistedObvOwnedIdentity,
         currentUserCanUseLocation: Bool,
         locationsPublisher: AnyPublisher<[PersistedLocationContinuous], Never>,
         centeredMessageId: TypeSafeManagedObjectID<PersistedMessage>?) {
        
        self.ownedIdentity = ownedIdentity
        self.currentUserCanUseLocation = currentUserCanUseLocation
        self.locationsPublisher = locationsPublisher
        self.centeredMessageId = centeredMessageId
        
        observeLocationMessagesChanges()
    }
    
    deinit {
        cancellables.forEach({ $0.cancel() })
    }
    
    @MainActor
    private func updateUserContents(from locations: [PersistedLocationContinuous]) {
        
        var possibleCenteredUserContent: MapUserPositionContentViewModel? = nil
        guard let currentDevice = ownedIdentity.currentDevice else { assertionFailure(); return }
        
        self.usersToDisplay = locations.compactMap({ location in
            if let locationReceived = location as? PersistedLocationContinuousReceived {
                guard let message = locationReceived.receivedMessages.first else { return nil } // We just get the first message in order to retrieve the location sender crypto id (should be the same for each messages received)
                let userContent = MapUserPositionContentViewModel(contactCryptoId: message.contactIdentity?.cryptoId,
                                                                  userInitialConfiguraton: message.contactIdentity?.circledInitialsConfiguration,
                                                                  location: CLLocation(latitude: locationReceived.latitude,
                                                                                       longitude: locationReceived.longitude))
                
                // we update the centeredUserContent with the new location
                if let centeredUserContent, centeredUserContent.contactCryptoId == message.contactIdentity?.cryptoId {
                    self.centeredUserContent = userContent
                }
                if locationReceived.receivedMessages.contains(where: { $0.typedObjectID.downcast == self.centeredMessageId }) { // If the current location's messages contains the centered message id, we center the map to this user content
                    possibleCenteredUserContent = userContent
                }
                return userContent
            } else if let locationSent = location as? PersistedLocationContinuousSent, locationSent.ownedDevice != currentDevice { // Location Sent from different Device
                let userContent = MapUserPositionContentViewModel(contactCryptoId: ownedIdentity.cryptoId,
                                                                  userInitialConfiguraton: ownedIdentity.circledInitialsConfiguration,
                                                                  location: CLLocation(latitude: locationSent.latitude,
                                                                                       longitude: locationSent.longitude))
                
                // we update the centeredUserContent with the new location
                if let centeredUserContent, centeredUserContent.contactCryptoId == ownedIdentity.cryptoId {
                    self.centeredUserContent = userContent
                }
                if locationSent.sentMessages.contains(where: { $0.typedObjectID.downcast == self.centeredMessageId }) { // If the current location's messages contains the centered message id, we center the map to this user content
                    possibleCenteredUserContent = userContent
                }
                return userContent
            }
            
            return nil
        })
        
        if let possibleCenteredUserContent {
            self.centeredUserContent = possibleCenteredUserContent
        }
            
    }
    
    @MainActor
    private func observeLocationMessagesChanges() {
        
        // Update locations
        self.locationsPublisher
            .sink { [weak self] locations in
                guard let self else { return }
                self.updateUserContents(from: locations)
            }.store(in: &cancellables)
        
        // Used to check if we want to center to the current user.
        self.locationsPublisher
            .first()
            .map { locations in
                return locations
                    .compactMap { $0 as? PersistedLocationContinuousSent } // Only location continuous sent.
                    .first { $0.sentMessages.map(\.typedObjectID).contains { $0.downcast == self.centeredMessageId }} // get first location which contains the center message tapped.
            }
            .sink { [weak self] location in
                guard let self else { return }
                guard location != nil else { return } // If location is != nil, it means we want to center to the current user.
                self.centeredToCurrentUser = true
            }.store(in: &cancellables)
        
        self.$mapCameraChanged
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                self.centeredToCurrentUser = false
                self.centeredMessageId = nil
                self.centeredUserContent = nil
            }.store(in: &cancellables)
    }
}
