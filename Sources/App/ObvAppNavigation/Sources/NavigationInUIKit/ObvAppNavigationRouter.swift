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

import UIKit
import SwiftUI
import ObvTypes
import ObvAppTypes
import ObvSingleContact
import ObvCells
import ObvUIGroupV1
import ObvUIGroupV2
import ObvUIGroupSharedBetweenV1AndV2
import ObvDesignSystem
import OlvidUtils


/// Most of the navigation can be handled by the `ObvAppNavigationRouter`. Certain views are still managed by the app itself. For those we forward the navigation calls to our delegate.
@MainActor
public protocol ObvAppNavigationRouterNavigation {
    
    func userWantsToNavigateToOneToOneDiscussionWithContact(_ router: ObvAppNavigationRouter, contactIdentifier: ObvTypes.ObvContactIdentifier) throws // ok
    func userWantsToNavigateToGroupDiscussion(_ router: ObvAppNavigationRouter, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) // ok
    
    func userWantsToCallContact(_ router: ObvAppNavigationRouter, contactIdentifier: ObvTypes.ObvContactIdentifier)
    func userWantsToCall(_ router: ObvAppNavigationRouter, groupIdentifier: ObvAppTypes.ObvGroupIdentifier)

    func userWantsToEditContactNicknameAndCustomPicture(_ router: ObvAppNavigationRouter, contactIdentifier: ObvTypes.ObvContactIdentifier) // ok
    func userWantsToEditGroupNicknameAndCustomPicture(_ router: ObvAppNavigationRouter, groupIdentifier: ObvAppTypes.ObvGroupIdentifier)
    
