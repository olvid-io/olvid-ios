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

import SwiftUI
import MapKit
import OSLog
import ObvTypes
import ObvAppTypes
import ObvSystemIcon
import ObvDesignSystem
import ObvAppCoreConstants


public struct ObvMapViewModel: Sendable, Hashable, Equatable {
    
    let currentOwnedDevice: CurrentOwnedDevice
    let deviceLocations: [DeviceLocation]
    
    public init(currentOwnedDevice: CurrentOwnedDevice, deviceLocations: [DeviceLocation]) {
        self.currentOwnedDevice = currentOwnedDevice
        self.deviceLocations = deviceLocations
    }
    
    public struct DeviceLocation: Sendable, Hashable, Equatable, Identifiable {
        let deviceIdentifier: ObvDeviceIdentifier
        let coordinate: ObvLocationCoordinate2D
        let avatarViewModel: ObvAvatarViewModel
        public var id: ObvDeviceIdentifier { deviceIdentifier }
        public init(deviceIdentifier: ObvDeviceIdentifier, coordinate: ObvLocationCoordinate2D, avatarViewModel: ObvAvatarViewModel) {
            self.deviceIdentifier = deviceIdentifier
            self.coordinate = coordinate
            self.avatarViewModel = avatarViewModel
        }
    }
    
    public struct CurrentOwnedDevice: Sendable, Hashable, Equatable {
        let deviceIdentifier: ObvDeviceIdentifier
        let avatarViewModel: ObvAvatarViewModel
        public init(deviceIdentifier: ObvDeviceIdentifier, avatarViewModel: ObvAvatarViewModel) {
            self.deviceIdentifier = deviceIdentifier
            self.avatarViewModel = avatarViewModel
        }
    }
    

}

enum ObvMapViewDataSourceKind {
    case currentOwnedDevice
    case all(ownedCryptoId: ObvCryptoId)
    case discussion(discussionIdentifier: ObvDiscussionIdentifier)
}

@MainActor
protocol ObvMapViewDataSource: DeviceLocationViewDataSource {
    func getAsyncStreamOfObvMapViewModel() throws -> AsyncStream<ObvMapViewModel>
}

@MainActor
protocol ObvMapViewActionsProtocol: AnyObject {
    func userWantsToDismissObvMapView()
}

/// This view displays a map allowing to consult the locations shared with the current device.
/// It is up to the `ObvMapViewDataSource` to decide which locations are actually shown on the map.
/// For example, depending on the data source, we can restrict to showing locations shared by the participants of a discussion,
/// or to restrict to all the contacts of the current owned identity.
@available(iOS 17.0, *)
public struct ObvMapView: View {
    
    /// When set, we immediately set the `selectedDeviceLocation` when receiving the first version of the model by our data source.
    /// This is typically used when tapping a received message containing a received continuous location, to immediately focus on the message's sender.
    let initialDeviceIdentifierToSelect: ObvDeviceIdentifier?
    let dataSource: any ObvMapViewDataSource
    let actions: any ObvMapViewActionsProtocol
    
    init(dataSource: any ObvMapViewDataSource, actions: any ObvMapViewActionsProtocol, initialDeviceIdentifierToSelect: ObvDeviceIdentifier? = nil) {
        self.initialDeviceIdentifierToSelect = initialDeviceIdentifierToSelect
        self.dataSource = dataSource
        self.actions = actions
    }

    @State private var model: ObvMapViewModel?
    @State private var selectedDeviceLocation: ObvMapViewModel.DeviceLocation?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentOwnedDeviceLocation: ObvMapViewModel.DeviceLocation?
    @State private var modelSetAtLeastOnce: Bool = false
    
    private let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ObvMapView")
    
