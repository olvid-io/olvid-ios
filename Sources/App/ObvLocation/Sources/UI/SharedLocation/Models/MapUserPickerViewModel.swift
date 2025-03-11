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
import Combine
import ObvTypes
import CoreLocation

final class MapUserPickerViewModel: ObservableObject {
    
    private(set) var ownedIdentity: PersistedObvOwnedIdentity
    
    // Used for mapping to the view from outside
    @Published var centeredUserContent: MapUserPositionContentViewModel?
    @Published var centeredToCurrentUser: Bool = false
    @Published var userContents: [MapUserPositionContentViewModel] = []
    
    // Used to publish interactions to map
    @Published var selectedUserContent: MapUserPositionContentViewModel?
    @Published var selectedOwnedUserContent: Bool = false
    
    
    @Published var pickerIsOpened: Bool = false
    
    private var cancellables: Set<AnyCancellable> = []
    
    private lazy var ownedUserContent = MapUserPositionContentViewModel(contactCryptoId: ownedIdentity.cryptoId,
                                                                        userInitialConfiguraton: ownedIdentity.circledInitialsConfiguration,
                                                                        location: CLLocation(latitude: 0, longitude: 0)) // Location not used here.
    
    private let currentUserCanUseLocation: Bool
    
    
    var displayableUserContents: [MapUserPositionContentViewModel] {
        guard let ownedUserContent, currentUserCanUseLocation else {
            return userContents
        }
        return [ownedUserContent] + userContents
    }
    
    
    init(ownedIdentity: PersistedObvOwnedIdentity, currentUserCanUseLocation: Bool) {
        self.ownedIdentity = ownedIdentity
        self.currentUserCanUseLocation = currentUserCanUseLocation
        self.bind()
    }
    
    private func bind() {
        
        // We check that user centered still exist.
        $userContents
            .sink { [weak self] _ in
                guard let self else { return }
                if self.displayableUserContents.contains(where: { $0.contactCryptoId == self.centeredUserContent?.contactCryptoId }) == false {
                    centeredUserContent = nil
                }
            }.store(in: &cancellables)
        
        $centeredToCurrentUser
            .sink { [weak self] centeredToCurrentUser in
                if centeredToCurrentUser, let ownedUserContent = self?.ownedUserContent {
                    self?.centeredUserContent = ownedUserContent
                }
            }.store(in: &cancellables)
    }
    
    func togglePicker() {
        if displayableUserContents.count > 1 {
            pickerIsOpened.toggle()
        } else {
            if pickerIsOpened {
                pickerIsOpened = false // Close picker if it was opened and userContents has been updated with an empty array of users.
            }
            
            if let firstUserContent = displayableUserContents.first {
                userContentHasBeenSelected(userContent: firstUserContent, shouldTogglerPickerAutomatically: false)
            }
        }
    }
    
    func userContentHasBeenSelected(userContent: MapUserPositionContentViewModel, shouldTogglerPickerAutomatically: Bool = true) {
        centeredUserContent = userContent
        if userContent.contactCryptoId == self.ownedIdentity.cryptoId {
            selectedUserContent = nil
            selectedOwnedUserContent = true
        } else {
            selectedOwnedUserContent = false
            selectedUserContent = userContent
        }
        if shouldTogglerPickerAutomatically {
            togglePicker()
        }
    }
}
