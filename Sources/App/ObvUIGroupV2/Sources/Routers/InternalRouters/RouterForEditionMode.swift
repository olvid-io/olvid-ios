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
import ObvTypes
import ObvAppTypes
import ObvDesignSystem


@MainActor
public protocol ObvUIGroupV2RouterDelegateForEdition: AnyObject {
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ router: ObvUIGroupV2Router, publishedDetails: PublishedDetailsValidationViewModel) async throws
    func userWantsToLeaveGroup(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws
    func userWantsToDisbandGroup(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws
    func userWantsToChat(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async
    func userWantsToCall(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async
    func userWantsToRemoveOtherUserFromGroup(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    func userWantsToUpdateGroupV2(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws
    func userWantsObtainAvatarDuringGroupEdition(_ router: ObvUIGroupV2Router, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    func userWantsToSaveImageToTempFileDuringGroupEdition(_ router: ObvUIGroupV2Router, image: UIImage) async throws -> URL
    func userWantsToInviteOtherUserToOneToOne(_ router: ObvUIGroupV2Router, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    func userWantsToInviteOtherUserToOneToOne(_ router: ObvUIGroupV2Router, contactIdentifiers: [ObvTypes.ObvContactIdentifier]) async throws
    func userWantsToCancelOneToOneInvitationSent(_ router: ObvUIGroupV2Router, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    func userWantsToShowOtherUserProfile(_ router: ObvUIGroupV2Router, navigationController: UINavigationController, contactIdentifier: ObvTypes.ObvContactIdentifier) async
    func userWantsToUpdatePersonalNote(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier, with newText: String?) async
    func userWantsToEditGroupNicknameAndCustomPicture(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier)
    func userWantsToCloneGroup(_ router: ObvUIGroupV2Router, valuesOfGroupToClone: ObvUIGroupV2Router.ValuesOfClonedGroup)
    func userTappedOnManualResyncOfGroupV2Button(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier) async throws
}


@MainActor
final class RouterForEditionMode {
        
    weak var parentRouter: ObvUIGroupV2Router?
    
    private let dataSource: ObvUIGroupV2RouterDataSource // Strong pointer to the dataSource
    private weak var delegate: ObvUIGroupV2RouterDelegateForEdition?

    init(dataSource: ObvUIGroupV2RouterDataSource, delegate: ObvUIGroupV2RouterDelegateForEdition) {
        self.dataSource = dataSource
        self.delegate = delegate
    }
 
    
    func pushOrPopInitialViewController(navigationController: UINavigationController, groupIdentifier: ObvGroupV2Identifier) {
        if let vc = navigationController.viewControllers.last(where: {
            guard let vc = $0 as? SingleGroupV2MainViewController else { return false }
            return vc.groupIdentifier == groupIdentifier
        }) {
            navigationController.popToViewController(vc, animated: true)
        } else {
            let vc = getInitialViewControllerForGroupEdition(groupIdentifier: groupIdentifier)
            // For some reason, pushing the view controller does not always work, so we "set" the view controllers
            navigationController.pushViewController(vc, animated: true)
        }
    }
    
    func getInitialViewControllerForGroupEdition(groupIdentifier: ObvGroupV2Identifier) -> UIViewController {
        let vc = SingleGroupV2MainViewController(groupIdentifier: groupIdentifier,
                                                delegate: self,
                                                dataSource: self)
        return vc
    }

    func removeFromNavigationAllViewControllersRelatingToGroup(navigationController: UINavigationController, groupIdentifier: ObvGroupV2Identifier) {
        var newViewController = [UIViewController]()
        for vc in navigationController.viewControllers {
            if let vc = vc as? EditGroupNameAndPictureViewController, vc.groupIdentifier == groupIdentifier {
                break // Remove the view controller from the stack
            } else if let vc = vc as? EditGroupTypeViewController, vc.groupIdentifier == groupIdentifier {
                break // Remove the view controller from the stack
            } else if let vc = vc as? FullListOfGroupMembersViewController, vc.groupIdentifier == groupIdentifier {
                break // Remove the view controller from the stack
            } else if let vc = vc as? SingleGroupV2MainViewController, vc.groupIdentifier == groupIdentifier {
                break // Remove the view controller from the stack
            } else if let vc = vc as? OnetoOneInvitableGroupMembersViewController, vc.groupIdentifier == groupIdentifier {
                break // Remove the view controller from the stack
            } else if let vc = vc as? SelectUsersToAddViewController, vc.groupIdentifier == groupIdentifier {
                break // Remove the view controller from the stack
            } else {
                newViewController += [vc]
            }
        }
        guard !newViewController.isEmpty else { return } // This sometimes happen. Setting an empty stack of view controllers on the naviation freezes it.
        if navigationController.viewControllers != newViewController {
            navigationController.setViewControllers(newViewController, animated: true)
        }
    }
    
}


// MARK: - Implementing SingleGroupV2MainViewControllerDelegate

extension RouterForEditionMode: SingleGroupV2MainViewControllerDelegate {
    
    func userWantsToLeaveGroup(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        try await delegate.userWantsToLeaveGroup(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToDisbandGroup(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        try await delegate.userWantsToDisbandGroup(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToChat(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        await delegate.userWantsToChat(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToCall(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        await delegate.userWantsToCall(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ vc: SingleGroupV2MainViewController, publishedDetails: PublishedDetailsValidationViewModel) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        try await delegate.userWantsToReplaceTrustedDetailsByPublishedDetails(parentRouter, publishedDetails: publishedDetails)
    }
    
    func userWantsToNavigateToFullListOfOtherGroupMembers(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        let vcToPush = FullListOfGroupMembersViewController(mode: .listMembers(groupIdentifier: groupIdentifier), dataSource: self, delegate: self)
        vc.navigationController?.pushViewController(vcToPush, animated: true)
    }
    
    func userWantsToNavigateToViewAllowingToModifyMembers(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        let vcToPush = FullListOfGroupMembersViewController(mode: .listMembers(groupIdentifier: groupIdentifier), dataSource: self, delegate: self)
        vc.navigationController?.pushViewController(vcToPush, animated: true)
    }
    
    func userWantsToNavigateToViewAllowingToSelectGroupTypes(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) async {
        let vcToPresent = EditGroupTypeViewController(mode: .edition(groupIdentifier: groupIdentifier),
                                                      dataSource: self,
                                                      delegate: self)
        let nav = UINavigationController(rootViewController: vcToPresent)
        vc.present(nav, animated: true)
    }
    
    func userWantsToNavigateToViewAllowingToEditGroupName(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) async {
        let vcToPresent = EditGroupNameAndPictureViewController(mode: .edition(groupIdentifier: groupIdentifier),
                                                                dataSource: self,
                                                                delegate: self)
        let nav = UINavigationController(rootViewController: vcToPresent)
        vc.present(nav, animated: true)
    }
    
    func userWantsToNavigateToViewAllowingToManageAdmins(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) async {
        let vcToPresent = FullListOfGroupMembersViewController(mode: .editAdmins(groupIdentifier: groupIdentifier, selectedGroupType: nil), dataSource: self, delegate: self)
        let nav = UINavigationController(rootViewController: vcToPresent)
        vc.present(nav, animated: true)
    }
    
    func userWantsToInviteOtherUserToOneToOne(_ vc: SingleGroupV2MainViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        try await delegate.userWantsToInviteOtherUserToOneToOne(parentRouter, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToShowOtherUserProfile(_ vc: SingleGroupV2MainViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        guard let navigationController = vc.navigationController else { assertionFailure(); return }
        await delegate.userWantsToShowOtherUserProfile(parentRouter, navigationController: navigationController, contactIdentifier: contactIdentifier)
    }
    
    
    func userWantsToRemoveOtherUserFromGroup(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        try await userWantsToRemoveOtherUserFromGroup(groupIdentifier: groupIdentifier, contactIdentifier: contactIdentifier)
    }
    
    
    func userWantsToLeaveGroupFlow(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        guard let navigationController = vc.navigationController else {
            // This happens when we are removed from a group while in one of the group's views.
            // In that case, we remove the views from the navigation, reason why it is nil here.
            return
        }
        userWantsToLeaveGroupFlow(navigationController: navigationController, groupIdentifier: groupIdentifier)
    }
 
    
    func userWantsToUpdatePersonalNote(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier, with newText: String?) async {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        await delegate.userWantsToUpdatePersonalNote(parentRouter, groupIdentifier: groupIdentifier, with: newText)
    }
    
    
    func userWantsToEditGroupNicknameAndCustomPicture(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) {
        // We do not implement the views allowing to change the custom photo and nickname of a group in this module.
        // Instead, we leverage the existing implementation at the app level
        guard let parentRouter, let delegate else { assertionFailure(); return }
        delegate.userWantsToEditGroupNicknameAndCustomPicture(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    
    func userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) {
        let vcToPush = OnetoOneInvitableGroupMembersViewController(groupIdentifier: groupIdentifier, dataSource: self, delegate: self)
        vc.navigationController?.pushViewController(vcToPush, animated: true)
    }
    
    
    func userWantsToCloneGroup(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        let valuesOfGroupToClone = try await dataSource.getValuesOfGroupToClone(parentRouter, identifierOfGroupToClone: groupIdentifier)
        delegate.userWantsToCloneGroup(parentRouter, valuesOfGroupToClone: valuesOfGroupToClone)
    }
    
    
    func userTappedOnManualResyncOfGroupV2Button(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        try await delegate.userTappedOnManualResyncOfGroupV2Button(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    
    /// This can be called from the main group view, when the group is empty. In this case (and in this case only), we show a button allowing to add the first other members in the group.
    func userWantsToNavigateToViewAllowingToAddGroupMembers(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) {
        let vcToPresent = SelectUsersToAddViewController(mode: .edition(groupIdentifier: groupIdentifier), dataSource: self, delegate: self)
        let nav = UINavigationController(rootViewController: vcToPresent)
        vc.navigationController?.present(nav, animated: true)
    }
    
}


// MARK: - Private helpers for implementing SingleGroupV2MainViewControllerDelegate

extension RouterForEditionMode {
    
    private func userWantsToRemoveOtherUserFromGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        try await delegate.userWantsToRemoveOtherUserFromGroup(parentRouter, groupIdentifier: groupIdentifier, contactIdentifier: contactIdentifier)
    }

    
    private func userWantsToLeaveGroupFlow(navigationController: UINavigationController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        if navigationController.presentingViewController != nil {
            // If we are presented, just dismiss
            navigationController.dismiss(animated: true)
        } else {
            // Pop to the view controller preceeding the first SingleGroupV2MainViewController concerning the group
            removeFromNavigationAllViewControllersRelatingToGroup(navigationController: navigationController, groupIdentifier: groupIdentifier)
        }
    }

}


// MARK: - Implementing EditGroupTypeViewControllerDelegate

extension RouterForEditionMode: EditGroupTypeViewControllerDelegate {
        
    func userWantsToCancelAndDismiss(_ vc: EditGroupTypeViewController) {
        vc.dismiss(animated: true)
    }
    
    func userWantsToLeaveGroupFlow(_ vc: EditGroupTypeViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        vc.dismiss(animated: true)
    }
    
    func userWantsToUpdateGroupV2(_ vc: EditGroupTypeViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.userWantsToUpdateGroupV2(parentRouter, groupIdentifier: groupIdentifier, changeset: changeset)
    }
    
    func userChosedGroupTypeAndWantsToSelectAdmins(_ vc: EditGroupTypeViewController, groupIdentifier: ObvGroupV2Identifier, selectedGroupType: ObvGroupType) {
        guard let nav = vc.navigationController else { assertionFailure(); return }
        let vc = FullListOfGroupMembersViewController(mode: .editAdmins(groupIdentifier: groupIdentifier, selectedGroupType: selectedGroupType),
                                                      dataSource: self,
                                                      delegate: self)
        nav.pushViewController(vc, animated: true)
    }
    
    func userChosedGroupTypeDuringGroupCreation(_ vc: EditGroupTypeViewController, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, selectedGroupType: ObvAppTypes.ObvGroupType) {
        assertionFailure("Not expected to be called during a group edition")
    }

}



// MARK: - Implementing EditGroupNameAndPictureViewControllerDelegate

extension RouterForEditionMode: EditGroupNameAndPictureViewControllerDelegate {
            
    func userWantsToLeaveGroupFlow(_ vc: EditGroupNameAndPictureViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        guard let navigationController = vc.navigationController else { assertionFailure(); return }
        userWantsToLeaveGroupFlow(navigationController: navigationController, groupIdentifier: groupIdentifier)
    }
    
    func userWantsObtainAvatar(_ vc: EditGroupNameAndPictureViewController, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.userWantsObtainAvatarDuringGroupEdition(parentRouter, avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    func userWantsToSaveImageToTempFile(_ vc: EditGroupNameAndPictureViewController, image: UIImage) async throws -> URL {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.userWantsToSaveImageToTempFileDuringGroupEdition(parentRouter, image: image)
    }
    
    func userWantsToUpdateGroupV2(_ vc: EditGroupNameAndPictureViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.userWantsToUpdateGroupV2(parentRouter, groupIdentifier: groupIdentifier, changeset: changeset)
    }

    func userWantsToCancelAndDismiss(_ vc: EditGroupNameAndPictureViewController) {
        vc.dismiss(animated: true)
    }
    
    func groupDetailsWereSuccessfullyUpdated(_ vc: EditGroupNameAndPictureViewController, groupIdentifier: ObvGroupV2Identifier) {
        vc.dismiss(animated: true)
    }
    
    func userWantsToPublishCreatedGroupWithDetails(_ vc: EditGroupNameAndPictureViewController, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails) async throws {
        assertionFailure("Not expected to be called during a group edition")
        throw ObvError.unexpectedDuringGroupEdition
    }
    
    func groupWasSuccessfullyCreated(_ vc: EditGroupNameAndPictureViewController, ownedCryptoId: ObvTypes.ObvCryptoId) {
        assertionFailure("Not expected to be called during a group edition")
    }

}


// MARK: - Implementing FullListOfGroupMembersViewControllerDelegate

extension RouterForEditionMode: FullListOfGroupMembersViewControllerDelegate {
        
    func userWantsToNavigateToViewAllowingToAddGroupMembers(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        let vcToPresent = SelectUsersToAddViewController(mode: .edition(groupIdentifier: groupIdentifier), dataSource: self, delegate: self)
        let nav = UINavigationController(rootViewController: vcToPresent)
        vc.navigationController?.present(nav, animated: true)
    }

    func userWantsToUpdateGroupV2(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        try await delegate.userWantsToUpdateGroupV2(parentRouter, groupIdentifier: groupIdentifier, changeset: changeset)
    }
    
    func userWantsToNavigateToViewAllowingToRemoveGroupMembers(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        let vcToPresent = FullListOfGroupMembersViewController(mode: .removeMembers(groupIdentifier: groupIdentifier), dataSource: self, delegate: self)
        let nav = UINavigationController(rootViewController: vcToPresent)
        vc.navigationController?.present(nav, animated: true)
    }
    
    func groupMembersWereSuccessfullyRemovedFromGroup(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvGroupV2Identifier) {
        vc.navigationController?.presentedViewController?.dismiss(animated: true)
    }
    
    
    func userWantsToCancelAndDismiss(_ vc: FullListOfGroupMembersViewController) {
        vc.dismiss(animated: true)
    }

    
    func hudWasDismissedAfterSuccessfulGroupEdition(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvGroupV2Identifier) {
        vc.dismiss(animated: true)
    }
    
    
    func userWantsToInviteOtherUserToOneToOne(_ vc: FullListOfGroupMembersViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        try await delegate.userWantsToInviteOtherUserToOneToOne(parentRouter, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToShowOtherUserProfile(_ vc: FullListOfGroupMembersViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        guard let navigationController = vc.navigationController else { assertionFailure(); return }
        await delegate.userWantsToShowOtherUserProfile(parentRouter, navigationController: navigationController, contactIdentifier: contactIdentifier)
    }
    
    
    func userWantsToRemoveMembersFromGroup(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, membersToRemove: Set<SingleGroupMemberViewModelIdentifier>) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }

        guard !membersToRemove.isEmpty else { return }
        
        var changes = Set<ObvGroupV2.Change>()
        
        for userIdentifier in membersToRemove {
            
            let obvContactIdentifier = try await dataSource.getContactIdentifierOfGroupMember(parentRouter, contactIdentifier: userIdentifier)
            
            guard obvContactIdentifier.ownedCryptoId == groupIdentifier.ownedCryptoId else {
                assertionFailure()
                throw ObvError.unexpectedOwnedIdentity
            }
            
            changes.insert(.memberRemoved(contactCryptoId: obvContactIdentifier.contactCryptoId))
            
        }
        
        guard !changes.isEmpty else { return }
        
        let changeset = try ObvGroupV2.Changeset(changes: changes)
        
        try await delegate.userWantsToUpdateGroupV2(parentRouter, groupIdentifier: groupIdentifier, changeset: changeset)
    }

    
    func userWantsToRemoveOtherUserFromGroup(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        try await userWantsToRemoveOtherUserFromGroup(groupIdentifier: groupIdentifier, contactIdentifier: contactIdentifier)
    }
        
    
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(_ vc: FullListOfGroupMembersViewController, creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool) {
        assertionFailure("Not expected to be called during a group edition")
        return
    }

    
    func userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(_ vc: FullListOfGroupMembersViewController, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId) {
        assertionFailure("Not expected to be called during a group edition")
        return
    }
    
}


// MARK: - Implementing SelectUsersToAddViewControllerDelegate

extension RouterForEditionMode: SelectUsersToAddViewControllerDelegate {
        
    func userWantsToCancelAndDismiss(_ vc: SelectUsersToAddViewController) {
        vc.dismiss(animated: true)
    }
    
    func viewShouldBeDismissed(_ vc: SelectUsersToAddViewController) {
        vc.dismiss(animated: true)
    }
    
    func userWantsToAddSelectedUsersToExistingGroup(_ vc: SelectUsersToAddViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {
        
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }

        guard !userIdentifiers.isEmpty else { return }
        
        var changes = Set<ObvGroupV2.Change>()
        
        let groupType = try await dataSource.getGroupType(parentRouter, groupIdentifier: groupIdentifier)
        let permissions = ObvGroupType.exactPermissions(of: .regularMember, forGroupType: groupType)
        
        for userIdentifier in userIdentifiers {
            
            let obvContactIdentifier = try await dataSource.getContactIdentifierOfUser(parentRouter, contactIdentifier: userIdentifier)
            
            guard obvContactIdentifier.ownedCryptoId == groupIdentifier.ownedCryptoId else {
                assertionFailure()
                throw ObvError.unexpectedOwnedIdentity
            }
            
            changes.insert(.memberAdded(contactCryptoId: obvContactIdentifier.contactCryptoId, permissions: permissions))
            
        }
        
        guard !changes.isEmpty else { return }
        
        let changeset = try ObvGroupV2.Changeset(changes: changes)
        
        try await delegate.userWantsToUpdateGroupV2(parentRouter, groupIdentifier: groupIdentifier, changeset: changeset)
        
    }
    
    func userWantsToAddSelectedUsersToCreatingGroup(_ vc: SelectUsersToAddViewController, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) {
        assertionFailure("Not expected to be called during a group edition")
        return
    }

}


// MARK: - Implementing OnetoOneInvitableGroupMembersViewControllerDelegate

extension RouterForEditionMode: OnetoOneInvitableGroupMembersViewControllerDelegate {
    
    func userWantsToSendOneToOneInvitationTo(_ vc: OnetoOneInvitableGroupMembersViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        try await delegate.userWantsToInviteOtherUserToOneToOne(parentRouter, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToCancelOneToOneInvitationSentTo(_ vc: OnetoOneInvitableGroupMembersViewController, contactIdentifier: ObvContactIdentifier) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        try await delegate.userWantsToCancelOneToOneInvitationSent(parentRouter, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToSendOneToOneInvitationsTo(_ vc: OnetoOneInvitableGroupMembersViewController, contactIdentifiers: [OnetoOneInvitableGroupMembersViewModel.Identifier]) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); return }
        let contactIdentifiers = try await dataSource.getContactIdentifiers(parentRouter, identifiers: contactIdentifiers)
        try await delegate.userWantsToInviteOtherUserToOneToOne(parentRouter, contactIdentifiers: contactIdentifiers)
    }
    
}


// MARK: - Implementing OnetoOneInvitableGroupMembersViewDataSource

extension RouterForEditionMode: OnetoOneInvitableGroupMembersViewDataSource {
        
    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OnetoOneInvitableGroupMembersViewModel>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(streamUUID: UUID) {
        guard let parentRouter else { assertionFailure(); return }
        dataSource.finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(parentRouter, streamUUID: streamUUID)
    }
    
    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(identifier: OnetoOneInvitableGroupMembersViewModel.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OnetoOneInvitableGroupMembersViewCellModel>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(parentRouter, identifier: identifier)
    }
    
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(identifier: OnetoOneInvitableGroupMembersViewModel.Identifier, streamUUID: UUID) {
        guard let parentRouter else { assertionFailure(); return }
        dataSource.finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(parentRouter, identifier: identifier, streamUUID: streamUUID)
    }

}


// MARK: - Implementing SingleGroupMemberViewDataSource

extension RouterForEditionMode: SingleGroupMemberViewDataSource {
        
    func getAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberViewModel>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfSingleGroupMemberViewModels(parentRouter, memberIdentifier: identifier)
    }
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier, streamUUID: UUID) {
        guard let parentRouter else { return } // No assert as this happens when the group is disbanded
        dataSource.finishAsyncSequenceOfSingleGroupMemberViewModels(parentRouter, memberIdentifier: identifier, streamUUID: streamUUID)
    }
    
    func getAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<GroupLightweightModel>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfGroupLightweightModel(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, streamUUID: UUID) {
        guard let parentRouter else { assertionFailure(); return }
        dataSource.finishAsyncSequenceOfGroupLightweightModel(parentRouter, groupIdentifier: groupIdentifier, streamUUID: streamUUID)
    }

    func fetchAvatarImageForGroupMember(contactIdentifier: ObvTypes.ObvContactIdentifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try await dataSource.fetchAvatarImage(parentRouter, photoURL: photoURL, avatarSize: avatarSize)
    }
    
}


// MARK: - Implementing OwnedIdentityAsGroupMemberViewDataSource

extension RouterForEditionMode: OwnedIdentityAsGroupMemberViewDataSource {
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityAsGroupMemberViewModel>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier, streamUUID: UUID) {
        guard let parentRouter else { assertionFailure(); return }
        dataSource.finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(parentRouter, groupIdentifier: groupIdentifier, streamUUID: streamUUID)
    }
    
    func fetchAvatarImageForOwnedIdentityAsGroupMember(ownedCryptoId: ObvTypes.ObvCryptoId, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try await dataSource.fetchAvatarImage(parentRouter, photoURL: photoURL, avatarSize: avatarSize)
    }
    
}


// MARK: - Implementing ListOfGroupMembersViewDataSource

extension RouterForEditionMode: ListOfGroupMembersViewDataSource {
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfListOfSingleGroupMemberViewModel(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID) {
        guard let parentRouter else { return } // No assert as this happens when disbanding a group
        dataSource.finishAsyncSequenceOfListOfSingleGroupMemberViewModel(parentRouter, streamUUID: streamUUID)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID, searchText: String?) {
        guard let parentRouter else { assertionFailure(); return }
        dataSource.filterAsyncSequenceOfListOfSingleGroupMemberViewModel(parentRouter, streamUUID: streamUUID, searchText: searchText)
    }
    
}


// MARK: - Implementing FullListOfGroupMembersViewDataSource

extension RouterForEditionMode: FullListOfGroupMembersViewDataSource {
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(creationSessionUUID: UUID) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        assertionFailure("Not expected to be called during a group edition")
        throw ObvError.unexpectedDuringGroupEdition
    }
    
    func getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(streamUUID: UUID) {
        guard let parentRouter else { assertionFailure(); return }
        dataSource.finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(parentRouter, streamUUID: streamUUID)
    }

    func getGroupLightweightModelDuringGroupCreation(creationSessionUUID: UUID) throws -> GroupLightweightModel {
        assertionFailure("Not expected to be called during a group edition")
        throw ObvError.unexpectedDuringGroupEdition
    }
    
}


// MARK: - Implementing PublishedDetailsValidationViewDataSource

extension RouterForEditionMode: PublishedDetailsValidationViewDataSource {
    
    func getPublishedPhotoForGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, publishedPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try await dataSource.fetchAvatarImage(parentRouter, photoURL: publishedPhotoURL, avatarSize: avatarSize)
    }
    
}


// MARK: - Implementing SingleGroupV2MainViewDataSource

extension RouterForEditionMode: SingleGroupV2MainViewDataSource {
        
    func getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>) {
        guard let parentRouter else { throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfSingleGroupV2MainViewModel(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: UUID) {
        guard let parentRouter else { return }
        dataSource.finishAsyncSequenceOfSingleGroupV2MainViewModel(parentRouter, streamUUID: streamUUID)
    }
    
    func getTrustedPhotoForGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, trustedPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try await dataSource.fetchAvatarImage(parentRouter, photoURL: trustedPhotoURL, avatarSize: avatarSize)
    }
    
    func getCustomPhotoForGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, customPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try await dataSource.fetchAvatarImage(parentRouter, photoURL: customPhotoURL, avatarSize: avatarSize)
    }
    
    
    /// Allows to show a card dispolaying the number of group members that are
    /// - contacts
    /// - but not one2one yet.
    ///  These are the contacts that the owned identity can invite to a one to one discussion
    func getAsyncSequenceOfOneToOneInvitableViewModel(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OneToOneInvitableViewModel>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfOneToOneInvitableViewModel(parentRouter, groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncSequenceOfOneToOneInvitableViewModel(streamUUID: UUID) {
        guard let parentRouter else { assertionFailure(); return }
        dataSource.finishAsyncSequenceOfOneToOneInvitableViewModel(parentRouter, streamUUID: streamUUID)
    }

}


//MARK: - Implementing EditGroupTypeViewDataSource

extension RouterForEditionMode: EditGroupTypeViewDataSource {
    
    // Already implemented thanks to other data source conformances
    
}


// MARK: - Implementing EditGroupNameAndPictureViewDataSource

extension RouterForEditionMode: EditGroupNameAndPictureViewDataSource {
    
    func getPhotoForGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try await dataSource.fetchAvatarImage(parentRouter, photoURL: photoURL, avatarSize: avatarSize)
    }
    
}


// MARK: - Implementing SelectUsersToAddViewDataSource

extension RouterForEditionMode: SelectUsersToAddViewDataSource {
    
    func getAsyncSequenceOfUsersToAddToCreatingGroup(ownedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        assertionFailure("Not expected to be called during a group edition")
        throw ObvError.unexpectedDuringGroupEdition
    }
    
    func getAsyncSequenceOfUsersToAddToExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfSelectUsersToAddViewModel(parentRouter, mode: .edition(groupIdentifier: groupIdentifier))
    }
    
    
    func finishAsyncSequenceOfSelectUsersToAddViewModel(streamUUID: UUID) {
        guard let parentRouter else { assertionFailure(); return }
        return dataSource.finishAsyncSequenceOfSelectUsersToAddViewModel(parentRouter, streamUUID: streamUUID)
    }
    
    
    func getAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel.User>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfSelectUsersToAddViewModelUser(parentRouter, withIdentifier: identifier)
    }
    
    
    func finishAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier, streamUUID: UUID) {
        guard let parentRouter else { assertionFailure(); return }
        return dataSource.finishAsyncSequenceOfSelectUsersToAddViewModelUser(parentRouter, withIdentifier: identifier, streamUUID: streamUUID)
    }
    
    
    func fetchAvatarImage(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try await dataSource.fetchAvatarImage(parentRouter, photoURL: photoURL, avatarSize: avatarSize)
    }
    
    func filterAsyncSequenceOfUsersToAdd(streamUUID: UUID, searchText: String?) {
        guard let parentRouter else { assertionFailure(); return }
        dataSource.filterAsyncSequenceOfSelectUsersToAddViewModel(parentRouter, streamUUID: streamUUID, searchText: searchText)
    }
    
}


// MARK: - Errors

extension RouterForEditionMode {
    
    enum ObvError: Error {
        case delegateOrParentRouterIsNil
        case dataSourceOrParentRouterIsNil
        case unexpectedOwnedIdentity
        case unexpectedDuringGroupEdition
    }
    
}
