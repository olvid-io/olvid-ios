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
import ObvTypes
import ObvDesignSystem
import ObvSubscription
import ObvSystemIcon

@MainActor
public protocol ObvSingleOwnedIdentityViewStackActions: ObvSingleOwnedIdentityViewActions, EditOwnedDetailsViewActions, OlvidShopViewActions, OwnedDevicesListViewActions {

}

@MainActor
public protocol ObvSingleOwnedIdentityViewStackNavigation {
    func userWantsToDismissPresentedNavigationStack(_ view: ObvSingleOwnedIdentityViewStack)
    func userWantsToNavigateToViewAllowingToAddNewDevice(_ view: ObvSingleOwnedIdentityViewStack, ownedCryptoId: ObvTypes.ObvCryptoId)
}

public struct ObvSingleOwnedIdentityViewStack: View {
    
    let ownedCryptoId: ObvCryptoId
    let dataSources: DataSources
    let actions: any ObvSingleOwnedIdentityViewStackActions
    let navigation: any ObvSingleOwnedIdentityViewStackNavigation
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    public struct DataSources {
        let olvidShopViewDataSources: OlvidShopView.DataSources
        let singleOwnedIdentityViewDataSources: ObvSingleOwnedIdentityView.DataSources
        let editOwnedDetailsViewDataSources: EditOwnedDetailsView.DataSources
        let ownedDevicesListViewDataSources: OwnedDevicesListView.DataSources
        public init(olvidShopViewDataSources: OlvidShopView.DataSources,
                    singleOwnedIdentityViewDataSources: ObvSingleOwnedIdentityView.DataSources,
                    editOwnedDetailsViewDataSources: EditOwnedDetailsView.DataSources,
                    ownedDevicesListViewDataSources: OwnedDevicesListView.DataSources) {
            self.olvidShopViewDataSources = olvidShopViewDataSources
            self.singleOwnedIdentityViewDataSources = singleOwnedIdentityViewDataSources
            self.editOwnedDetailsViewDataSources = editOwnedDetailsViewDataSources
            self.ownedDevicesListViewDataSources = ownedDevicesListViewDataSources
        }
    }

    private var navigationTitle: String {
        String(localizedInThisBundle: "MY_PROFILE_NAVIGATION_TITLE")
    }
    
    private func userWantsToDismissPresentedNavigationStack() {
        navigation.userWantsToDismissPresentedNavigationStack(self)
    }
    
    @State private var isEditOwnedDetailsViewPresented: Bool = false
    @State private var isOlvidShopViewPresented: Bool = false

    @State private var path = [Route]()

    private enum Route: Hashable, Identifiable {
        case listOfOwnedDevices
        
        var id: Self {
            return self
        }
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ObvSingleOwnedIdentityView(
                ownedCryptoId: ownedCryptoId,
                dataSources: dataSources.singleOwnedIdentityViewDataSources,
                actions: actions,
                navigation: self,
                uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(action: userWantsToDismissPresentedNavigationStack)
                }
            }
            .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isEditOwnedDetailsViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
                EditOwnedDetailsView(
                    ownedCryptoId: ownedCryptoId,
                    dataSources: dataSources.editOwnedDetailsViewDataSources,
                    actions: actions,
                    navigation: self)
            }
            .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isOlvidShopViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
                OlvidShopView(dataSources: dataSources.olvidShopViewDataSources,
                              navigation: self,
                              actions: actions)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .listOfOwnedDevices:
                    OwnedDevicesListView(
                        ownedCryptoId: ownedCryptoId,
                        dataSources: dataSources.ownedDevicesListViewDataSources,
                        actions: actions,
                        navigation: self)
                }
            }
        }
    }
    
}

// MARK: - Implementing OwnedDevicesListViewNavigation

extension ObvSingleOwnedIdentityViewStack: OwnedDevicesListViewNavigation {
    
    public func userWantsToSeeSubscriptionPlans(_ view: OwnedDevicesListView) {
        isOlvidShopViewPresented = true
    }
    
}

// MARK: - Implementing OlvidShopViewNavigation

extension ObvSingleOwnedIdentityViewStack: OlvidShopViewNavigation {
    
    public func userWantsToDismissPresentedOlvidShopView(_ view: OlvidShopView) {
        isOlvidShopViewPresented = false
    }
    
}

// MARK: - Implementing EditOwnedDetailsViewNavigation

extension ObvSingleOwnedIdentityViewStack: EditOwnedDetailsViewNavigation {
    
    public func userWantsToDismissEditOwnedDetailsView(_ view: EditOwnedDetailsView) {
        isEditOwnedDetailsViewPresented = false
    }
    
}

// MARK: - Implementing ObvSingleOwnedIdentityViewNavigation

extension ObvSingleOwnedIdentityViewStack: ObvSingleOwnedIdentityViewNavigation {
    
    public func userWantsToSeeSubscriptionPlans(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        isOlvidShopViewPresented = true
    }
    
    public func userWantsToEditOwnedProfile(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        isEditOwnedDetailsViewPresented = true
    }
    
    public func userWantsToNavigateToListOfOwnedDevices(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        path.append(Route.listOfOwnedDevices)
    }
    
    public func userWantsToNavigateToViewAllowingToAddNewDevice(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        navigation.userWantsToNavigateToViewAllowingToAddNewDevice(self, ownedCryptoId: ownedCryptoId)
    }
    
}
