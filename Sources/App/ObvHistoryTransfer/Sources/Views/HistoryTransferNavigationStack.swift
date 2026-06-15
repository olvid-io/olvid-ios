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
#if canImport(WiFiAware)
import WiFiAware
#endif
import ObvSystemIcon
import ObvOwnedIdentityChooser
import ObvTypes
import ObvDesignSystem


@MainActor
public protocol HistoryTransferNavigationStackActions: LocalNetworkExportViewActions, LocalNetworkImportViewActions, ZipExportViewActions, ZipImportViewActions {
    func userWantsToDismissHistoryTransferNavigationStack(_ view: HistoryTransferNavigationStack)
}


public struct HistoryTransferNavigationStack: View {
    
    private let currentOwnedCryptoId: ObvCryptoId
    private let temporaryDirectory: URL
    private let dataSources: DataSources
    private let actions: any HistoryTransferNavigationStackActions
    
    init(currentOwnedCryptoId: ObvCryptoId,
         temporaryDirectory: URL,
         dataSources: DataSources,
         actions: any HistoryTransferNavigationStackActions) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.temporaryDirectory = temporaryDirectory
        self.dataSources = dataSources
        self.actions = actions
    }
    
    public struct DataSources {
        let ownedIdentityChooserViewDataSource: any OwnedIdentityChooserViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let listOfOtherOwnedDevicesViewDataSource: any ListOfOtherOwnedDevicesViewDataSource
        let zipExportViewDataSource: any ZipExportViewDataSource
        public init(ownedIdentityChooserViewDataSource: any OwnedIdentityChooserViewDataSource,
                    avatarViewDataSource: any ObvAvatarViewDataSource,
                    listOfOtherOwnedDevicesViewDataSource: any ListOfOtherOwnedDevicesViewDataSource,
                                        zipExportViewDataSource: any ZipExportViewDataSource) {
            self.ownedIdentityChooserViewDataSource = ownedIdentityChooserViewDataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.listOfOtherOwnedDevicesViewDataSource = listOfOtherOwnedDevicesViewDataSource
            self.zipExportViewDataSource = zipExportViewDataSource
        }
    }
    
    private func importHistoryButtonTapped() {
        path.append(.chooseProfileForHistoryImport)
    }
    
    private func exportHistoryButtonTapped() {
        path.append(.chooseProfileForHistoryExport)
    }
    
    enum FlowKind {
        case `import`
        case export
    }
    
    @State private var path = [Route]()

    private enum Route: Hashable {
        case chooseProfileForHistoryExport
        case chooseProfileForHistoryImport
        case showInstructionsForHistoryImport(selectedOwnedCryptoId: ObvCryptoId)
        case chooseTransferMethodView(selectedOwnedCryptoId: ObvCryptoId, role: TransferRole)
        case chooseRemoteOwnedDeviceForHistoryExport(selectedOwnedCryptoId: ObvCryptoId)
        case showWebRTCInstructions(otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier, nameOfRemoteDevice: String?)
        case chooseWhatToTransfer(transferMethod: ChooseWhatToTransferView.ForTransferMethod)
        case transferMethodChosen(transferMethod: ChooseWhatToTransferView.ForTransferMethod, scope: TransferScope)
        case zipImport(selectedOwnedCryptoId: ObvCryptoId)
        #if !targetEnvironment(macCatalyst) // For some reason, #if canImport(WiFiAware) does not work for iPad here
        case wifiAwarePairingOnDestination(selectedOwnedCryptoId: ObvCryptoId)
        case wifiAwareProgress(role: ObvWiFiAwareViewTransferRole, selectedOwnedCryptoId: ObvCryptoId, device: ObvWAPairedDevice)
        #endif
    }
    
    @State private var toggleToDismiss = false
    
    @State private var isWifiAwareNotAvailableAlertShown = false
    
    private func userTappedCancelButtonInToolbar() {
        actions.userWantsToDismissHistoryTransferNavigationStack(self)
    }
    
    
    public var body: some View {
        NavigationStack(path: $path) {
            Form {
                
                ExplanationsSectionView(explanation: "HISTORY_TRANSFER_EXPLANATION")
                
                Section(String(localizedInThisBundle: "IMPORT_CHAT_HISTORY_HEADER")) {
                    Text("IMPORT_EXPLANATION")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Button(action: importHistoryButtonTapped) {
                        HStack {
                            Image(systemIcon: .iphoneAndArrowForwardInward)
                            Text("BUTTON_TITLE_IMPORT")
                            Spacer(minLength: 0)
                            Image(systemIcon: .chevronRight)
                        }
                    }
                }
                
                
                Section(String(localizedInThisBundle: "EXPORT_CHAT_HISTORY_HEADER")) {
                    Text("EXPORT_EXPLANATION")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Button(action: exportHistoryButtonTapped) {
                        HStack {
                            Image(systemIcon: .iphoneAndArrowForwardOutward)
                            Text("BUTTON_TITLE_EXPORT")
                            Spacer(minLength: 0)
                            Image(systemIcon: .chevronRight)
                        }
                    }
                }
                                                
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .chooseProfileForHistoryExport,
                        .chooseProfileForHistoryImport:
                    OwnedIdentityChooserView(
                        currentOwnedCryptoId: currentOwnedCryptoId,
                        configuration: .init(
                            explanation: String(localizedInThisBundle: "CHOOSE_PROFILE_FOR_HISTORY_EXPORT_EXPLANATION"),
                            title: String(localizedInThisBundle: "CHOOSE_PROFILE_FOR_HISTORY_EXPORT_TITLE")),
                        dataSources: .init(ownedIdentityChooserViewDataSource: dataSources.ownedIdentityChooserViewDataSource,
                                           avatarViewDataSource: dataSources.avatarViewDataSource),
                        actions: self)
                    .toolbar {
                        ToolbarItem(placement: .destructiveAction) {
                            ObvButtonWithCancelRole(action: userTappedCancelButtonInToolbar)
                        }
                    }
                case .showInstructionsForHistoryImport(selectedOwnedCryptoId: _):
                    WebRTCImportInstructionsViewActions()
                        .toolbar {
                            ToolbarItem(placement: .destructiveAction) {
                                ObvButtonWithCancelRole(action: userTappedCancelButtonInToolbar)
                            }
                        }
                case .chooseRemoteOwnedDeviceForHistoryExport(selectedOwnedCryptoId: let selectedOwnedCryptoId):
                    ListOfOtherOwnedDevicesView(
                        ownedCryptoId: selectedOwnedCryptoId,
                        dataSource: dataSources.listOfOtherOwnedDevicesViewDataSource,
                        actions: self)
                    .toolbar {
                        ToolbarItem(placement: .destructiveAction) {
                            ObvButtonWithCancelRole(action: userTappedCancelButtonInToolbar)
                        }
                    }
                case .chooseWhatToTransfer(transferMethod: let transferMethod):
                    ChooseWhatToTransferView(transferMethod: transferMethod, actions: self)
                        .toolbar {
                            ToolbarItem(placement: .destructiveAction) {
                                ObvButtonWithCancelRole(action: userTappedCancelButtonInToolbar)
                            }
                        }
                case .transferMethodChosen(transferMethod: let transferMethod, scope: let scope):
                    switch transferMethod {
                    case .webrtc(otherOwnedDeviceIdentifier: let otherOwnedDeviceIdentifier, nameOfRemoteDevice: let nameOfRemoteDevice):
                        LocalNetworkExportView(
                            localNetorkType: .webRTC(otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier,
                                                     nameOfRemoteDevice: nameOfRemoteDevice),
                            scope: scope,
                            internalActions: self,
                            actions: actions
                        )
                    case .zip(ownedCryptoId: let ownedCryptoId):
                        ZipExportView(
                            ownedCryptoId: ownedCryptoId,
                            scope: scope,
                            dataSource: dataSources.zipExportViewDataSource,
                            internalActions: self,
                            actions: actions)
                    case .wifiAware(role: let role, ownedCryptoId: let ownedCryptoId):
                        #if !targetEnvironment(macCatalyst) // For some reason, #if canImport(WiFiAware) does not work for iPad here
                        if #available(iOS 26.0, *) {
                            switch role {
                            case .source:
                                ObvWiFiAwareView(
                                    role: .source(scope: scope),
                                    selectedOwnedCryptoId: ownedCryptoId,
                                    dataSource: ObvWiFiAwareViewDefaultDataSource(),
                                    navigation: self
                                )
                                .toolbar {
                                    ToolbarItem(placement: .destructiveAction) {
                                        ObvButtonWithCancelRole(action: userTappedCancelButtonInToolbar)
                                    }
                                }
                            case .destination:
                                ObvWiFiAwareView(
                                    role: .destination,
                                    selectedOwnedCryptoId: ownedCryptoId,
                                    dataSource: ObvWiFiAwareViewDefaultDataSource(),
                                    navigation: self
                                )
                                .toolbar {
                                    ToolbarItem(placement: .destructiveAction) {
                                        ObvButtonWithCancelRole(action: userTappedCancelButtonInToolbar)
                                    }
                                }
                            }
                        } else {
                            EmptyView()
                        }
                        #else
                        EmptyView()
                        #endif
                    }
                case .chooseTransferMethodView(selectedOwnedCryptoId: let selectedOwnedCryptoId, role: let role):
                    ChooseTransferMethodView(role: role, selectedOwnedCryptoId: selectedOwnedCryptoId, actions: self)
                        .alert(String(localizedInThisBundle: "WIFI_AWARE_NOT_AVAILABLE_ALERT_TITLE"),
                               isPresented: $isWifiAwareNotAvailableAlertShown,
                               actions: { Button(String(localizedInThisBundle: "OK"), action: {}) },
                               message: { Text("WIFI_AWARE_NOT_AVAILABLE_ALERT_MESSAGE") })
                        .toolbar {
                            ToolbarItem(placement: .destructiveAction) {
                                ObvButtonWithCancelRole(action: userTappedCancelButtonInToolbar)
                            }
                        }
                case .showWebRTCInstructions(otherOwnedDeviceIdentifier: let otherOwnedDeviceIdentifier, nameOfRemoteDevice: let nameOfRemoteDevice):
                    WebRTCInstructionsView(otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier, nameOfRemoteDevice: nameOfRemoteDevice, actions: self)
                        .toolbar {
                            ToolbarItem(placement: .destructiveAction) {
                                ObvButtonWithCancelRole(action: userTappedCancelButtonInToolbar)
                            }
                        }
                case .zipImport(selectedOwnedCryptoId: let selectedOwnedCryptoId):
                    ZipImportView(ownedCryptoId: selectedOwnedCryptoId,
                                          temporaryDirectory: temporaryDirectory,
                                          actions: actions)
                #if !targetEnvironment(macCatalyst) // For some reason, #if canImport(WiFiAware) does not work for iPad here
                case .wifiAwareProgress(role: let role, selectedOwnedCryptoId: let selectedOwnedCryptoId, device: let pairedDevice):
                    switch role {
                    case .source(scope: let scope):
                        LocalNetworkExportView(
                            localNetorkType: .wifiAware(ownedCryptoId: selectedOwnedCryptoId, pairedDevice: pairedDevice), scope: scope,
                            internalActions: self,
                            actions: actions
                        )
                    case .destination:
                        LocalNetworkImportView(
                            localNetworkType: .wifiAware(ownedCryptoId: selectedOwnedCryptoId, pairedDevice: pairedDevice),
                            actions: actions)
                    }
                case .wifiAwarePairingOnDestination(selectedOwnedCryptoId: let ownedCryptoId):
                    if #available(iOS 26.0, *) {
                        ObvWiFiAwareView(
                            role: .destination,
                            selectedOwnedCryptoId: ownedCryptoId,
                            dataSource: ObvWiFiAwareViewDefaultDataSource(),
                            navigation: self
                        )
                        .toolbar {
                            ToolbarItem(placement: .destructiveAction) {
                                ObvButtonWithCancelRole(action: userTappedCancelButtonInToolbar)
                            }
                        }
                    } else {
                        EmptyView()
                    }
                #endif // canImport(WifiAware)
                }
            }
            .navigationTitle(String(localizedInThisBundle: "NAVIGATION_TITLE_HISTORY_TRANSFER"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(action: userTappedCancelButtonInToolbar)
                }
            }

        }
    }
    
}