    private func onTask() async {
        do {
            let stream = try dataSource.getAsyncStreamOfObvMapViewModel()
            for await receivedModel in stream {
                
                let settingModelForFirstTime: Bool = (self.model == nil)
                
                self.model = receivedModel
                
                if settingModelForFirstTime {
                    automaticallySelectOwnedDeviceLocationIfAppropriate()
                }

                setSelectedDeviceLocationUsingInitialDeviceIdentifierToSelectIfAppropriate(model: receivedModel)
                
                // If the selectedDeviceLocation is no longer part of the model, set it to nil
                let selectedDeviceLocationIsPartOfOtherDeviceLocation = receivedModel.deviceLocations.contains(where: { $0.deviceIdentifier == selectedDeviceLocation?.deviceIdentifier })
                let selectedDeviceLocationIsOurCurrentOwnedDevice = (receivedModel.currentOwnedDevice.deviceIdentifier == selectedDeviceLocation?.deviceIdentifier)
                if !selectedDeviceLocationIsPartOfOtherDeviceLocation && !selectedDeviceLocationIsOurCurrentOwnedDevice {
                    selectedDeviceLocation = nil
                    if !cameraPosition.positionedByUser {
                        cameraPosition = .automatic
                    }
                }
            }
        } catch {
            assertionFailure()
        }
    }
    
    
    /// This method makes sure we select the current device location in case there are no other locations to show.
    /// This is required as the `.automatic` camera mode is to narrow when showing the current physical device location.
    /// This method is called on exactly two occasions:
    /// - When setting the model for the first time.
    /// - When setting the current owned device location for the first time.
    private func automaticallySelectOwnedDeviceLocationIfAppropriate() {
        guard let model else { return }
        guard model.deviceLocations.isEmpty else { return }
        guard let currentOwnedDeviceLocation else { return }
        self.selectedDeviceLocation = currentOwnedDeviceLocation
    }
    

