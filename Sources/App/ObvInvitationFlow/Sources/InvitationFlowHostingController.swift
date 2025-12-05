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

@preconcurrency import UIKit
import SwiftUI
import ObvAppTypes
import ObvTypes
import CoreData
import ObvDesignSystem
import ObvCells


public final class InvitationFlowHostingController: KeyboardHostingController<InvitationFlowRouterView> {
    
    private var observationTokens = [NSObjectProtocol]()
    public override var canBecomeFirstResponder: Bool { true }
    
    let ownedURLIdentity: ObvURLIdentity
    let router: InvitationFlowRouter
    
    private var currentOwnedCryptoId: ObvCryptoId {
        ownedURLIdentity.cryptoId
    }
        
    public init(ownedURLIdentity: ObvURLIdentity,
                ownedIdentityIsManagedByKeycloak: Bool,
                routerMode: InvitationFlowRouterMode,
                invitationFlowHostingControllerDataSources: InvitationFlowHostingControllerDataSources,
                actions: InvitationFlowHostingControllerActions,
                navigation: any InvitationFlowRouterNavigation) {
  
        self.ownedURLIdentity = ownedURLIdentity
        
        router = InvitationFlowRouter(parentRouter: nil,
                                      invitationFlowHostingControllerDataSources: invitationFlowHostingControllerDataSources,
                                      listOfContactsAndGroupsViewActions: actions,
                                      scanValidationViewActions: actions,
                                      scannerViewActions: actions,
                                      contactInvitationViewAction: actions,
                                      copyPasteMenuActions: actions,
                                      externalInvitationHandlerViewActions: actions,
                                      navigation: navigation)
        
        let routerView = InvitationFlowRouterView(ownedURLIdentity: ownedURLIdentity,
                                                  ownedIdentityIsManagedByKeycloak: ownedIdentityIsManagedByKeycloak,
                                                  routerMode: routerMode,
                                                  router: router)
        
        super.init(rootView: routerView)
        
        self.view.backgroundColor = .clear
    }
    
    @MainActor required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
    }
    
    
    public func handleExternalInvitation(mutualScanURLToShow: ObvMutualScanUrl, remoteURLIdentity: ObvURLIdentity) {
        self.router.popToRoot()
        self.router.pushRoute(.externalInvitation(mutualScanURLToShow: mutualScanURLToShow, remoteURLIdentity: remoteURLIdentity))
        //self.router.presentFullScreen(.externalInvitation(mutualScanURLToShow: mutualScanURLToShow, remoteURLIdentity: remoteURLIdentity))
    }
    

    /// Called when the user scans or pastes an `OlvidURL` of category `mutualScan`.
    ///
    /// This typically occurs during the `ObvInvitationFlow` within the `ScannerView`:
    /// 1. The remote Olvid user scans the current user’s invitation QR code.
    /// 2. The current user then scans the remote user’s `ObvMutualScanUrl`.
    /// 3. The `ScannerView` notifies its delegate with the scanned `OlvidURL`.
    /// 4. The delegate parses the URL, identifies the `mutualScan` category, and invokes this method to resume the flow.
    ///
    /// This method is also called in rare cases where the user scans or taps an `ObvMutualScanUrl` from outside Olvid,
    /// such as through the system camera or a shared link.
    public func mutualScanURLWasHandled(initalScanViewModel: ScanValidationViewModel) {
        self.router.presentFullScreen(.scanValidation(currentOwnedCryptoId: currentOwnedCryptoId, initalScanViewModel: initalScanViewModel))
    }
    
}

/// Since all the actions are implemented by the `MainFlowViewController` in practice, we define this simple typealias to simplify the `InvitationFlowHostingController` initialiser.
public typealias InvitationFlowHostingControllerActions = ListOfContactsAndGroupsViewActions & ObvScanValidationViewActions & ObvScannerViewActions & ObvContactInvitationViewAction & ObvCopyPasteMenuActions & ObvExternalInvitationHandlerViewActions

// MARK: - InvitationFlowHostingControllerDataSources

/// A convenience structure that consolidates all the data sources required to initialize the `ObvInvitationFlow` within the `InvitationFlowHostingController`.
public struct InvitationFlowHostingControllerDataSources {
    let sharingProfileViewDataSource: any ObvSharingProfileViewDataSource
    let scanValidationViewDataSource: any ObvScanValidationViewDataSource
    let avatarViewDataSource: any ObvAvatarViewDataSource
    let groupCellViewDataSource: any ObvGroupCellViewDataSource
    let qrCodeViewDataSource: any ObvQRCodeViewDataSource
    let scannerViewDataSource: any ObvNewScannerViewDataSource
    let contactInvitationViewDataSource: any ObvContactInvitationViewDataSource
    let externalInvitationHandlerViewDataSource: any ObvExternalInvitationHandlerViewDataSource
    let invitationContactsListViewDataSource: any ListOfContactsAndGroupsViewDataSource
    
    public init(sharingProfileViewDataSource: any ObvSharingProfileViewDataSource, scanValidationViewDataSource: any ObvScanValidationViewDataSource, avatarViewDataSource: any ObvAvatarViewDataSource, groupCellViewDataSource: any ObvGroupCellViewDataSource, qrCodeViewDataSource: any ObvQRCodeViewDataSource, scannerViewDataSource: any ObvNewScannerViewDataSource, contactInvitationViewDataSource: any ObvContactInvitationViewDataSource, externalInvitationHandlerViewDataSource: any ObvExternalInvitationHandlerViewDataSource, invitationContactsListViewDataSource: any ListOfContactsAndGroupsViewDataSource) {
        self.sharingProfileViewDataSource = sharingProfileViewDataSource
        self.scanValidationViewDataSource = scanValidationViewDataSource
        self.avatarViewDataSource = avatarViewDataSource
        self.groupCellViewDataSource = groupCellViewDataSource
        self.qrCodeViewDataSource = qrCodeViewDataSource
        self.scannerViewDataSource = scannerViewDataSource
        self.contactInvitationViewDataSource = contactInvitationViewDataSource
        self.externalInvitationHandlerViewDataSource = externalInvitationHandlerViewDataSource
        self.invitationContactsListViewDataSource = invitationContactsListViewDataSource
    }
    
}
