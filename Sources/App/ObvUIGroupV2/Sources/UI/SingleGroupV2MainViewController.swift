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
import ObvDesignSystem

@MainActor
protocol SingleGroupV2MainViewControllerDelegate: AnyObject {
    func userWantsToLeaveGroup(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws
    func userWantsToDisbandGroup(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws
    func userWantsToChat(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async
    func userWantsToCall(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ vc: SingleGroupV2MainViewController, publishedDetails: PublishedDetailsValidationViewModel) async throws
    func userWantsToNavigateToFullListOfOtherGroupMembers(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async
    func userWantsToNavigateToViewAllowingToModifyMembers(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async
    func userWantsToNavigateToViewAllowingToSelectGroupTypes(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) async
    func userWantsToNavigateToViewAllowingToManageAdmins(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) async
    func userWantsToNavigateToViewAllowingToEditGroupName(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) async
    func userWantsToInviteOtherUserToOneToOne(_ vc: SingleGroupV2MainViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    func userWantsToShowOtherUserProfile(_ vc: SingleGroupV2MainViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async
    func userWantsToRemoveOtherUserFromGroup(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    func userWantsToLeaveGroupFlow(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier)
    func userWantsToUpdatePersonalNote(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, with newText: String?) async
    func userWantsToEditGroupNicknameAndCustomPicture(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier)
    func userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier)
    func userWantsToCloneGroup(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) async throws
    func userTappedOnManualResyncOfGroupV2Button(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier) async throws
    func userWantsToNavigateToViewAllowingToAddGroupMembers(_ vc: SingleGroupV2MainViewController, groupIdentifier: ObvGroupV2Identifier)
}


final class SingleGroupV2MainViewController: UIHostingController<SingleGroupV2MainView> {
    
    private let actions = ViewActions()
    private weak var internalDelegate: SingleGroupV2MainViewControllerDelegate?
    let groupIdentifier: ObvGroupV2Identifier

    init(groupIdentifier: ObvGroupV2Identifier, delegate: SingleGroupV2MainViewControllerDelegate, dataSource: any SingleGroupV2MainViewDataSource) {
        self.groupIdentifier = groupIdentifier
        let rootView = SingleGroupV2MainView(groupIdentifier: groupIdentifier,
                                            dataSource: dataSource,
                                            actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        self.actions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}

// MARK: - Errors

extension SingleGroupV2MainViewController {
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}


// MARK: - Implementing SingleGroupV2MainViewActionsProtocol

extension SingleGroupV2MainViewController: SingleGroupV2MainViewActionsProtocol {
    
    func userWantsToLeaveGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await internalDelegate.userWantsToLeaveGroup(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToDisbandGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await internalDelegate.userWantsToDisbandGroup(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToChat(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToChat(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToCall(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToCall(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(publishedDetails: PublishedDetailsValidationViewModel) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await internalDelegate.userWantsToReplaceTrustedDetailsByPublishedDetails(self, publishedDetails: publishedDetails)
    }
    
    func userWantsToNavigateToFullListOfOtherGroupMembers(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToNavigateToFullListOfOtherGroupMembers(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToNavigateToViewAllowingToModifyMembers() async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToNavigateToViewAllowingToModifyMembers(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToNavigateToViewAllowingToSelectGroupTypes() async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToNavigateToViewAllowingToSelectGroupTypes(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToNavigateToViewAllowingToManageAdmins() async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToNavigateToViewAllowingToManageAdmins(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToNavigateToViewAllowingToEditGroupName() async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToNavigateToViewAllowingToEditGroupName(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToInviteOtherUserToOneToOne(contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await internalDelegate.userWantsToInviteOtherUserToOneToOne(self, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToShowOtherUserProfile(contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToShowOtherUserProfile(self, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToRemoveOtherUserFromGroup(groupIdentifier: ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await internalDelegate.userWantsToRemoveOtherUserFromGroup(self, groupIdentifier: groupIdentifier, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToLeaveGroupFlow() {
        guard let internalDelegate else { return } // No assert here, as this method can be called after the flow is dismissed
        internalDelegate.userWantsToLeaveGroupFlow(self, groupIdentifier: groupIdentifier)
    }
    
    func userTappedOnTheEditPersonalNoteButton(groupIdentifier: ObvGroupV2Identifier, currentPersonalNote: String?) {
        let viewControllerToPresent = PersonalNoteEditorHostingController(model: .init(initialText: currentPersonalNote), actions: self)
        if let sheet = viewControllerToPresent.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.preferredCornerRadius = 16.0
        }
        present(viewControllerToPresent, animated: true, completion: nil)
    }
    
    
    func userTappedOnTheEditCustomNameAndPhotoButton() {
        // We do not implement the views allowing to change the custom photo and nickname of a group in this module.
        // Instead, we leverage the existing implementation at the app level
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToEditGroupNicknameAndCustomPicture(self, groupIdentifier: self.groupIdentifier)
    }
    
    
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool) {
        assertionFailure("Not expected to be called. This is only used during group creation.")
    }
    
    
    func userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(groupIdentifier: ObvGroupV2Identifier) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(self, groupIdentifier: groupIdentifier)
    }
    
    
    func userTappedOnCloneGroupButton(groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let internalDelegate else { assertionFailure(); return }
        try await internalDelegate.userWantsToCloneGroup(self, groupIdentifier: groupIdentifier)
    }
    
    
    func userTappedOnManualResyncOfGroupV2Button(groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let internalDelegate else { assertionFailure(); return }
        try await internalDelegate.userTappedOnManualResyncOfGroupV2Button(self, groupIdentifier: groupIdentifier)
    }
    
    
    func userWantsToNavigateToViewAllowingToAddGroupMembers(groupIdentifier: ObvGroupV2Identifier) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToNavigateToViewAllowingToAddGroupMembers(self, groupIdentifier: groupIdentifier)
    }
    
}


// MARK: - Implementing PersonalNoteEditorViewActionsDelegate

extension SingleGroupV2MainViewController: PersonalNoteEditorViewActionsDelegate {
    
    func userWantsToDismissPersonalNoteEditorView() async {
        self.dismiss(animated: true)
    }
    
    
    func userWantsToUpdatePersonalNote(with newText: String?) async {
        self.dismiss(animated: true)
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToUpdatePersonalNote(self, groupIdentifier: groupIdentifier, with: newText)
    }
    
}


// MARK: - ViewActions

@MainActor
private final class ViewActions: SingleGroupV2MainViewActionsProtocol {
    
    weak var delegate: SingleGroupV2MainViewActionsProtocol?
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
    func userWantsToLeaveGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToLeaveGroup(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToDisbandGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToDisbandGroup(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToChat(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        guard let delegate else { assertionFailure(); return }
        return await delegate.userWantsToChat(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToCall(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        guard let delegate else { assertionFailure(); return }
        return await delegate.userWantsToCall(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(publishedDetails: PublishedDetailsValidationViewModel) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToReplaceTrustedDetailsByPublishedDetails(publishedDetails: publishedDetails)
    }
    
    func userWantsToNavigateToFullListOfOtherGroupMembers(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        guard let delegate else { assertionFailure(); return }
        return await delegate.userWantsToNavigateToFullListOfOtherGroupMembers(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToNavigateToViewAllowingToModifyMembers() async {
        guard let delegate else { assertionFailure(); return }
        await delegate.userWantsToNavigateToViewAllowingToModifyMembers()
    }
    
    func userWantsToNavigateToViewAllowingToSelectGroupTypes() async {
        guard let delegate else { assertionFailure(); return }
        return await delegate.userWantsToNavigateToViewAllowingToSelectGroupTypes()
    }
    
    func userWantsToNavigateToViewAllowingToManageAdmins() async {
        guard let delegate else { assertionFailure(); return }
        return await delegate.userWantsToNavigateToViewAllowingToManageAdmins()
    }
    
    func userWantsToNavigateToViewAllowingToEditGroupName() async {
        guard let delegate else { assertionFailure(); return }
        return await delegate.userWantsToNavigateToViewAllowingToEditGroupName()
    }
    
    func userWantsToInviteOtherUserToOneToOne(contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToInviteOtherUserToOneToOne(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToShowOtherUserProfile(contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        guard let delegate else { assertionFailure(); return }
        return await delegate.userWantsToShowOtherUserProfile(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToRemoveOtherUserFromGroup(groupIdentifier: ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToRemoveOtherUserFromGroup(groupIdentifier: groupIdentifier, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToLeaveGroupFlow() {
        guard let delegate else { return } // No assert here, as this method my be called after the flow is dismissed
        delegate.userWantsToLeaveGroupFlow()
    }
    
    func userTappedOnTheEditPersonalNoteButton(groupIdentifier: ObvGroupV2Identifier, currentPersonalNote: String?) {
        guard let delegate else { assertionFailure(); return }
        delegate.userTappedOnTheEditPersonalNoteButton(groupIdentifier: groupIdentifier, currentPersonalNote: currentPersonalNote)
    }
    
    func userTappedOnTheEditCustomNameAndPhotoButton() {
        guard let delegate else { assertionFailure(); return }
        delegate.userTappedOnTheEditCustomNameAndPhotoButton()
    }
 
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool) {
        guard let delegate else { assertionFailure(); return }
        delegate.userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(creationSessionUUID: creationSessionUUID, memberIdentifier: memberIdentifier, newIsAnAdmin: newIsAnAdmin)
    }
    
    func userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(groupIdentifier: ObvGroupV2Identifier) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(groupIdentifier: groupIdentifier)
    }
    
    func userTappedOnCloneGroupButton(groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let delegate else { assertionFailure(); return }
        try await delegate.userTappedOnCloneGroupButton(groupIdentifier: groupIdentifier)
    }
 
    func userTappedOnManualResyncOfGroupV2Button(groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let delegate else { assertionFailure(); return }
        try await delegate.userTappedOnManualResyncOfGroupV2Button(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToNavigateToViewAllowingToAddGroupMembers(groupIdentifier: ObvGroupV2Identifier) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToNavigateToViewAllowingToAddGroupMembers(groupIdentifier: groupIdentifier)
    }
}