    /// This method is called early in the appearance of the view and allows for immediately selecting the geolocation associated with the device passed as a parameter during view initialization.
    /// This is typically useful when displaying a map after the user taps on a received message cell containing the sender's geolocation.
    /// The method quickly selects the shared position from the message to facilitate navigation on the map and allow the user to see where the message sender is located.
    private func setSelectedDeviceLocationUsingInitialDeviceIdentifierToSelectIfAppropriate(model: ObvMapViewModel) {

        guard !modelSetAtLeastOnce else { return }
        defer { modelSetAtLeastOnce = true }

        guard let initialDeviceIdentifierToSelect else { return }
        
        if let deviceLocationToSelectInitially = model.deviceLocations.first(where: { $0.deviceIdentifier == initialDeviceIdentifierToSelect }) {
            selectedDeviceLocation = deviceLocationToSelectInitially
            cameraPosition = .camera(.init(centerCoordinate: deviceLocationToSelectInitially.coordinate.clCoordinate, distance: 1_000))
        }

    }
    
    
    /// On the view's task, we start monitoring the current owned device location, and update the `currentOwnedDeviceLocation` on each update.
    /// If the user decided to track her current owned device, we update `selectedDeviceLocation` using the received location.
    private func onTaskForMonitoringCurrentOwnedDeviceLocation() async {
        let currentOwnedDeviceLocationUpdates = CLLocationUpdate.liveUpdates()
        do {
            for try await newCurrentOwnedDeviceLocation in currentOwnedDeviceLocationUpdates {
                guard let model else { continue }
                guard let location = newCurrentOwnedDeviceLocation.location else {
                    // This happens, e.g., if the user did not authorize access to her location
                    logger.error("The received CLLocationUpdate did not contain a location. Continuing...")
                    continue
                }
                let currentOwnedDeviceLocation = ObvMapViewModel.DeviceLocation(deviceIdentifier: model.currentOwnedDevice.deviceIdentifier,
                                                                                coordinate: ObvLocationCoordinate2D(location: location.coordinate),
                                                                                avatarViewModel: model.currentOwnedDevice.avatarViewModel)
                
                let settingCurrentOwnedDeviceLocationForTheFirstTime = (self.currentOwnedDeviceLocation == nil)
                
                withAnimation {
                    self.currentOwnedDeviceLocation = currentOwnedDeviceLocation
                    if self.selectedDeviceLocation?.deviceIdentifier == model.currentOwnedDevice.deviceIdentifier {
                        self.selectedDeviceLocation = currentOwnedDeviceLocation
                    }
                }
                
                if settingCurrentOwnedDeviceLocationForTheFirstTime {
                    self.automaticallySelectOwnedDeviceLocationIfAppropriate()
                }
                
            }
        } catch {
            logger.fault("Failed to loop over live location updates: \(error)")
            assertionFailure()
        }
    }

    
    public var body: some View {
        ZStack {
            InternalView(model: $model, selectedDeviceLocation: $selectedDeviceLocation, cameraPosition: $cameraPosition, currentOwnedDeviceLocation: currentOwnedDeviceLocation, dataSource: dataSource)
                .task { await onTask() }
                .task { await onTaskForMonitoringCurrentOwnedDeviceLocation() }
            VStack {
                Spacer()
                Button(action: actions.userWantsToDismissObvMapView) {
                    Text("CLOSE")
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
            }
        }
    }


    private struct InternalView: View {
        
        @Binding var model: ObvMapViewModel?
        @Binding var selectedDeviceLocation: ObvMapViewModel.DeviceLocation?
        @Binding var cameraPosition: MapCameraPosition
        let currentOwnedDeviceLocation: ObvMapViewModel.DeviceLocation?
        let dataSource: any ObvMapViewDataSource

        private let userAnnotationSize: CGFloat = 24.0

        private func onChangeOfSelectedDeviceLocation(selectedDeviceLocation: ObvMapViewModel.DeviceLocation?) {
            print("onChangeOfSelectedDeviceLocation")
            if let selectedDeviceLocation {
                cameraPosition = .camera(.init(centerCoordinate: selectedDeviceLocation.coordinate.clCoordinate, distance: 1_000))
            }
        }
        
        
        /// If the user tracks (selected) a specific device, its location needs to be updated with the new coordinates found in the model, each time it changes.
        /// This is true for all devices, except the current owned device, which location is tracked within this view, not thanks to coordinates found in database.
        private func onChangeOfModel(newModel: ObvMapViewModel) {
            if let selectedDeviceLocation {
                if selectedDeviceLocation.deviceIdentifier == model?.currentOwnedDevice.deviceIdentifier {
                    // Do nothing in this case, as the current owned device exact location is managed within this view, not by the coordinates received from the database
                } else {
                    // Update the location with the new location's coordinates received from database
                    self.selectedDeviceLocation = newModel.deviceLocations.first(where: { $0.deviceIdentifier == selectedDeviceLocation.deviceIdentifier })
                }
            }
        }

        var body: some View {
            if let model {
                ZStack {
                    
                    Map(position: $cameraPosition,
                        selection: $selectedDeviceLocation)
                    {
                        
                        // This annotation allows to automatically show the current owned device current location on the map.
                        // It displays the standard system blue dot.
                        UserAnnotation()
                        
                        // The following transparent annotation is position exactly at the same position than the
                        // UserAnnotation above. We add it in order for the .automatic camera placement to take into
                        // account our owned device position when sizing the camera.
                        if let currentOwnedDeviceLocation {
                            Annotation("", coordinate: currentOwnedDeviceLocation.coordinate.clCoordinate) {
                                Circle().opacity(0)
                            }
                            .tag(currentOwnedDeviceLocation)
                        }
                        
                        // The following annotations represent all other devices positions
                        ForEach(model.deviceLocations) { deviceLocation in
                            Annotation("", coordinate: deviceLocation.coordinate.clCoordinate) {
                                DeviceLocationView(deviceLocation: deviceLocation, dataSource: dataSource)
                            }
                            .tag(deviceLocation)
                        }
                        
                    }
                    .animation(.easeInOut, value: cameraPosition)
                    .animation(.easeInOut, value: model)
                    
                    VStack {
                        HStack {
                            Spacer()
                            ObvMapPickerView(model: $model,
                                             cameraPosition: $cameraPosition,
                                             selectedDeviceLocation: $selectedDeviceLocation,
                                             currentOwnedDeviceLocation: currentOwnedDeviceLocation,
                                             dataSource: dataSource)
                            .padding(.top, 16.0)
                            .padding(.trailing, 16.0)
                        }
                        Spacer()
                    }
                    
                }
                .onChange(of: selectedDeviceLocation) { _, newValue in
                    onChangeOfSelectedDeviceLocation(selectedDeviceLocation: newValue)
                }
                .onChange(of: model) { oldValue, newValue in
                    onChangeOfModel(newModel: newValue)
                }
                .onChange(of: cameraPosition.positionedByUser, { oldValue, newValue in
                    if newValue {
                        self.selectedDeviceLocation = nil
                    }
                })
            } else {
                ProgressView()
            }
        }
    }
    
}


@available(iOS 17.0, *)
struct ObvMapPickerView: View {
    
    @Binding var model: ObvMapViewModel?
    @Binding var cameraPosition: MapCameraPosition
    @Binding var selectedDeviceLocation: ObvMapViewModel.DeviceLocation?
    let currentOwnedDeviceLocation: ObvMapViewModel.DeviceLocation?
    let dataSource: DeviceLocationViewDataSource

