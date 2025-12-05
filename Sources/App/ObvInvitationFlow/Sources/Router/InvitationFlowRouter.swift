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
import SwiftUI
import CoreData
import ObvDesignSystem
import ObvTypes
import ObvCells


/// Defines the presentation modes for the invitation flow in `InvitationFlowHostingController`.
///
/// The invitation flow supports two distinct modes:
///
/// - **`.listOfContactsAndGroups`**:
///   Displays a root view with two primary buttons at the top:
///   - **Invite a new user**: Pops a view allowing to choose how to invite a new contact.
///   - **Create a new group**: Dismisses the invitation flow and opens the group creation flow.
///
///   Below the buttons, the view includes two lists:
///   - **Contacts List**: Shows all direct and indirect contacts of the user.
///   - **Groups List**: Displays existing groups the user belongs to.
///
///   **Keycloak-Managed Identities**:
///   If the user's identity is managed by Keycloak, a third list appears, allowing the user to search for Keycloak users.
///
/// - **`.scanner`**:
///   Displays the same root view as `.listOfContactsAndGroups`, but immediately presents the scanner view in full-screen mode upon appearance.
public enum InvitationFlowRouterMode {
    case listOfContactsAndGroups
    case scanner
}

@MainActor
public protocol InvitationFlowRouterNavigation: ListOfContactsAndGroupsViewNavigation {
    
}

@MainActor
final class InvitationFlowRouter: ObservableObject, @unchecked Sendable {
    
    enum Route: Hashable, Identifiable, Equatable {
        case listOfContactsAndGroups(ownedURLIdentity: ObvURLIdentity, ownedIdentityIsManagedByKeycloak: Bool)
        case scanner(currentOwnedCryptoId: ObvCryptoId, scannerMode: NewScannerView.ScannerMode)
        case scanValidation(currentOwnedCryptoId: ObvCryptoId, initalScanViewModel: ScanValidationViewModel)
        case sharingProfile(currentOwnedCryptoId: ObvCryptoId)
        case invitation(contactIdentifier: ContactInvitationViewModel.ContactIdentifier, currentOwnedCryptoId: ObvCryptoId) // When sending a one2one invitation to a collected contact
        case externalInvitation(mutualScanURLToShow: ObvMutualScanUrl, remoteURLIdentity: ObvURLIdentity) // When this flow is lauched as the user scans/taps an invitation link from outside the app

        var id: Self {
            return self
        }
    }
    
    enum NavigationType {
        case push
        case sheet
        case fullScreenCover
    }
    
    @Published var path = [Route]()
    @Published var routePresentedAsSheet: Route?
    @Published var routePresentedAsFullScreenCover: Route?
    
    var actionToPerformOnSheetDismissal: (() -> Void)? // Action to call when a sheet or cover is dismissed
    
    let parentRouter: InvitationFlowRouter?
    
    let invitationFlowHostingControllerDataSources: InvitationFlowHostingControllerDataSources
    
    var invitationContactsListViewDataSource: any ListOfContactsAndGroupsViewDataSource { invitationFlowHostingControllerDataSources.invitationContactsListViewDataSource }
    var scanValidationViewDataSource: any ObvScanValidationViewDataSource { invitationFlowHostingControllerDataSources.scanValidationViewDataSource }
    var avatarViewDataSource: any ObvAvatarViewDataSource { invitationFlowHostingControllerDataSources.avatarViewDataSource }
    var groupCellViewDataSource: any ObvGroupCellViewDataSource { invitationFlowHostingControllerDataSources.groupCellViewDataSource }
    var scannerViewDataSource: any ObvNewScannerViewDataSource { invitationFlowHostingControllerDataSources.scannerViewDataSource }
    var qrCodeViewDataSource: ObvQRCodeViewDataSource { invitationFlowHostingControllerDataSources.qrCodeViewDataSource }
    var contactInvitationViewDataSource: any ObvContactInvitationViewDataSource { invitationFlowHostingControllerDataSources.contactInvitationViewDataSource }
    var sharingProfileViewDataSource: any ObvSharingProfileViewDataSource { invitationFlowHostingControllerDataSources.sharingProfileViewDataSource }
    var externalInvitationHandlerViewDataSource: any ObvExternalInvitationHandlerViewDataSource { invitationFlowHostingControllerDataSources.externalInvitationHandlerViewDataSource }
    
    let listOfContactsAndGroupsViewActions: any ListOfContactsAndGroupsViewActions
    let copyPasteMenuActions: any ObvCopyPasteMenuActions
    let scanValidationViewActions: any ObvScanValidationViewActions
    let scannerViewActions: ObvScannerViewActions
    let contactInvitationViewAction: any ObvContactInvitationViewAction
    let externalInvitationHandlerViewActions: any ObvExternalInvitationHandlerViewActions
    
    let navigation: any InvitationFlowRouterNavigation
    