// MARK: - Implementing ObvWiFiAwareViewNavigation

#if !targetEnvironment(macCatalyst) // For some reason, #if canImport(WiFiAware) does not work for iPad here
@available(iOS 26.0, *)
extension HistoryTransferNavigationStack: ObvWiFiAwareViewNavigation {
     
    func userDidChoosePairedDevice(_ view: ObvWiFiAwareView, selectedOwnedCryptoId: ObvCryptoId, role: ObvWiFiAwareViewTransferRole, device: ObvWAPairedDevice) {
        self.path.append(.wifiAwareProgress(role: role, selectedOwnedCryptoId: selectedOwnedCryptoId, device: device))
    }
    
}
#endif // canImport(WifiAware)


// MARK: - Implementing ZipExportViewInternalActions

extension HistoryTransferNavigationStack: ZipExportViewInternalActions {
    
    public func userWantsToPopView(_ view: ZipExportView) {
        _ = self.path.popLast()
    }
    
}


// MARK: - Implementing LocalNetworkExportViewInternalActions

extension HistoryTransferNavigationStack: LocalNetworkExportViewInternalActions {
    
    public func userWantsToPopView(_ view: LocalNetworkExportView) {
        _ = self.path.popLast()
    }
    
}


// MARK: - Implementing WebRTCInstructionsViewActions

