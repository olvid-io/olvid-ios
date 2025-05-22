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


@MainActor
protocol FullListOfGroupMembersViewControllerDelegate: AnyObject {
    func userWantsToNavigateToViewAllowingToAddGroupMembers(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvGroupV2Identifier) async
    func userWantsToNavigateToViewAllowingToRemoveGroupMembers(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvGroupV2Identifier) async
    func userWantsToInviteOtherUserToOneToOne(_ vc: FullListOfGroupMembersViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    func userWantsToShowOtherUserProfile(_ vc: FullListOfGroupMembersViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async
    func userWantsToRemoveOtherUserFromGroup(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    func userWantsToRemoveMembersFromGroup(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvGroupV2Identifier, membersToRemove: Set<SingleGroupMemberViewModelIdentifier>) async throws
    func groupMembersWereSuccessfullyRemovedFromGroup(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvGroupV2Identifier)
    func userWantsToUpdateGroupV2(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws
    func userWantsToCancelAndDismiss(_ vc: FullListOfGroupMembersViewController)
    func hudWasDismissedAfterSuccessfulGroupEdition(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvGroupV2Identifier)
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(_ vc: FullListOfGroupMembersViewController, creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool)
    func userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(_ vc: FullListOfGroupMembersViewController, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId)
}


final class FullListOfGroupMembersViewController: UIHostingController<FullListOfGroupMembersView> {
    
    private let actions = ViewsActions()
    private weak var internalDelegate: FullListOfGroupMembersViewControllerDelegate?
    private let mode: GroupMembersListMode
    
    init(mode: GroupMembersListMode, dataSource: FullListOfGroupMembersViewDataSource, delegate: FullListOfGroupMembersViewControllerDelegate) {
        self.mode = mode
        let rootView = FullListOfGroupMembersView(mode: mode,
                                                  dataSource: dataSource,
                                                  actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        actions.delegate = self
        
        switch self.mode {
        case .listMembers:
            self.title = String(localizedInThisBundle: "TITLE_GROUP_MEMBERS")
        case .removeMembers:
            self.title = String(localizedInThisBundle: "TITLE_REMOVE_GROUP_MEMBERS")
        case .editAdmins:
            self.title = String(localizedInThisBundle: "TITLE_EDIT_GROUP_ADMINS")
        case .selectAdminsDuringGroupCreation:
            self.title = String(localizedInThisBundle: "TITLE_CHOOSE_GROUP_ADMINS")
        }
        
    }
    
    var groupIdentifier: ObvGroupV2Identifier? {
        switch mode {
        case .listMembers(groupIdentifier: let groupIdentifier),
                .removeMembers(groupIdentifier: let groupIdentifier),
                .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _):
            return groupIdentifier
        case .selectAdminsDuringGroupCreation:
            return nil
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let barButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: .init(handler: { [weak self] _ in
                guard let self else { return }
                internalDelegate?.userWantsToCancelAndDismiss(self)
            }),
            menu: nil)
        
        switch self.mode {
        case .listMembers:
            break
        case .editAdmins, .removeMembers:
            if self.isBeingPresented || self.navigationController?.isBeingPresented == true {
                navigationItem.leftBarButtonItem = barButtonItem
            }
        case .selectAdminsDuringGroupCreation:
            navigationItem.rightBarButtonItem = barButtonItem
        }
        
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    enum ObvError: Error {
        case internalDelegateIsNil
    }

}


// MARK: - Implementing FullListOfGroupMembersViewActionsProtocol

extension FullListOfGroupMembersViewController: FullListOfGroupMembersViewActionsProtocol {
    
    func userWantsToAddGroupMembers(groupIdentifier: ObvGroupV2Identifier) async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToNavigateToViewAllowingToAddGroupMembers(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToRemoveGroupMembers(groupIdentifier: ObvGroupV2Identifier) async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToNavigateToViewAllowingToRemoveGroupMembers(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToInviteOtherUserToOneToOne(contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        try await internalDelegate.userWantsToInviteOtherUserToOneToOne(self, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToShowOtherUserProfile(contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToShowOtherUserProfile(self, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToRemoveOtherUserFromGroup(groupIdentifier: ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        try await internalDelegate.userWantsToRemoveOtherUserFromGroup(self, groupIdentifier: groupIdentifier, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToRemoveMembersFromGroup(groupIdentifier: ObvGroupV2Identifier, membersToRemove: Set<SingleGroupMemberViewModelIdentifier>) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        try await internalDelegate.userWantsToRemoveMembersFromGroup(self, groupIdentifier: groupIdentifier, membersToRemove: membersToRemove)
    }

    func groupMembersWereSuccessfullyRemovedFromGroup(groupIdentifier: ObvGroupV2Identifier) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.groupMembersWereSuccessfullyRemovedFromGroup(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToUpdateGroupV2(groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        try await internalDelegate.userWantsToUpdateGroupV2(self, groupIdentifier: groupIdentifier, changeset: changeset)
    }
    
    func hudWasDismissedAfterSuccessfulGroupEdition(groupIdentifier: ObvGroupV2Identifier) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.hudWasDismissedAfterSuccessfulGroupEdition(self, groupIdentifier: groupIdentifier)
    }
    
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(self, creationSessionUUID: creationSessionUUID, memberIdentifier: memberIdentifier, newIsAnAdmin: newIsAnAdmin)
    }
    
    func userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(self, creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId)
    }
    
}


// MARK: - View's actions

private final class ViewsActions: FullListOfGroupMembersViewActionsProtocol {
    
    weak var delegate: FullListOfGroupMembersViewActionsProtocol?
    
    enum ObvError: Error {
        case delegateIsNil
    }

    func userWantsToAddGroupMembers(groupIdentifier: ObvGroupV2Identifier) async {
        guard let delegate else { assertionFailure(); return }
        await delegate.userWantsToAddGroupMembers(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToRemoveGroupMembers(groupIdentifier: ObvGroupV2Identifier) async {
        guard let delegate else { assertionFailure(); return }
        await delegate.userWantsToRemoveGroupMembers(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToInviteOtherUserToOneToOne(contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToInviteOtherUserToOneToOne(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToShowOtherUserProfile(contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        guard let delegate else { assertionFailure(); return }
        await delegate.userWantsToShowOtherUserProfile(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToRemoveOtherUserFromGroup(groupIdentifier: ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToRemoveOtherUserFromGroup(groupIdentifier: groupIdentifier, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToRemoveMembersFromGroup(groupIdentifier: ObvGroupV2Identifier, membersToRemove: Set<SingleGroupMemberViewModelIdentifier>) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToRemoveMembersFromGroup(groupIdentifier: groupIdentifier, membersToRemove: membersToRemove)
    }
    
    func groupMembersWereSuccessfullyRemovedFromGroup(groupIdentifier: ObvGroupV2Identifier) {
        guard let delegate else { return }
        delegate.groupMembersWereSuccessfullyRemovedFromGroup(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToUpdateGroupV2(groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToUpdateGroupV2(groupIdentifier: groupIdentifier, changeset: changeset)
    }
    
    func hudWasDismissedAfterSuccessfulGroupEdition(groupIdentifier: ObvGroupV2Identifier) {
        guard let delegate else { assertionFailure(); return }
        delegate.hudWasDismissedAfterSuccessfulGroupEdition(groupIdentifier: groupIdentifier)
    }
 
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool) {
        guard let delegate else { assertionFailure(); return }
        delegate.userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(creationSessionUUID: creationSessionUUID, memberIdentifier: memberIdentifier, newIsAnAdmin: newIsAnAdmin)
    }
    
    func userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId) {
        guard let delegate else { assertionFailure(); return }
        delegate.userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId)
    }
}