    @State private var pickerIsOpened: Bool = false
    
    private let userAnnotationSize: CGFloat = 22
    
    @ViewBuilder private var labelForMainButton: some View {
        if let selectedDeviceLocation {
            if let currentOwnedDeviceIdentifier = model?.currentOwnedDevice.deviceIdentifier, selectedDeviceLocation.deviceIdentifier == currentOwnedDeviceIdentifier {
                // The user decided to follow her current owned device location
                SystemIconInCircleView(systemIcon: .locationCircle, userAnnotationSize: userAnnotationSize)
            } else {
                // The user decided to follow a contact device location
                DeviceLocationView(deviceLocation: selectedDeviceLocation, dataSource: dataSource, userAnnotationSize: userAnnotationSize, withShadow: false)
            }
        } else {
            if cameraPosition == .automatic {
                // The user decided to track all devices' locations
                SystemIconInCircleView(systemIcon: .globeEuropeAfricaFill, userAnnotationSize: userAnnotationSize)
            } else {
                // The user is positioning the map manually
                SystemIconInCircleView(systemIcon: .locationCircle, userAnnotationSize: userAnnotationSize)
            }
        }
    }
    
    private var mainButtonColor: Color {
        cameraPosition.positionedByUser ? .gray : .blue
    }
    
    
    /// This internal view represents the content of the picker, shown when it is opened.
    /// To include it, we use `ViewThatFits` to include this view in a scroll view when the content is large (due to
    /// a large number of participants to the map), or to include it "as is" when the number of participants is sufficiently
    /// small to fit on screen without scrolling.
    private struct ObvMapPickerViewOpenedContent: View {
        
        @Binding var model: ObvMapViewModel?
        @Binding var cameraPosition: MapCameraPosition
        @Binding var selectedDeviceLocation: ObvMapViewModel.DeviceLocation?
        @Binding var pickerIsOpened: Bool
        let currentOwnedDeviceLocation: ObvMapViewModel.DeviceLocation?
        let dataSource: DeviceLocationViewDataSource
        let userAnnotationSize: CGFloat

        private func globeButtonTapped() {
            withAnimation {
                selectedDeviceLocation = nil
                cameraPosition = .automatic
                pickerIsOpened = false
            }
        }

        private func deviceLocationTapped(deviceLocation: ObvMapViewModel.DeviceLocation) {
            withAnimation {
                self.selectedDeviceLocation = deviceLocation
                // cameraPosition will change automatically
                pickerIsOpened = false
            }
        }
        

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                
                if cameraPosition != .automatic {
                    
                    Button(action: globeButtonTapped) {
                        SystemIconInCircleView(systemIcon: .globeEuropeAfricaFill, userAnnotationSize: userAnnotationSize)
                    }
                    
                }
                
                if let currentOwnedDeviceLocation, selectedDeviceLocation?.deviceIdentifier != currentOwnedDeviceLocation.deviceIdentifier {
                    Button(action: { deviceLocationTapped(deviceLocation: currentOwnedDeviceLocation) }) {
                        SystemIconInCircleView(systemIcon: .locationCircle, userAnnotationSize: userAnnotationSize)
                    }
                }
                
                if let model {
                    ForEach(model.deviceLocations) { deviceLocation in
                        if selectedDeviceLocation != deviceLocation {
                            Button(action: { deviceLocationTapped(deviceLocation: deviceLocation) }) {
                                DeviceLocationView(deviceLocation: deviceLocation, dataSource: dataSource, userAnnotationSize: userAnnotationSize, withShadow: false)
                            }
                        }
                    }
                }
                
            }
            .padding(.trailing, 16)
        }
    }
    
    
    var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation { pickerIsOpened.toggle() }
                } label: {
                    HStack {
                        labelForMainButton
                            .tint(mainButtonColor)
                        
                        Image(systemIcon: .chevronRight)
                            .imageScale(.small)
                            .rotationEffect(.degrees(pickerIsOpened ? 90 : 0))
                            .animation(.spring(), value: pickerIsOpened)
                        
                    }
                }
                if pickerIsOpened {
                    ViewThatFits {
                        
                        ObvMapPickerViewOpenedContent(model: $model,
                                                      cameraPosition: $cameraPosition,
                                                      selectedDeviceLocation: $selectedDeviceLocation,
                                                      pickerIsOpened: $pickerIsOpened,
                                                      currentOwnedDeviceLocation: currentOwnedDeviceLocation,
                                                      dataSource: dataSource,
                                                      userAnnotationSize: userAnnotationSize)

                        ScrollView(.vertical) {
                            ObvMapPickerViewOpenedContent(model: $model,
                                                          cameraPosition: $cameraPosition,
                                                          selectedDeviceLocation: $selectedDeviceLocation,
                                                          pickerIsOpened: $pickerIsOpened,
                                                          currentOwnedDeviceLocation: currentOwnedDeviceLocation,
                                                          dataSource: dataSource,
                                                          userAnnotationSize: userAnnotationSize)
                        }
                        
                    }
                }
            }
            .padding(8.0)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 8.0, style: .continuous))
            .transition(.moveAndScale)

    }
    
}