extension HistoryTransferNavigationStack: WebRTCInstructionsViewActions {
    
    func userConfirmedOnSourceDeviceThatDestinationDeviceIsOnSameWifiNetwork(_ view: WebRTCInstructionsView, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier, nameOfRemoteDevice: String?) {
        path.append(.chooseWhatToTransfer(transferMethod: .webrtc(otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier, nameOfRemoteDevice: nameOfRemoteDevice)))
    }
    
}


// MARK: - Implementing ListOfOtherOwnedDevicesViewActions

extension HistoryTransferNavigationStack: ListOfOtherOwnedDevicesViewActions {
        
    func userDidChooseOtherOwnedDevice(_ view: ListOfOtherOwnedDevicesInnerView, otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier, nameOfRemoteDevice: String?) {
        path.append(.showWebRTCInstructions(otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier, nameOfRemoteDevice: nameOfRemoteDevice))
    }

    func userTappedBackButton(_ view: ListOfOtherOwnedDevicesView) {
        _ = path.popLast()
    }
    
}


// MARK: - Implementing OwnedIdentityChooserViewActionsProtocol

extension HistoryTransferNavigationStack: OwnedIdentityChooserViewActions {
    
    public func userDidConfirmOwnedCryptoIdSelection(
        _ view: ObvOwnedIdentityChooser.OwnedIdentityChooserView,
        selectedOwnedCryptoId: ObvTypes.ObvCryptoId
    ) {
        switch path.last {
        case .none:
            return
        case .chooseProfileForHistoryExport:
            path.append(.chooseTransferMethodView(selectedOwnedCryptoId: selectedOwnedCryptoId, role: .source))
        case .chooseProfileForHistoryImport:
            path.append(.chooseTransferMethodView(selectedOwnedCryptoId: selectedOwnedCryptoId, role: .destination))
        default:
            return
        }
    }
    
}