    func userWantsToIntroduceOneContactToAnother(_ router: ObvAppNavigationRouter, contactIdentifier: ObvTypes.ObvContactIdentifier) throws // ok
    func userWantsToCreateNewGroupWithContact(_ router: ObvAppNavigationRouter, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws // ok
    
    func userWantsToCloneGroup(_ router: ObvAppNavigationRouter, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async throws // ok

}

public typealias ObvAppNavigationRouterActions = any ObvSingleContactViewActions & ObvListOfContactDevicesViewActions & SingleGroupV1MainViewActionsProtocol & SingleGroupV2MainViewActionsProtocol & ListOfMembersWithAddAndRemoveButtonsViewActions & ListOfMembersWithSegmentedControlViewActions & OnetoOneInvitableGroupMembersViewActionsProtocol & ObvPresentedNavigationStackActions


@MainActor
public final class ObvAppNavigationRouter {
    
    private let dataSources: DataSources
    private let actions: ObvAppNavigationRouterActions
    private let navigation: any ObvAppNavigationRouterNavigation
    private let navigationController: UINavigationController
    private var currentlyPresentingViewController: UIViewController? // The view controller that was most recently used to present a view controller
    
    public init(dataSources: DataSources,
                actions: ObvAppNavigationRouterActions,
                navigation: any ObvAppNavigationRouterNavigation,
                navigationController: UINavigationController) {
        self.dataSources = dataSources
        self.actions = actions
        self.navigation = navigation
        self.navigationController = navigationController
    }
    
    public struct DataSources {
        let listOfContactDevicesViewDataSource: any ObvListOfContactDevicesViewDataSource
        let trustOriginsListViewDataSource: any ObvTrustOriginsListViewDataSource
        let singleGroupV2MainViewDataSource: any SingleGroupV2MainViewDataSource
        let onetoOneInvitableGroupMembersViewDataSource: any OnetoOneInvitableGroupMembersViewDataSource
        let onetoOneInvitableGroupMembersViewCellDataSource: any OnetoOneInvitableGroupMembersViewCellDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let fullListOfGroupMembersViewDataSource: any FullListOfGroupMembersViewDataSource
        let singleContactViewDataSources: ObvSingleContactView.DataSources
        let listOfCommonGroupsWithContactViewDataSources: ObvListOfCommonGroupsWithContactView.DataSources
        let singleGroupV1MainViewDataSources: SingleGroupV1MainView.DataSources
        let singleGroupV2MainViewSubDataSources: SingleGroupV2MainView.SubDataSources
        let listOfMembersWithAddAndRemoveButtonsViewDataSources: ListOfMembersWithAddAndRemoveButtonsView.DataSources
        let listOfMembersWithSegmentedControlViewDataSources: ListOfMembersWithSegmentedControlView.DataSources
        let fullListOfGroupMembersViewSubDataSources: FullListOfGroupMembersView.SubDataSources
        let presentedNavigationStackDataSources: ObvPresentedNavigationStack.DataSources
        
        public init(listOfContactDevicesViewDataSource: any ObvListOfContactDevicesViewDataSource,
                    trustOriginsListViewDataSource: any ObvTrustOriginsListViewDataSource,
                    singleGroupV2MainViewDataSource: any SingleGroupV2MainViewDataSource,
                    onetoOneInvitableGroupMembersViewDataSource: any OnetoOneInvitableGroupMembersViewDataSource,
                    onetoOneInvitableGroupMembersViewCellDataSource: any OnetoOneInvitableGroupMembersViewCellDataSource,
                    avatarViewDataSource: any ObvAvatarViewDataSource,
                    fullListOfGroupMembersViewDataSource: any FullListOfGroupMembersViewDataSource,
                    singleContactViewDataSources: ObvSingleContactView.DataSources,
                    listOfCommonGroupsWithContactViewDataSources: ObvListOfCommonGroupsWithContactView.DataSources,
                    singleGroupV1MainViewDataSources: SingleGroupV1MainView.DataSources,
                    singleGroupV2MainViewSubDataSources: SingleGroupV2MainView.SubDataSources,
                    listOfMembersWithAddAndRemoveButtonsViewDataSources: ListOfMembersWithAddAndRemoveButtonsView.DataSources,
                    listOfMembersWithSegmentedControlViewDataSources: ListOfMembersWithSegmentedControlView.DataSources,
                    fullListOfGroupMembersViewSubDataSources: FullListOfGroupMembersView.SubDataSources,
                    presentedNavigationStackDataSources: ObvPresentedNavigationStack.DataSources) {
            self.listOfContactDevicesViewDataSource = listOfContactDevicesViewDataSource
            self.trustOriginsListViewDataSource = trustOriginsListViewDataSource
            self.singleGroupV2MainViewDataSource = singleGroupV2MainViewDataSource
            self.onetoOneInvitableGroupMembersViewDataSource = onetoOneInvitableGroupMembersViewDataSource
            self.onetoOneInvitableGroupMembersViewCellDataSource = onetoOneInvitableGroupMembersViewCellDataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.fullListOfGroupMembersViewDataSource = fullListOfGroupMembersViewDataSource
            self.singleContactViewDataSources = singleContactViewDataSources
            self.listOfCommonGroupsWithContactViewDataSources = listOfCommonGroupsWithContactViewDataSources
            self.singleGroupV1MainViewDataSources = singleGroupV1MainViewDataSources
            self.singleGroupV2MainViewSubDataSources = singleGroupV2MainViewSubDataSources
            self.listOfMembersWithAddAndRemoveButtonsViewDataSources = listOfMembersWithAddAndRemoveButtonsViewDataSources
            self.listOfMembersWithSegmentedControlViewDataSources = listOfMembersWithSegmentedControlViewDataSources
            self.fullListOfGroupMembersViewSubDataSources = fullListOfGroupMembersViewSubDataSources
            self.presentedNavigationStackDataSources = presentedNavigationStackDataSources
        }
        
    }
    
}


// Public API

extension ObvAppNavigationRouter {
    
    public func pushSingleContactViewController(contactIdentifier: ObvContactIdentifier) {
        self.userWantsToShowSingleContactView(contactIdentifier: contactIdentifier)
    }
    
    public func pushSingleGroupViewController(groupIdentifier: ObvGroupIdentifier) {
        self.userWantsToShowSingleGroupView(groupIdentifier: groupIdentifier)
    }
    
    public func presentNavigationStack(root: ObvPresentedNavigationStack.NavigationStackRootView, on presentingViewController: UIViewController) {
        
        let rootView = ObvPresentedNavigationStack(
            root: root,
            dataSources: dataSources.presentedNavigationStackDataSources,
            actions: actions,
            navigation: self,
            uiKitDelegateForSwiftUISheet: self)

        let vcToPresent = UIHostingController(rootView: rootView)

        currentlyPresentingViewController = presentingViewController
        while let vc = currentlyPresentingViewController?.presentedViewController {
            currentlyPresentingViewController = vc
        }
        
        currentlyPresentingViewController?.present(vcToPresent, animated: true)

    }
    
}


// MARK: - Implementing UIKitDelegateForSwiftUISheet

extension ObvAppNavigationRouter: UIKitDelegateForSwiftUISheet {
    
    public func userWantsToPresentView<Content>(_ view: some View, content: @escaping () -> Content) async where Content : View {
        let hostingController = UIHostingController(rootView: content())
        if let currentlyPresentingViewController {
            // We are in the case where the navigation stack itself is presented.
            // This happens, e.g., when the presenting the edition view for the group type when the main group view
            // was presented by tapping the title of a discussion.
            await currentlyPresentingViewController.presentOnTopAndAwaitCompletion(hostingController, animated: true)
        } else {
            // We are in the case where nothing should be presented at this point.
            // This happens, e.g., when presenting the edition view for the group type when the main group view
            // is pushed on one of the flows.
            if let presentedViewController = navigationController.presentedViewController {
                await presentedViewController.dismissAndAwaitCompletion(animated: true)
            }
            await navigationController.presentOnTopAndAwaitCompletion(hostingController, animated: true)
        }
    }
    
    public func userWantsToDismissPresentedView(_ view: some View) {
        let currentlyPresentingViewController = currentlyPresentingViewController ?? navigationController
        currentlyPresentingViewController.presentedViewController?.dismiss(animated: true)
    }
    
}


// MARK: - Implementing navigation

extension ObvAppNavigationRouter: ObvPresentedNavigationStackNavigation {
    
    public func userWantsToNavigateToOneToOneDiscussionWithContact(_ view: ObvPresentedNavigationStack, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        currentlyPresentingViewController?.dismiss(animated: true)
        currentlyPresentingViewController = nil
        try navigation.userWantsToNavigateToOneToOneDiscussionWithContact(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToNavigateToGroupDiscussion(_ view: ObvPresentedNavigationStack, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        currentlyPresentingViewController?.dismiss(animated: true)
        currentlyPresentingViewController = nil
        navigation.userWantsToNavigateToGroupDiscussion(self, groupIdentifier: groupIdentifier)
    }
    
    public func userWantsToCallContact(_ view: ObvPresentedNavigationStack, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        if let currentlyPresentingViewController {
            currentlyPresentingViewController.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.currentlyPresentingViewController = nil
                navigation.userWantsToCallContact(self, contactIdentifier: contactIdentifier)
            }
        } else {
            navigation.userWantsToCallContact(self, contactIdentifier: contactIdentifier)
        }
    }
    
    public func userWantsToCall(_ view: ObvPresentedNavigationStack, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        if let currentlyPresentingViewController {
            currentlyPresentingViewController.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.currentlyPresentingViewController = nil
                navigation.userWantsToCall(self, groupIdentifier: groupIdentifier)
            }
        } else {
            navigation.userWantsToCall(self, groupIdentifier: groupIdentifier)
        }
    }
    
    public func userWantsToEditContactNicknameAndCustomPicture(_ view: ObvPresentedNavigationStack, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        currentlyPresentingViewController?.dismiss(animated: true)
        currentlyPresentingViewController = nil
        navigation.userWantsToEditContactNicknameAndCustomPicture(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToEditGroupNicknameAndCustomPicture(_ view: ObvPresentedNavigationStack, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        currentlyPresentingViewController?.dismiss(animated: true)
        currentlyPresentingViewController = nil
        navigation.userWantsToEditGroupNicknameAndCustomPicture(self, groupIdentifier: groupIdentifier)
    }
    
    public func userWantsToIntroduceOneContactToAnother(_ view: ObvPresentedNavigationStack, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        currentlyPresentingViewController?.dismiss(animated: true)
        currentlyPresentingViewController = nil
        try navigation.userWantsToIntroduceOneContactToAnother(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToCreateNewGroupWithContact(_ view: ObvPresentedNavigationStack, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        currentlyPresentingViewController?.dismiss(animated: true)
        currentlyPresentingViewController = nil
        try await navigation.userWantsToCreateNewGroupWithContact(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToCloneGroup(_ view: ObvPresentedNavigationStack, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async throws {
        await currentlyPresentingViewController?.dismissAndAwaitCompletion(animated: true)
        currentlyPresentingViewController = nil
        try await navigation.userWantsToCloneGroup(self, groupIdentifier: groupIdentifier)
    }
    
    public func userWantsToDismissPresentedNavigationStack(_ view: ObvPresentedNavigationStack) {
        currentlyPresentingViewController?.dismiss(animated: true)
        currentlyPresentingViewController = nil
    }
        
}

extension ObvAppNavigationRouter: ObvSingleContactViewNavigation {
    
    public func userWantsToNavigateToListOfContactDevices(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        if let vc = navigationController.viewControllers.first(where: { ($0 as? ObvListOfContactDevicesViewController)?.contactIdentifier == contactIdentifier }) {
            navigationController.popToViewController(vc, animated: true)
        } else {
            let vc = ObvListOfContactDevicesViewController(
                contactIdentifier: contactIdentifier,
                dataSource: dataSources.listOfContactDevicesViewDataSource,
                actions: actions)
            self.navigationController.pushViewController(vc, animated: true)
        }
    }
    
    public func userWantsToNavigateToListOfTrustOrigins(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        if let vc = navigationController.viewControllers.first(where: { ($0 as? ObvTrustOriginsListViewController)?.contactIdentifier == contactIdentifier }) {
            navigationController.popToViewController(vc, animated: true)
        } else {
            let vc = ObvTrustOriginsListViewController(
                contactIdentifier: contactIdentifier,
                dataSource: dataSources.trustOriginsListViewDataSource)
            self.navigationController.pushViewController(vc, animated: true)
        }
    }
    
    public func userWantsToNavigateToOneToOneDiscussionWithContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        try navigation.userWantsToNavigateToOneToOneDiscussionWithContact(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToIntroduceOneContactToAnother(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        try navigation.userWantsToIntroduceOneContactToAnother(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToCallContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        navigation.userWantsToCallContact(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToNavigateToListOfCommonGroupsWithContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        if let vc = navigationController.viewControllers.first(where: { ($0 as? ObvListOfCommonGroupsWithContactViewController)?.contactIdentifier == contactIdentifier }) {
            navigationController.popToViewController(vc, animated: true)
        } else {
            let vc = ObvListOfCommonGroupsWithContactViewController(
                contactIdentifier: contactIdentifier,
                dataSources: dataSources.listOfCommonGroupsWithContactViewDataSources,
                navigation: self)
            self.navigationController.pushViewController(vc, animated: true)
        }
        
    }
    
    public func userWantsToCreateNewGroupWithContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        try await navigation.userWantsToCreateNewGroupWithContact(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToEditContactNicknameAndCustomPicture(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        navigation.userWantsToEditContactNicknameAndCustomPicture(self, contactIdentifier: contactIdentifier)
    }
    
}


extension ObvAppNavigationRouter: ObvListOfCommonGroupsWithContactViewNavigation {
    
    public func userDidPressOnObvGroupCellView(_ view: ObvCells.ObvGroupCellView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, expectedNavigation: ObvCells.ObvGroupCellView.ExpectedNavigation) throws {
        switch expectedNavigation {
        case .groupDiscussion:
            navigation.userWantsToNavigateToGroupDiscussion(self, groupIdentifier: groupIdentifier)
        case .groupDetails:
            self.userWantsToShowSingleGroupView(groupIdentifier: groupIdentifier)
        }
    }
    
}


extension ObvAppNavigationRouter: SingleGroupV1MainViewNavigation {
    
    public func userWantsToNavigateToViewAllowingToModifyMembers(_ view: ObvUIGroupV1.SingleGroupV1MainView, groupIdentifier: ObvTypes.ObvGroupV1Identifier) async {
        userWantsToNavigateToViewAllowingToModifyMembers(groupIdentifier: .groupV1(groupIdentifier))
    }
    
    public func userWantsToChat(_ view: ObvUIGroupV1.SingleGroupV1MainView, groupIdentifier: ObvTypes.ObvGroupV1Identifier) async {
        navigation.userWantsToNavigateToGroupDiscussion(self, groupIdentifier: .groupV1(groupIdentifier))
    }
    
    public func userWantsToCall(_ view: ObvUIGroupV1.SingleGroupV1MainView, groupIdentifier: ObvTypes.ObvGroupV1Identifier) {
        navigation.userWantsToCall(self, groupIdentifier: .groupV1(groupIdentifier))
    }
    
    public func userWantsToLeaveGroupFlow(_ view: ObvUIGroupV1.SingleGroupV1MainView) {
        // We do nothing
    }
    
    public func userWantsToEditGroupNicknameAndCustomPicture(_ view: ObvUIGroupV1.SingleGroupV1MainView, groupIdentifier: ObvTypes.ObvGroupV1Identifier) {
        navigation.userWantsToEditGroupNicknameAndCustomPicture(self, groupIdentifier: .groupV1(groupIdentifier))
    }
    
    public func userWantsToCloneGroup(_ view: ObvUIGroupV1.SingleGroupV1MainView, groupIdentifier: ObvTypes.ObvGroupV1Identifier) async throws {
        try await navigation.userWantsToCloneGroup(self, groupIdentifier: .groupV1(groupIdentifier))
    }
    
    public func userWantsToNavigateToFullListOfOtherGroupMembers(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async {
        if let vc = navigationController.viewControllers.first(where: { ($0 as? ListOfMembersWithSegmentedControlViewController)?.groupIdentifier == groupIdentifier }) {
            navigationController.popToViewController(vc, animated: true)
        } else {
            let vc = ListOfMembersWithSegmentedControlViewController(
                groupIdentifier: groupIdentifier,
                dataSources: dataSources.listOfMembersWithSegmentedControlViewDataSources,
                actions: actions,
                navigation: self)
            self.navigationController.pushViewController(vc, animated: true)
        }
    }
    
    public func userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(_ view: ObvUIGroupSharedBetweenV1AndV2.OneToOneInvitableView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        if let vc = navigationController.viewControllers.first(where: { ($0 as? OnetoOneInvitableGroupMembersViewController)?.groupIdentifier == groupIdentifier }) {
            navigationController.popToViewController(vc, animated: true)
        } else {
            let vc = OnetoOneInvitableGroupMembersViewController(
                groupIdentifier: groupIdentifier,
                dataSource: dataSources.onetoOneInvitableGroupMembersViewDataSource,
                onetoOneInvitableGroupMembersViewCellDataSource: dataSources.onetoOneInvitableGroupMembersViewCellDataSource,
                avatarViewDataSource: dataSources.avatarViewDataSource,
                actions: actions)
            self.navigationController.pushViewController(vc, animated: true)
        }
    }
    
    public func userWantsToShowOtherUserProfile(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.InternalView, contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        self.userWantsToShowSingleContactView(contactIdentifier: contactIdentifier)
    }
    
    
}


extension ObvAppNavigationRouter: SingleGroupV2MainViewNavigation {
    
    public func userWantsToChat(_ view: ObvUIGroupV2.SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        navigation.userWantsToNavigateToGroupDiscussion(self, groupIdentifier: .groupV2(groupIdentifier))
    }
    
    public func userWantsToCall(_ view: ObvUIGroupV2.SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        navigation.userWantsToCall(self, groupIdentifier: .groupV2(groupIdentifier))
    }
    
    public func userWantsToLeaveGroupFlow(_ view: ObvUIGroupV2.SingleGroupV2MainView) {
        // We do nothing
    }
    
    public func userWantsToEditGroupNicknameAndCustomPicture(_ view: ObvUIGroupV2.SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        navigation.userWantsToEditGroupNicknameAndCustomPicture(self, groupIdentifier: .groupV2(groupIdentifier))
    }
    
    public func userWantsToCloneGroup(_ view: ObvUIGroupV2.SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws {
        try await navigation.userWantsToCloneGroup(self, groupIdentifier: .groupV2(groupIdentifier))
    }
    
    public func userWantsToNavigateToViewAllowingToModifyMembers(_ view: ObvUIGroupV2.GroupAdministrationView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        self.userWantsToNavigateToViewAllowingToModifyMembers(groupIdentifier: .groupV2(groupIdentifier))
    }
    
    public func userWantsToNavigateToViewAllowingToManageAdmins(_ view: ObvUIGroupV2.GroupAdministrationView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        let vc = FullListOfGroupMembersViewController(
            mode: .editAdmins(groupIdentifier: groupIdentifier,
                              selectedGroupType: nil,
                              navigation: self,
                              actions: actions),
            dataSource: dataSources.fullListOfGroupMembersViewDataSource,
            subDataSources: dataSources.fullListOfGroupMembersViewSubDataSources,
            uiKitDelegateForSwiftUISheet: self)
        navigationController.pushViewController(vc, animated: true)
    }
    
    
}

extension ObvAppNavigationRouter: ListOfMembersWithAddAndRemoveButtonsViewNavigation {
    // Other protocol implementations are enough
}

extension ObvAppNavigationRouter: ListOfMembersWithSegmentedControlViewNavigation {
    // Other protocol implementations are enough
}

extension ObvAppNavigationRouter: FullListOfGroupMembersViewNavigationDuringEdition {
    
    public func hudWasDismissedAfterSuccessfulGroupEdition(_ view: ObvUIGroupV2.FullListOfGroupMembersView.InternalView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        // We do nothing
    }
    
}

// MARK: - Private helpers

extension ObvAppNavigationRouter {
    
    public func userWantsToNavigateToViewAllowingToModifyMembers(groupIdentifier: ObvGroupIdentifier) {
        if let vc = navigationController.viewControllers.first(where: { ($0 as? ListOfMembersWithAddAndRemoveButtonsViewController)?.groupIdentifier == groupIdentifier }) {
            navigationController.popToViewController(vc, animated: true)
        } else {
            let vc = ListOfMembersWithAddAndRemoveButtonsViewController(
                groupIdentifier: groupIdentifier,
                dataSources: dataSources.listOfMembersWithAddAndRemoveButtonsViewDataSources,
                actions: actions,
                navigation: self,
                uiKitDelegateForSwiftUISheet: self)
            self.navigationController.pushViewController(vc, animated: true)
        }
    }
    
    private func userWantsToShowSingleContactView(contactIdentifier: ObvTypes.ObvContactIdentifier) {
        
        let navigationControllerToUse: UINavigationController
        if let presentedNavigationController = self.navigationController.presentedViewController as? UINavigationController {
            navigationControllerToUse = presentedNavigationController
        } else {
            self.navigationController.dismiss(animated: true)
            navigationControllerToUse = self.navigationController
        }
        
        if let vc = navigationControllerToUse.viewControllers.first(where: { ($0 as? ObvSingleContactViewController)?.contactIdentifier == contactIdentifier }) {
            navigationControllerToUse.popToViewController(vc, animated: true)
        } else {
            let vc = ObvSingleContactViewController(
                contactIdentifier: contactIdentifier,
                dataSources: dataSources.singleContactViewDataSources,
                actions: actions,
                navigation: self,
                uiKitDelegateForSwiftUISheet: self)
            navigationControllerToUse.pushViewController(vc, animated: true)
        }
    }
    
    private func userWantsToShowSingleGroupView(groupIdentifier: ObvGroupIdentifier) {
        switch groupIdentifier {
        case .groupV1(let groupV1Identifier):
            if let vc = navigationController.viewControllers.first(where: { ($0 as? SingleGroupV1MainViewController)?.groupIdentifier == groupV1Identifier }) {
                navigationController.popToViewController(vc, animated: true)
            } else {
                let vc = SingleGroupV1MainViewController(
                    groupIdentifier: groupV1Identifier,
                    dataSources: dataSources.singleGroupV1MainViewDataSources,
                    actions: actions,
                    navigation: self,
                    uiKitDelegateForSwiftUISheet: self)
                self.navigationController.pushViewController(vc, animated: true)
            }
        case .groupV2(let groupV2Identifier):
            if let vc = navigationController.viewControllers.first(where: { ($0 as? SingleGroupV2MainViewController)?.groupIdentifier == groupV2Identifier }) {
                navigationController.popToViewController(vc, animated: true)
            } else {
                let vc = SingleGroupV2MainViewController(
                    groupIdentifier: groupV2Identifier,
                    dataSource: dataSources.singleGroupV2MainViewDataSource,
                    subDataSources: dataSources.singleGroupV2MainViewSubDataSources,
                    actions: actions,
                    navigation: self,
                    uiKitDelegateForSwiftUISheet: self)
                self.navigationController.pushViewController(vc, animated: true)
            }
        }
    }

}