    init(parentRouter: InvitationFlowRouter?,
         invitationFlowHostingControllerDataSources: InvitationFlowHostingControllerDataSources,
         listOfContactsAndGroupsViewActions: any ListOfContactsAndGroupsViewActions,
         scanValidationViewActions: any ObvScanValidationViewActions,
         scannerViewActions: ObvScannerViewActions,
         contactInvitationViewAction: any ObvContactInvitationViewAction,
         copyPasteMenuActions: any ObvCopyPasteMenuActions,
         externalInvitationHandlerViewActions: any ObvExternalInvitationHandlerViewActions,
         navigation: any InvitationFlowRouterNavigation) {
        self.parentRouter = parentRouter
        self.invitationFlowHostingControllerDataSources = invitationFlowHostingControllerDataSources
        self.listOfContactsAndGroupsViewActions = listOfContactsAndGroupsViewActions
        self.scannerViewActions = scannerViewActions
        self.scanValidationViewActions = scanValidationViewActions
        self.contactInvitationViewAction = contactInvitationViewAction
        self.copyPasteMenuActions = copyPasteMenuActions
        self.externalInvitationHandlerViewActions = externalInvitationHandlerViewActions
        self.navigation = navigation
    }
    
#if DEBUG
    
    static func initForPreviews(invitationContactsListViewDataSource: any ListOfContactsAndGroupsViewDataSource = MinimalDataSourceAndActionsForPreviews(),
                                externalInvitationHandlerViewDataSource: any ObvExternalInvitationHandlerViewDataSource = MinimalDataSourceAndActionsForPreviews(),
                                sharingProfileViewDataSource: any ObvSharingProfileViewDataSource = MinimalDataSourceAndActionsForPreviews(),
                                scanValidationViewDataSource: any ObvScanValidationViewDataSource = MinimalDataSourceAndActionsForPreviews(),
                                avatarViewDataSource: any ObvAvatarViewDataSource = MinimalDataSourceAndActionsForPreviews(),
                                groupCellViewDataSource: any ObvGroupCellViewDataSource = MinimalDataSourceAndActionsForPreviews(),
                                listOfContactsAndGroupsViewActions: any ListOfContactsAndGroupsViewActions = MinimalDataSourceAndActionsForPreviews(),
                                scanValidationViewActions: any ObvScanValidationViewActions = MinimalDataSourceAndActionsForPreviews(),
                                scannerViewActions: ObvScannerViewActions = MinimalDataSourceAndActionsForPreviews(),
                                qrCodeViewDataSource: ObvQRCodeViewDataSource = MinimalDataSourceAndActionsForPreviews(),
                                contactInvitationViewDataSource: any ObvContactInvitationViewDataSource = MinimalDataSourceAndActionsForPreviews(),
                                scannerViewDataSource: any ObvNewScannerViewDataSource = MinimalDataSourceAndActionsForPreviews(),
                                contactInvitationViewAction: any ObvContactInvitationViewAction = MinimalDataSourceAndActionsForPreviews(),
                                copyPasteMenuActions: any ObvCopyPasteMenuActions = MinimalDataSourceAndActionsForPreviews(),
                                externalInvitationHandlerViewActions: any ObvExternalInvitationHandlerViewActions = MinimalDataSourceAndActionsForPreviews(),
                                navigation: any InvitationFlowRouterNavigation = MinimalDataSourceAndActionsForPreviews()) -> Self {
        self.init(parentRouter: nil,
                  invitationFlowHostingControllerDataSources: .init(
                    sharingProfileViewDataSource: sharingProfileViewDataSource,
                    scanValidationViewDataSource: scanValidationViewDataSource,
                    avatarViewDataSource: avatarViewDataSource,
                    groupCellViewDataSource: groupCellViewDataSource,
                    qrCodeViewDataSource: qrCodeViewDataSource,
                    scannerViewDataSource: scannerViewDataSource,
                    contactInvitationViewDataSource: contactInvitationViewDataSource,
                    externalInvitationHandlerViewDataSource: externalInvitationHandlerViewDataSource,
                    invitationContactsListViewDataSource: invitationContactsListViewDataSource),
                  listOfContactsAndGroupsViewActions: listOfContactsAndGroupsViewActions,
                  scanValidationViewActions: scanValidationViewActions,
                  scannerViewActions: scannerViewActions,
                  contactInvitationViewAction: contactInvitationViewAction,
                  copyPasteMenuActions: copyPasteMenuActions,
                  externalInvitationHandlerViewActions: externalInvitationHandlerViewActions,
                  navigation: navigation)
                
    }

#endif

    
    @ViewBuilder
    func view(for route: Route, type: NavigationType = .push) -> some View {
        switch type {
        case .push:
            internalView(for: route, type: type)
        case .sheet, .fullScreenCover:
            NavigationStack {
                internalView(for: route, type: type)
            }
        }
    }
    
    
    /// Helper for `func view(for route: Route, type: NavigationType = .push)`
    @ViewBuilder
    func internalView(for route: Route, type: NavigationType) -> some View {
        switch route {
        case .listOfContactsAndGroups(ownedURLIdentity: let ownedURLIdentity, ownedIdentityIsManagedByKeycloak: let isKeycloak):
            ListOfContactsAndGroupsView(ownedURLIdentity: ownedURLIdentity, ownedIdentityIsManagedByKeycloak: isKeycloak, router: router(navigationType: type), navigation: navigation)
        case .scanner(let cryptoId, let scannerMode):
            NewScannerView(ownedCryptoId: cryptoId, initialScannerMode: scannerMode, actions: scannerViewActions, router: router(navigationType: type))
        case .sharingProfile(let cryptoId):
            SharingProfileView(currentOwnedCryptoId: cryptoId, router: router(navigationType: type))
        case .invitation(let contactIdentifier, let cryptoId):
            ContactInvitationView(contactIdentifier: contactIdentifier, currentOwnedCryptoId: cryptoId, router: router(navigationType: type))
        case .scanValidation(currentOwnedCryptoId: let cryptoId, initalScanViewModel: let initalScanViewModel):
            ScanValidationView(currentOwnedCryptoId: cryptoId, initialViewModel: initalScanViewModel, router: router(navigationType: type))
        case .externalInvitation(mutualScanURLToShow: let mutualScanURLToShow, remoteURLIdentity: let remoteURLIdentity):
            ExternalInvitationHandlerView(router: router(navigationType: type), mutualScanURLToShow: mutualScanURLToShow, remoteURLIdentity: remoteURLIdentity, actions: externalInvitationHandlerViewActions)
        }
    }