// MARK: - Implementing ChooseWhatToTransferViewActions

extension HistoryTransferNavigationStack: ChooseWhatToTransferViewActions {
    
    func userDidChooseWhatToTransferToDestination(_ view: ChooseWhatToTransferView, transferMethod: ChooseWhatToTransferView.ForTransferMethod, scope: TransferScope) {
        path.append(.transferMethodChosen(transferMethod: transferMethod, scope: scope))
    }
    
}


// MARK: - Implementing ChooseTransferMethodViewActions

extension HistoryTransferNavigationStack: ChooseTransferMethodViewActions {

    func userChoseTransferMethod(selectedTransferMethod: TransferMethod, selectedOwnedCryptoId: ObvCryptoId, role: TransferRole) {
        switch selectedTransferMethod {
        case .webRTC:
            switch role {
            case .source:
                path.append(.chooseRemoteOwnedDeviceForHistoryExport(selectedOwnedCryptoId: selectedOwnedCryptoId))
            case .destination:
                path.append(.showInstructionsForHistoryImport(selectedOwnedCryptoId: selectedOwnedCryptoId))
            }
        case .wifiAware:
            if #available(iOS 26.0, *) {
                switch role {
                case .source:
                    path.append(.chooseWhatToTransfer(transferMethod: .wifiAware(role: role, ownedCryptoId: selectedOwnedCryptoId)))
                case .destination:
                    #if !targetEnvironment(macCatalyst) // For some reason, #if canImport(WiFiAware) does not work for iPad here
                    path.append(.wifiAwarePairingOnDestination(selectedOwnedCryptoId: selectedOwnedCryptoId))
                    #endif
                }
//                if WACapabilities.supportedFeatures.contains(.wifiAware) {
//                    path.append(.wifiAwarePairing(role: role, selectedOwnedCryptoId: selectedOwnedCryptoId))
//                } else {
//                    isWifiAwareNotAvailableAlertShown = true
//                }
            } else {
                isWifiAwareNotAvailableAlertShown = true
            }
        case .zip:
            switch role {
            case .source:
                path.append(.chooseWhatToTransfer(transferMethod: .zip(ownedCryptoId: selectedOwnedCryptoId)))
            case .destination:
                path.append(.zipImport(selectedOwnedCryptoId: selectedOwnedCryptoId))
            }
        }
    }
    
}


// MARK: - Previews

#if DEBUG

private let dataSourceForPreviews = GenericDataSourceForPreviews()

#Preview {
    HistoryTransferNavigationStack(
        currentOwnedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0],
        temporaryDirectory: FileManager.default.temporaryDirectory,
        dataSources: .init(ownedIdentityChooserViewDataSource: dataSourceForPreviews,
                           avatarViewDataSource: dataSourceForPreviews,
                           listOfOtherOwnedDevicesViewDataSource: dataSourceForPreviews,
                                               zipExportViewDataSource: dataSourceForPreviews),
        actions: dataSourceForPreviews)
}

#endif
