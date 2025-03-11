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

import SwiftUI
import ObvUICoreData
import Combine

@available(iOS 17.0, *)
public struct MapSharedLocationView: View {
    
    @ObservedObject private var viewModel: MapSharedLocationViewModel
    
    private var mapViewModel: (any MapViewModelProtocol)?
    
    
    private var cancellables = [AnyCancellable]()
    
    private let mapUserPickerView: MapUserPickerView
    private let pickerViewModel: MapUserPickerViewModel
    
    init(viewModel: MapSharedLocationViewModel) {
        self.viewModel = viewModel
        
        pickerViewModel = MapUserPickerViewModel(ownedIdentity: viewModel.ownedIdentity,
                                                 currentUserCanUseLocation: viewModel.currentUserCanUseLocation)
        
        self.mapUserPickerView = MapUserPickerView(viewModel: pickerViewModel)
        
        instanciate()
        
    }
    
    private mutating func instanciate() {
        let mapViewModel = MapViewModel(ownedIdentity: viewModel.ownedIdentity)
        
        mapViewModel.enableInteraction = true
        
        //MARK: User Array Binding
        self.viewModel
            .$usersToDisplay
            .assign(to: \.usersToDisplay, on: mapViewModel)
            .store(in: &cancellables)
        
        self.viewModel
            .$usersToDisplay
            .assign(to: \.userContents, on: pickerViewModel)
            .store(in: &cancellables)
        
        
        self.viewModel
            .$centeredUserContent
            .assign(to: \.centeredUserContent, on: pickerViewModel)
            .store(in: &cancellables)
        
        self.viewModel
            .$centeredUserContent
            .assign(to: \.centeredUserContent, on: mapViewModel)
            .store(in: &cancellables)

        self.viewModel
            .$centeredToCurrentUser
            .assign(to: \.centeredToCurrentUser, on: mapViewModel)
            .store(in: &cancellables)

        self.viewModel
            .$centeredToCurrentUser
            .assign(to: \.centeredToCurrentUser, on: pickerViewModel)
            .store(in: &cancellables)
        
        mapViewModel
            .$selectedUserContent
            .assign(to: \.centeredUserContent, on: self.viewModel)
            .store(in: &cancellables)
        
        mapViewModel
            .$mapCameraChanged
            .filter { $0 } // We only want map camera change du to user interaction
            .assign(to: \.mapCameraChanged, on: self.viewModel)
            .store(in: &cancellables)
        
        //MARK: Picker View Binding
        pickerViewModel
            .$selectedOwnedUserContent
            .assign(to: \.centeredToCurrentUser, on: mapViewModel)
            .store(in: &cancellables)
        
        pickerViewModel
            .$selectedUserContent
            .compactMap { $0 }
            .assign(to: \.centeredUserContent, on: self.viewModel)
            .store(in: &cancellables)
        
        pickerViewModel
            .$selectedUserContent
            .compactMap { $0 }
            .assign(to: \.centeredUserContent, on: mapViewModel)
            .store(in: &cancellables)
        
        mapViewModel
            .$centeredToCurrentUser
            .assign(to: \.centeredToCurrentUser, on: pickerViewModel)
            .store(in: &cancellables)
        
        //If camera moves, picker is cleared.
        mapViewModel
            .$mapCameraChanged
            .filter { $0 } // We only want map camera change du to user interaction
            .map { _ in nil } // We map to nil in order to clear user content for picker view
            .assign(to: \.centeredUserContent, on: pickerViewModel)
            .store(in: &cancellables)
        
        mapViewModel
            .$mapCameraChanged
            .filter { $0 } // We only want map camera change du to user interaction
            .map { _ in false } // We map to false in order to unselect current user
            .assign(to: \.selectedOwnedUserContent, on: pickerViewModel)
            .store(in: &cancellables)
                
        self.mapViewModel = mapViewModel
    }
    
    public var body: some View {
        ZStack {
            if let mapViewModel = self.mapViewModel as? MapViewModel {
                NativeMapView(viewModel: mapViewModel)
            }            
            VStack {
                HStack {
                    Spacer()
                    mapUserPickerView
                        .padding(.top, 16.0)
                        .padding(.trailing, 16.0)
                }
                Spacer()
            }
        }
    }
}
