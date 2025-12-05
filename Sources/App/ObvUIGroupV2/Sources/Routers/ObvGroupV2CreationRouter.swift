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
import ObvTypes
import ObvAppTypes
import ObvDesignSystem
import ObvUIGroupSharedBetweenV1AndV2

public enum ObvUIGroupV2RouterDataSourceMode {
    case creation(ownedCryptoId: ObvTypes.ObvCryptoId)
    case edition(groupIdentifier: ObvTypes.ObvGroupV2Identifier)
}


@MainActor
public final class ObvGroupV2CreationRouter {
    
    private let dataSources: ObvUIGroupV2RouterDataSources
    private let actions: any GroupV2CreationNavigationStackActions
    
    public enum CreationMode {
        case fromScratch
        case cloneExistingGroup(valuesOfGroupToClone: ValuesOfClonedGroup)
    }

    public struct ValuesOfClonedGroup {
        let userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier]
        let selectedAdmins: Set<SingleGroupMemberView.Model.Identifier>
        let selectedGroupType: ObvGroupType
        let selectedPhoto: UIImage?
        let selectedGroupName: String?
        let selectedGroupDescription: String?
        public init(userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier], selectedAdmins: Set<SingleGroupMemberView.Model.Identifier>, selectedGroupType: ObvGroupType, selectedPhoto: UIImage?, selectedGroupName: String?, selectedGroupDescription: String?) {
            self.userIdentifiersOfAddedUsers = userIdentifiersOfAddedUsers
            self.selectedAdmins = selectedAdmins
            self.selectedGroupType = selectedGroupType
            self.selectedPhoto = selectedPhoto
            self.selectedGroupName = selectedGroupName
            self.selectedGroupDescription = selectedGroupDescription
        }
    }

    public init(dataSources: ObvUIGroupV2RouterDataSources, actions: any GroupV2CreationNavigationStackActions) {
        self.dataSources = dataSources
        self.actions = actions
    }
    
}

// MARK: - Public API to present the flow on a navigation stack managed internally (in SwiftUI)

extension ObvGroupV2CreationRouter {
    
    public func presentInitialViewControllerForGroupV2Creation(
        ownedCryptoId: ObvCryptoId,
        creationMode: ObvGroupV2CreationRouter.CreationMode,
        presentingViewController: UIViewController,
        navigation: any GroupCreationNavigationStackNavigation,
        uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {

            let vc = GroupV2CreationNavigationStackViewController(
                ownedCryptoId: ownedCryptoId,
                creationMode: creationMode,
                dataSources: self.dataSources.groupV2CreationNavigationStackDataSources,
                actions: actions,
                navigation: navigation,
                uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
            var finalPresentingViewController = presentingViewController
            while let presentedViewController = finalPresentingViewController.presentedViewController {
                finalPresentingViewController = presentedViewController
            }
            finalPresentingViewController.present(vc, animated: true)

        }
    
}
