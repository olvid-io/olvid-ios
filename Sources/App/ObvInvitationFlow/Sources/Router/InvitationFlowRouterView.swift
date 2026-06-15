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

import Foundation
import SwiftUI
import ObvTypes
import CoreData
import ObvDesignSystem

/// View containing the necessary SwiftUI
/// code to utilize a NavigationStack for
/// navigation accross our views.
public struct InvitationFlowRouterView: View {
    
    @StateObject var router: InvitationFlowRouter
    private let ownedURLIdentity: ObvURLIdentity
    private let ownedIdentityIsManagedByKeycloak: Bool
    private let routerMode: InvitationFlowRouterMode
    
    private var currentOwnedCryptoId: ObvCryptoId {
        ownedURLIdentity.cryptoId
    }
    
    init(ownedURLIdentity: ObvURLIdentity,
         ownedIdentityIsManagedByKeycloak: Bool,
         routerMode: InvitationFlowRouterMode,
         router: InvitationFlowRouter) {
        self.ownedURLIdentity = ownedURLIdentity
        self.ownedIdentityIsManagedByKeycloak = ownedIdentityIsManagedByKeycloak
        _router = StateObject(wrappedValue: router)
        self.routerMode = routerMode
    }
    
    private func getRootView() -> InvitationFlowRouter.Route {
        let rootRoute: InvitationFlowRouter.Route
        
        switch routerMode {
        case .listOfContactsAndGroups:
            rootRoute = .listOfContactsAndGroups(ownedURLIdentity: ownedURLIdentity, ownedIdentityIsManagedByKeycloak: ownedIdentityIsManagedByKeycloak)
        case .scanner:
            // Note that in this mode, the scanner view is presented full screen when the root view appears.
            rootRoute = .listOfContactsAndGroups(ownedURLIdentity: ownedURLIdentity, ownedIdentityIsManagedByKeycloak: ownedIdentityIsManagedByKeycloak)
        }
        
        return rootRoute
    }
    
    @ViewBuilder
    public var root: some View {
        router.view(for: getRootView())
    }
    public var body: some View {
        
//        let _ = Self._printChanges() // Use to print changes to observable
        
        NavigationStack(path: $router.path) {
            root
                .navigationDestination(for: InvitationFlowRouter.Route.self) { route in
                    router.view(for: route)
                }
        }
        .sheet(item: $router.routePresentedAsSheet, onDismiss: router.onDismissForSheetOrCover) { route in
            router.view(for: route, type: .sheet)
        }
        .fullScreenCover(item: $router.routePresentedAsFullScreenCover, onDismiss: router.onDismissForSheetOrCover) { route in
            router.view(for: route, type: .fullScreenCover)
        }
        .onAppear {
            switch routerMode {
            case .listOfContactsAndGroups:
                break
            case .scanner:
                Task { @MainActor in
                    // Small delay to allow the view to complete its initial rendering
                    try? await Task.sleep(milliseconds: 250) // 0.25 seconds
                    router.presentFullScreen(.scanner(currentOwnedCryptoId: currentOwnedCryptoId,
                                                      scannerMode: .mutualScan(ownedURLIdentityToShow: ownedURLIdentity)))
                }
            }
        }
    }
    
    public func dismiss() -> Bool {
        return router.dismiss()
    }
}