    // Pop to the root screen in our hierarchy
    func popToRoot() {
        path.removeLast(path.count)
    }
    
    @discardableResult
    func dismiss() -> Bool {
        var hasNavigated: Bool = true
        
        if !path.isEmpty {
            path.removeLast()
        } else if routePresentedAsSheet != nil {
            self.routePresentedAsSheet = nil
        } else if routePresentedAsFullScreenCover != nil {
            self.routePresentedAsFullScreenCover = nil
        } else {
            hasNavigated = false
        }
        
        if !hasNavigated {
            self.parentRouter?.dismiss()
        }
        
        return hasNavigated
    }
    

    // Used by views to navigate to another view
    func pushRoute(_ route: Route) {
        path.append(route)
    }
    

    func presentSheet(_ route: Route) {
        self.routePresentedAsSheet = route
    }

    
    /// Presents a route in full-screen mode, replacing the current view.
    ///
    /// This method creates a new child router for the presented view and ensures the presentation is handled by the root router.
    /// Only the root router (with no parent) can present full-screen views. To achieve this, the method traverses up the router hierarchy
    /// until it reaches the root router, which then performs the full-screen presentation.
    ///
    /// - Use Case:
    ///   For example, when the scanner view needs to present the scanner confirmation screen after a double scan,
    ///   this method ensures the scanner view is replaced by the confirmation view in full-screen mode.
    ///   This avoids stacking full-screen views on top of each other (which is impossible anyway)
    func presentFullScreen(_ route: Route) {
        var rootRouter = self
        while let parentRouter = rootRouter.parentRouter {
            rootRouter = parentRouter
        }
        rootRouter.routePresentedAsFullScreenCover = route
    }
    
    func router(navigationType: NavigationType) -> InvitationFlowRouter {
        switch navigationType {
        case .push:
            return self
        case .sheet:
            return InvitationFlowRouter(
                parentRouter: self,
                invitationFlowHostingControllerDataSources: invitationFlowHostingControllerDataSources,
                listOfContactsAndGroupsViewActions: listOfContactsAndGroupsViewActions,
                scanValidationViewActions: scanValidationViewActions,
                scannerViewActions: scannerViewActions,
                contactInvitationViewAction: contactInvitationViewAction,
                copyPasteMenuActions: copyPasteMenuActions,
                externalInvitationHandlerViewActions: externalInvitationHandlerViewActions,
                navigation: navigation
            )
        case .fullScreenCover:
            return InvitationFlowRouter(
                parentRouter: self,
                invitationFlowHostingControllerDataSources: invitationFlowHostingControllerDataSources,
                listOfContactsAndGroupsViewActions: listOfContactsAndGroupsViewActions,
                scanValidationViewActions: scanValidationViewActions,
                scannerViewActions: scannerViewActions,
                contactInvitationViewAction: contactInvitationViewAction,
                copyPasteMenuActions: copyPasteMenuActions,
                externalInvitationHandlerViewActions: externalInvitationHandlerViewActions,
                navigation: navigation
            )
        }
    }
    
    func onDismissForSheetOrCover() {
        actionToPerformOnSheetDismissal?()
    }
}
