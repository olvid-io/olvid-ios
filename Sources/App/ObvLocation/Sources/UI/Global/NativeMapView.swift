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
import CoreLocation
import MapKit
import ObvSettings
import ObvUI
import ObvUICoreData

@available(iOS 17.0, *)
struct NativeMapView: View {
    
    private let userAnnotationSize: CGFloat = 24.0
    
    @ObservedObject var viewModel: MapViewModel
    
    init(viewModel: MapViewModel) {
        self.viewModel = viewModel
    }
    
    private var initialOpacity: CGFloat = 0.6
    private var finalOpacity: CGFloat = 0.3
    private var initialScaleEffect: CGFloat = 1.0
    private var finalScaleEffect: CGFloat = 1.5
    
    private var animatedOpacity: CGFloat {
        viewModel.isAnimated ? finalOpacity : initialOpacity
    }

    private var animatedScaleEffect: CGFloat {
        viewModel.isAnimated ? finalScaleEffect : initialScaleEffect
    }
    
    private var circleAnimation: Animation {
        viewModel.isAnimated ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .easeInOut(duration: 1.0)
    }
    
    // Method to generate current user Annotation to add to the map
    private func userPositionContent(at userPosition: CLLocationCoordinate2D) -> Annotation<Text, some View> {
        Annotation("", coordinate: userPosition) {
            ZStack {
                Circle()
                    .frame(width: userAnnotationSize + 4.0, height: userAnnotationSize + 4.0)
                    .foregroundColor(Color.blue)
                    .opacity(animatedOpacity)
                    .scaleEffect(animatedScaleEffect)
                    .animation(circleAnimation, value: viewModel.isAnimated)
                    .onAppear { // Small hack in order to animate properly the circle when it appears and not before
                        viewModel.hasAppeared = true
                    }
                ZStack {
                    Circle()
                        .foregroundColor(.white)
                        .frame(width: userAnnotationSize + 4.0, height: userAnnotationSize + 4.0)
                    
                    CircledInitialsView(configuration: viewModel.ownedIdentity.circledInitialsConfiguration,
                                        size: .custom(sizeLength: userAnnotationSize),
                                        style: ObvMessengerSettings.Interface.identityColorStyle)
                }
                .shadow(radius: 3.0, x: 0.0, y: 2.0)
            }
        }
    }
    
    // Method to generate an Annotation to add to the map for another user.
    private func userPositionContent(for userContent: MapUserPositionContentViewModel) -> Annotation<Text, some View> {
        Annotation("", coordinate: CLLocationCoordinate2D(latitude: userContent.location.coordinate.latitude, longitude: userContent.location.coordinate.longitude)) {
            ZStack {
                Circle()
                    .foregroundColor(.white)
                    .frame(width: userAnnotationSize + 4.0, height: userAnnotationSize + 4.0)
                
                CircledInitialsView(configuration: userContent.userInitialConfiguraton,
                                    size: .custom(sizeLength: userAnnotationSize),
                                    style: ObvMessengerSettings.Interface.identityColorStyle)
            }
            .shadow(radius: 3.0, x: 0.0, y: 2.0)
            .tag(userContent.contactCryptoId)
        }
    }
    
    private var mapView: some View {
        Map(position: $viewModel.position,
            interactionModes: viewModel.interactionModes,
            selection: $viewModel.selectedContactCryptoId) {
            
            // Current user position
            if let userPosition = viewModel.userPosition {
                userPositionContent(at: userPosition)
                    .tag(viewModel.ownedIdentity.cryptoId)
            }
            
            // Display the other users
            ForEach(viewModel.usersToDisplay, id: \.contactCryptoId) { userPositionContent(for: $0) }
        }
        .mapControlVisibility(.hidden)
        .simultaneousGesture(DragGesture()
            .onChanged { drag in
                viewModel.dragState = .dragging
            }
            .onEnded { drag in
                viewModel.dragState = .dragEnded
            }
        )
        .onMapCameraChange(frequency: .continuous, {
            viewModel.mapCameraIsMoving = true
        })
        .onMapCameraChange(frequency: .onEnd) { cameraContext in // We store the current location of the map
            let centerLocation = CLLocation(latitude: cameraContext.camera.centerCoordinate.latitude, longitude: cameraContext.camera.centerCoordinate.longitude)
            viewModel.mapCameraIsMoving = false
            viewModel.mapCameraChanged = viewModel.dragState != .notDragging
            viewModel.currentLocation = centerLocation
            viewModel.dragState = .notDragging
        }
        .task {
            await viewModel.onTask()
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: viewModel.selectedContactCryptoId) { _, cryptoId in
            if let cryptoId {
                var selectedUserContent: MapUserPositionContentViewModel?
                
                viewModel.usersToDisplay.forEach { userContent in
                    if userContent.contactCryptoId == cryptoId {
                        selectedUserContent = userContent
                    }
                }
                
                if let selectedUserContent { // we center on the user
                    viewModel.centeredToCurrentUser = false
                    viewModel.selectedUserContent = selectedUserContent
                } else { // we center on the current user
                    viewModel.centeredToCurrentUser = true
                    viewModel.selectedUserContent = nil
                }
            }
            viewModel.selectedContactCryptoId = nil
        }
    }

    var body: some View {
        ZStack {
            mapView
                .animation(.easeInOut, value: UUID())
        }
    }
}