private extension AnyTransition {
    static var moveAndScale: AnyTransition {
        AnyTransition.move(edge: .top)
            .combined(with: .scale)
            .combined(with: opacity)
    }
}


// MARK: - Subview DeviceLocationView

protocol DeviceLocationViewDataSource: ObvAvatarViewDataSource {}

private struct DeviceLocationView: View {
    
    let deviceLocation: ObvMapViewModel.DeviceLocation
    let userAnnotationSize: CGFloat
    let withShadow: Bool
    let dataSource: DeviceLocationViewDataSource
    
    init(deviceLocation: ObvMapViewModel.DeviceLocation, dataSource: DeviceLocationViewDataSource, userAnnotationSize: CGFloat = 24.0, withShadow: Bool = true) {
        self.deviceLocation = deviceLocation
        self.userAnnotationSize = userAnnotationSize
        self.withShadow = withShadow
        self.dataSource = dataSource
    }

    var body: some View {
        ObvAvatarView(model: deviceLocation.avatarViewModel,
                      style: .map,
                      size: .custom(frameSize: CGSize(width: userAnnotationSize + 4.0, height: userAnnotationSize + 4.0)),
                      dataSource: dataSource)
        .shadow(radius: withShadow ? 3.0 : 0.0, x: 0.0, y: withShadow ? 2.0 : 0.0)
    }
    
}


// MARK: - SubView

private struct SystemIconInCircleView: View {
    
    let systemIcon: SystemIcon
    let userAnnotationSize: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .foregroundColor(.white)
                .frame(width: userAnnotationSize + 4.0, height: userAnnotationSize + 4.0)
            Image(systemIcon: systemIcon)
                .resizable()
                .frame(width: userAnnotationSize, height: userAnnotationSize)
                .background(.regularMaterial, in: Circle())
        }
    }
}


#if DEBUG

private final class DataSourceForPreviews: ObvMapViewDataSource {
    
    func fetchAvatar(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return UIImage.avatarForURL(url: photoURL)
    }
    
    
    func getAsyncStreamOfObvMapViewModel() throws -> AsyncStream<ObvMapViewModel> {
        let stream = AsyncStream(ObvMapViewModel.self) { (continuation: AsyncStream<ObvMapViewModel>.Continuation) in
            Task {
//                try! await Task.sleep(seconds: 2)
//                continuation.yield(ObvMapViewModel.sampleDatas[0])
//                try! await Task.sleep(seconds: 5)
                continuation.yield(ObvMapViewModel.sampleDatas[1])
//                try! await Task.sleep(seconds: 5)
//                continuation.yield(ObvMapViewModel.sampleDatas[0])
//                try! await Task.sleep(seconds: 5)
//                continuation.yield(ObvMapViewModel.sampleDatas[3])
//                try! await Task.sleep(seconds: 5)
//                continuation.yield(ObvMapViewModel.sampleDatas[1])
            }
        }
        return stream
    }
    
}


@MainActor
private final class ActionsForPreviews: ObvMapViewActionsProtocol {
    
    func userWantsToDismissObvMapView() {
        // Nothing to dismiss in previews
        print("Close button tapped")
    }
    
}

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@MainActor
private let actionsForPreviews = ActionsForPreviews()

@available(iOS 17.0, *)
#Preview {
    ObvMapView(dataSource: dataSourceForPreviews, actions: actionsForPreviews)
}

@available(iOS 17.0, *)
#Preview("With initial value") {
    ObvMapView(dataSource: dataSourceForPreviews, actions: actionsForPreviews, initialDeviceIdentifierToSelect: ObvDeviceIdentifier.sampleDatasOfContactDevices[0])
}


#endif
