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
import ObvDesignSystem
import ObvUICoreData
import Combine
import ObvSystemIcon
import ObvAppTypes
import ObvAppCoreConstants

@available(iOS 17.0, *)
public struct MapSharingView: View {
    
    @ObservedObject private var viewModel: MapSharingViewModel
    
    let actions: MapSharingViewActionsProtocol
    
    private var mapViewModel: (any MapViewModelProtocol)?
    
    private var cancellables = [AnyCancellable]()
    
    init(viewModel: MapSharingViewModel, actions: MapSharingViewActionsProtocol) {
        self.viewModel = viewModel
        self.actions = actions
        instanciate()
    }
    
    private mutating func instanciate() {
        let mapViewModel = MapViewModel(ownedIdentity: viewModel.ownedIdentity)
        
        self.viewModel
            .$shouldFollowUser
            .sink(receiveValue: { shouldFollowUser in
                    mapViewModel.enableInteraction = !shouldFollowUser
                    mapViewModel.centeredToCurrentUser = shouldFollowUser
            })
            .store(in: &cancellables)
        
        self.mapViewModel = mapViewModel
    }
    
    private var sharingTypeButton: some View {
        Button(action: viewModel.userWantsToSwitchType) {
            viewModel.sharingType.icon
                .padding(.all, 10.0)
                .frame(width: 40.0, height: 40.0)
                .foregroundColor(.white)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .clipShape(Circle())
        }
    }
    
    private var closeButton: some View {
        Button(action: actions.userWantsToDismissMapView) {
            Text("CLOSE")
        }
        .buttonStyle(.borderedProminent)
    }
    
    private var sharingButton: some View {
        Button(action: userWantsToSharePlace) {
            viewModel.sharingType.text
                .font(.system(size: 12.0, weight: .semibold, design: .default))
                .padding(.horizontal, 35.0)
                .frame(height: 40.0)
                .foregroundColor(Color.white)
                .background(viewModel.sharingType.background)
                .environment(\.colorScheme, .dark)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
    
    private var continuousSharingButtonWithoutExpiration: some View {
        Button(action: { actions.userWantsToShareLocationContinuously(expirationMode: SharingLocationExpirationMode.infinity, discussionIdentifier: viewModel.discussionIdentifier) }) {
            viewModel.sharingType.text
                .font(.system(size: 12.0, weight: .semibold, design: .default))
                .padding(.horizontal, 35.0)
                .frame(height: 40.0)
                .foregroundColor(Color.white)
                .background(viewModel.sharingType.background)
                .environment(\.colorScheme, .dark)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
    
    private var continuousSharingButton: some View {
        Menu {
            Section(header: Text("SHARE_MY_LOCATION").textCase(.uppercase)) {
                
                ForEach(SharingLocationExpirationMode.allCases, id: \.rawValue) { expirationMode in
                    Button(action: { actions.userWantsToShareLocationContinuously(expirationMode: expirationMode, discussionIdentifier: viewModel.discussionIdentifier) }) {
                        HStack {
                            expirationMode.text
                            expirationMode.image
                        }
                    }
                }
            }
        } label: {
            viewModel.sharingType.text
                .font(.system(size: 12.0, weight: .semibold, design: .default))
                .padding(.horizontal, 35.0)
                .frame(height: 40.0)
                .foregroundColor(Color.white)
                .background(viewModel.sharingType.background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
    
    public var body: some View {
        ZStack {
            if let mapViewModel = self.mapViewModel as? MapViewModel {
                NativeMapView(viewModel: mapViewModel)
            }
            if viewModel.sharingType == .landmark { // User wants to share a particular location, we display a marker
                MapLandmarkView()
                    .alignmentGuide(VerticalAlignment.center) { viewDimensions in
                        let centerOffset = viewDimensions.height - 5.0
                        return centerOffset
                    }
                    .disabled(true)
            }
            
            VStack {
                HStack {
                    if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
                        closeButton
                            .padding(.top, 16.0)
                            .padding(.leading, 16.0)
                    }
                    sharingTypeButton
                        .padding(.top, 16.0)
                        .padding(.leading, 16.0)
                    Spacer()
                }
                Spacer()
                if viewModel.sharingType == .landmark {
                    sharingButton
                        .padding(.bottom, 30.0)
                } else {
                    if !ContinuousSharingLocationService.shared.isSharing {
                        continuousSharingButton
                            .padding(.bottom, 30.0)
                    } else {
                        continuousSharingButtonWithoutExpiration
                            .padding(.bottom, 30.0)
                    }
                }
            }
        }
    }
}

@available(iOS 17.0, *)
extension MapSharingView {
    
    private func userWantsToSharePlace() {
        guard viewModel.sharingType == .landmark, let currentLocation = mapViewModel?.currentLocation else { return }
        Task {
            let address = try? await ObvLocationService.reverseGeocoding(from: currentLocation)
            let locationData = ObvLocationData(clLocation: currentLocation).withAddress(address)
            self.actions.userWantsToSendLocation(locationData, discussionIdentifier: viewModel.discussionIdentifier)
        }
    }
    
}
