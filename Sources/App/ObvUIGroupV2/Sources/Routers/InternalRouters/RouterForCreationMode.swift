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
public protocol ObvUIGroupV2RouterDelegateForCreation: AnyObject {
    func userWantsObtainAvatarDuringGroupCreation(_ router: ObvUIGroupV2Router, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    func userWantsToSaveImageToTempFileDuringGroupCreation(_ router: ObvUIGroupV2Router, image: UIImage) async throws -> URL
    func presentedGroupCreationFlowShouldBeDismissed(_ router: ObvUIGroupV2Router)
    func userWantsToPublishCreatedGroupV2(_ router: ObvUIGroupV2Router, ownedCryptoId: ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails, groupType: ObvGroupType, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>) async throws
}


@MainActor
final class RouterForCreationMode {
        
    weak var parentRouter: ObvUIGroupV2Router?

    private let dataSource: ObvUIGroupV2RouterDataSource // Strong pointer to the dataSource
    private weak var delegate: ObvUIGroupV2RouterDelegateForCreation?
    
    /// Each time the user starts a group creation (or cloning), we create an associated `CreationSession`.
    @MainActor
    final class CreationSession {
        
        let sessionUUID = UUID()
        let ownedCryptoId: ObvCryptoId
        let navigationController = UINavigationController()

        var userIdentifiersOfAddedUsers = [SelectUsersToAddViewModel.User.Identifier]()
        var selectedAdmins = Set<SingleGroupMemberViewModelIdentifier>()
        var selectedGroupType: ObvGroupType?
        var selectedPhoto: UIImage?
        var selectedGroupName: String?
        var selectedGroupDescription: String?

        var continuationForAdminsSelection: AsyncStream<ObvUIGroupV2.ListOfSingleGroupMemberViewModel>.Continuation?
        var streamUUIDForAdminsSelection: UUID?

        init(ownedCryptoId: ObvCryptoId) {
            self.ownedCryptoId = ownedCryptoId
        }
        
    }
    
    private var creationSessionForUUID: [UUID: CreationSession] = [:]
        
    init(dataSource: ObvUIGroupV2RouterDataSource, delegate: ObvUIGroupV2RouterDelegateForCreation) {
        self.dataSource = dataSource
        self.delegate = delegate
    }
    
    func presentInitialViewController(ownedCryptoId: ObvCryptoId, presentingViewController: UIViewController, creationType: ObvUIGroupV2Router.CreationMode) {
        
        // We create a new session for this group creation
        let creationSession = CreationSession(ownedCryptoId: ownedCryptoId)
        switch creationType {
        case .fromScratch:
            break
        case .cloneExistingGroup(valuesOfGroupToClone: let valuesOfClonedGroup):
            creationSession.userIdentifiersOfAddedUsers = valuesOfClonedGroup.userIdentifiersOfAddedUsers
            creationSession.selectedAdmins = valuesOfClonedGroup.selectedAdmins
            creationSession.selectedGroupType = valuesOfClonedGroup.selectedGroupType
            creationSession.selectedPhoto = valuesOfClonedGroup.selectedPhoto
            creationSession.selectedGroupName = String(localizedInThisBundle: "CLONED_GROUP_NAME_FROM_ORIGINAL_NAME_\(valuesOfClonedGroup.selectedGroupName ?? "")")
            creationSession.selectedGroupDescription = valuesOfClonedGroup.selectedGroupDescription
        }
        self.creationSessionForUUID[creationSession.sessionUUID] = creationSession
        
        var _presentingViewController = presentingViewController
        while let pVC = _presentingViewController.presentedViewController {
            _presentingViewController = pVC
        }

        let mode: SelectUsersToAddView.Mode = .creation(ownedCryptoId: ownedCryptoId,
                                                        creationSessionUUID: creationSession.sessionUUID,
                                                        preselectedUserIdentifiers: creationSession.userIdentifiersOfAddedUsers)
        let vc = SelectUsersToAddViewController(mode: mode, dataSource: self, delegate: self)
        creationSession.navigationController.setViewControllers([vc], animated: false)
        _presentingViewController.present(creationSession.navigationController, animated: true)
        
    }
    
    enum ObvError: Error {
        case unexpectedDuringGroupCreation
        case dataSourceOrParentRouterIsNil
        case delegateOrParentRouterIsNil
        case selectedGroupTypeIsNil
        case unexpectedOwnedIdentity
        case creationSessionIsNil
    }
}


// MARK: - Implementing SelectUsersToAddViewControllerDelegate

extension RouterForCreationMode: SelectUsersToAddViewControllerDelegate {
    
    func userWantsToAddSelectedUsersToExistingGroup(_ vc: SelectUsersToAddViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {
        assertionFailure("Not expected to be called during a group creation")
        throw ObvError.unexpectedDuringGroupCreation
    }
    
    func userWantsToAddSelectedUsersToCreatingGroup(_ vc: SelectUsersToAddViewController, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) {
        guard let creationSession = creationSessionForUUID[creationSessionUUID] else { assertionFailure(); return }
        creationSession.userIdentifiersOfAddedUsers = userIdentifiers
        let mode: EditGroupTypeView.Mode = .creation(creationSessionUUID: creationSessionUUID,
                                                     ownedCryptoId: ownedCryptoId,
                                                     preSelectedGroupType: creationSession.selectedGroupType ?? .standard)
        let vc = EditGroupTypeViewController(mode: mode, dataSource: self, delegate: self)
        creationSession.navigationController.pushViewController(vc, animated: true)
    }
    
    /// Called when the user hits cancel on the page allowing to choose the group members.
    func userWantsToCancelAndDismiss(_ vc: SelectUsersToAddViewController) {
        guard let parentRouter else { assertionFailure(); return }
        delegate?.presentedGroupCreationFlowShouldBeDismissed(parentRouter)
    }
    
    func viewShouldBeDismissed(_ vc: SelectUsersToAddViewController) {
        assertionFailure("Not expected to be called during a group creation")
    }
    
}


// MARK: - Implementing EditGroupTypeViewControllerDelegate

extension RouterForCreationMode: EditGroupTypeViewControllerDelegate {
    
    func userWantsToLeaveGroupFlow(_ vc: EditGroupTypeViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        assertionFailure("Not expected to be called during a group creation")
    }
    
    func userWantsToUpdateGroupV2(_ vc: EditGroupTypeViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        assertionFailure("Not expected to be called during a group creation")
        throw ObvError.unexpectedDuringGroupCreation
    }
    
    func userChosedGroupTypeAndWantsToSelectAdmins(_ vc: EditGroupTypeViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, selectedGroupType: ObvAppTypes.ObvGroupType) {
        assertionFailure("Not expected to be called during a group creation")
    }
    
    /// Called when the user hits cancel on the page allowing to choose the group type.
    func userWantsToCancelAndDismiss(_ vc: EditGroupTypeViewController) {
        guard let parentRouter else { assertionFailure(); return }
        delegate?.presentedGroupCreationFlowShouldBeDismissed(parentRouter)
    }
    
    func userChosedGroupTypeDuringGroupCreation(_ vc: EditGroupTypeViewController, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, selectedGroupType: ObvAppTypes.ObvGroupType) {
        guard let creationSession = creationSessionForUUID[creationSessionUUID] else { assertionFailure(); return }
        creationSession.selectedGroupType = selectedGroupType
        switch selectedGroupType {
        case .standard:
            let mode: EditGroupNameAndPictureView.Mode = .creation(creationSessionUUID: creationSessionUUID,
                                                                   ownedCryptoId: ownedCryptoId,
                                                                   preSelectedPhoto: creationSession.selectedPhoto,
                                                                   preSelectedGroupName: creationSession.selectedGroupName,
                                                                   preSelectedGroupDescription: creationSession.selectedGroupDescription)
            let vc = EditGroupNameAndPictureViewController(mode: mode, dataSource: self, delegate: self)
            creationSession.navigationController.pushViewController(vc, animated: true)
        case .managed, .readOnly, .advanced:
            let mode: GroupMembersListMode = .selectAdminsDuringGroupCreation(creationSessionUUID: creationSessionUUID,
                                                                              ownedCryptoId: ownedCryptoId,
                                                                              preSelectedAdmins: creationSession.selectedAdmins)
            let vc = FullListOfGroupMembersViewController(mode: mode, dataSource: self, delegate: self)
            creationSession.navigationController.pushViewController(vc, animated: true)
        }
    }
    
}


// MARK: - FullListOfGroupMembersViewControllerDelegate

extension RouterForCreationMode: FullListOfGroupMembersViewControllerDelegate {
    
    func userWantsToNavigateToViewAllowingToAddGroupMembers(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        assertionFailure("Unexpected call during group creation")
        return
    }
    
    
    func userWantsToNavigateToViewAllowingToRemoveGroupMembers(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        assertionFailure("Unexpected call during group creation")
        return
    }
    
    
    func userWantsToInviteOtherUserToOneToOne(_ vc: FullListOfGroupMembersViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        assertionFailure("Unexpected call during group creation")
        return
    }
    
    
    func userWantsToShowOtherUserProfile(_ vc: FullListOfGroupMembersViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        assertionFailure("Unexpected call during group creation")
        return
    }
    
    
    func userWantsToRemoveOtherUserFromGroup(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        assertionFailure("Unexpected call during group creation")
        return
    }
    
    
    func userWantsToRemoveMembersFromGroup(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, membersToRemove: Set<SingleGroupMemberViewModelIdentifier>) async throws {
        assertionFailure("Unexpected call during group creation")
        return
    }
    
    
    func groupMembersWereSuccessfullyRemovedFromGroup(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        assertionFailure("Unexpected call during group creation")
        return
    }
    
    
    func userWantsToUpdateGroupV2(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        assertionFailure("Unexpected call during group creation")
        return
    }

    
    func userWantsToCancelAndDismiss(_ vc: FullListOfGroupMembersViewController) {
        guard let parentRouter else { assertionFailure(); return }
        delegate?.presentedGroupCreationFlowShouldBeDismissed(parentRouter)
    }
    
    
    func hudWasDismissedAfterSuccessfulGroupEdition(_ vc: FullListOfGroupMembersViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        assertionFailure("Unexpected call during group creation")
        return
    }
    
    
    /// During a group creation, each time the owned identity toggles on/off an admin, the choice is immediately reflected here. This allows to make sure that, even if the user taps on the back button from the screen allowing to change admins,
    /// the choices made are not lost.
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(_ vc: FullListOfGroupMembersViewController, creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool) {
        guard let creationSession = creationSessionForUUID[creationSessionUUID] else { assertionFailure(); return }
        if newIsAnAdmin {
            creationSession.selectedAdmins.insert(memberIdentifier)
        } else {
            creationSession.selectedAdmins.remove(memberIdentifier)
        }
    }

    func userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(_ vc: FullListOfGroupMembersViewController, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId) {
        guard let creationSession = creationSessionForUUID[creationSessionUUID] else { assertionFailure(); return }
        let mode: EditGroupNameAndPictureView.Mode = .creation(creationSessionUUID: creationSessionUUID,
                                                               ownedCryptoId: ownedCryptoId,
                                                               preSelectedPhoto: creationSession.selectedPhoto,
                                                               preSelectedGroupName: creationSession.selectedGroupName,
                                                               preSelectedGroupDescription: creationSession.selectedGroupDescription)
        let vc = EditGroupNameAndPictureViewController(mode: mode, dataSource: self, delegate: self)
        creationSession.navigationController.pushViewController(vc, animated: true)
    }
    
}


// MARK: - Implementing EditGroupNameAndPictureViewControllerDelegate

extension RouterForCreationMode: EditGroupNameAndPictureViewControllerDelegate {
        
    func userWantsToLeaveGroupFlow(_ vc: EditGroupNameAndPictureViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        assertionFailure("Not expected to be called during a group creation")
    }
    
    func userWantsObtainAvatar(_ vc: EditGroupNameAndPictureViewController, avatarSource: ObvAppTypes.ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.userWantsObtainAvatarDuringGroupCreation(parentRouter, avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    func userWantsToSaveImageToTempFile(_ vc: EditGroupNameAndPictureViewController, image: UIImage) async throws -> URL {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.userWantsToSaveImageToTempFileDuringGroupCreation(parentRouter, image: image)
    }
    
    func userWantsToUpdateGroupV2(_ vc: EditGroupNameAndPictureViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        assertionFailure("Not expected to be called during a group creation")
        throw ObvError.unexpectedDuringGroupCreation
    }
    
    /// Called when the user hits cancel on the page allowing to choose the group name, description and photo.
    func userWantsToCancelAndDismiss(_ vc: EditGroupNameAndPictureViewController) {
        guard let parentRouter else { assertionFailure(); return }
        delegate?.presentedGroupCreationFlowShouldBeDismissed(parentRouter)
    }
    
    func groupDetailsWereSuccessfullyUpdated(_ vc: EditGroupNameAndPictureViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        assertionFailure("Not expected to be called during a group creation")
    }
    
    func userWantsToPublishCreatedGroupWithDetails(_ vc: EditGroupNameAndPictureViewController, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails) async throws {
        guard let parentRouter, let delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        guard let creationSession = creationSessionForUUID[creationSessionUUID] else { assertionFailure(); throw ObvError.creationSessionIsNil }

        guard let selectedGroupType = creationSession.selectedGroupType else {
            assertionFailure("Since we went through the group type selection screen, this is unexpected")
            throw ObvError.selectedGroupTypeIsNil
        }
        
        var adminsCryptoIds = Set<ObvCryptoId>()
        for admin in creationSession.selectedAdmins {
            let contactIdentifier = try await dataSource.getContactIdentifierOfGroupMember(parentRouter, contactIdentifier: admin)
            guard contactIdentifier.ownedCryptoId == ownedCryptoId else {
                assertionFailure()
                throw ObvError.unexpectedOwnedIdentity
            }
            adminsCryptoIds.insert(contactIdentifier.contactCryptoId)
        }
        
        let permissionsForAdmins = ObvGroupType.exactPermissions(of: .admin, forGroupType: selectedGroupType)
        let permissionsForRegularMember = ObvGroupType.exactPermissions(of: .regularMember, forGroupType: selectedGroupType)
        
        var otherGroupMembers = Set<ObvGroupV2.IdentityAndPermissions>()
        for userIdentifierOfAddedUser in creationSession.userIdentifiersOfAddedUsers {
            let contactIdentifier = try await dataSource.getContactIdentifierOfGroupMember(parentRouter, contactIdentifier: userIdentifierOfAddedUser)
            guard contactIdentifier.ownedCryptoId == ownedCryptoId else {
                assertionFailure()
                throw ObvError.unexpectedOwnedIdentity
            }
            let contactCryptoId = contactIdentifier.contactCryptoId
            if adminsCryptoIds.contains(contactCryptoId) {
                otherGroupMembers.insert(.init(identity: contactCryptoId, permissions: permissionsForAdmins))
            } else {
                otherGroupMembers.insert(.init(identity: contactCryptoId, permissions: permissionsForRegularMember))
            }
        }
        
        try await delegate.userWantsToPublishCreatedGroupV2(parentRouter,
                                                            ownedCryptoId: ownedCryptoId,
                                                            groupDetails: groupDetails,
                                                            groupType: selectedGroupType,
                                                            otherGroupMembers: otherGroupMembers)
    }
    
    /// Called when the group has been published and the checkmark was dismissed
    func groupWasSuccessfullyCreated(_ vc: EditGroupNameAndPictureViewController, ownedCryptoId: ObvTypes.ObvCryptoId) {
        guard let parentRouter else { assertionFailure(); return }
        delegate?.presentedGroupCreationFlowShouldBeDismissed(parentRouter)
    }

}


// MARK: - Implementing EditGroupNameAndPictureViewDataSource

extension RouterForCreationMode: EditGroupNameAndPictureViewDataSource {
    
    func getPhotoForGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        assertionFailure("Not expected to be called during a group creation")
        throw ObvError.unexpectedDuringGroupCreation
    }
    
}


// MARK: - Implementing EditGroupTypeViewDataSource

extension RouterForCreationMode: EditGroupTypeViewDataSource {
    
    func getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>) {
        assertionFailure("Not expected to be called during a group creation")
        throw ObvError.unexpectedDuringGroupCreation
    }
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: UUID) {
        assertionFailure("Not expected to be called during a group creation")
    }
    
}


// MARK: - Implementing SelectUsersToAddViewDataSource

extension RouterForCreationMode: SelectUsersToAddViewDataSource {
    
    func getAsyncSequenceOfUsersToAddToCreatingGroup(ownedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfSelectUsersToAddViewModel(parentRouter, mode: .creation(ownedCryptoId: ownedCryptoId))
    }
    
    func getAsyncSequenceOfUsersToAddToExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        assertionFailure("Not expected to be called during a group creation")
        throw ObvError.unexpectedDuringGroupCreation
    }
    
    func filterAsyncSequenceOfUsersToAdd(streamUUID: UUID, searchText: String?) {
        guard let parentRouter else { assertionFailure(); return }
        dataSource.filterAsyncSequenceOfSelectUsersToAddViewModel(parentRouter, streamUUID: streamUUID, searchText: searchText)
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

}

// MARK: - Implementing OwnedIdentityAsGroupMemberViewDataSource

extension RouterForCreationMode: OwnedIdentityAsGroupMemberViewDataSource {
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityAsGroupMemberViewModel>) {
        assertionFailure("Not expected to be called during a group creation")
        throw ObvError.unexpectedDuringGroupCreation
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier, streamUUID: UUID) {
        assertionFailure("Not expected to be called during a group creation")
    }
    
    func fetchAvatarImageForOwnedIdentityAsGroupMember(ownedCryptoId: ObvTypes.ObvCryptoId, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        assertionFailure("Not expected to be called during a group creation")
        throw ObvError.unexpectedDuringGroupCreation
    }
    
}


// MARK: - Implementing FullListOfGroupMembersViewDataSource

extension RouterForCreationMode: FullListOfGroupMembersViewDataSource {
        
    /// This called during group creation, when selecting the admins of the group
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(creationSessionUUID: UUID) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        
        guard let creationSession = creationSessionForUUID[creationSessionUUID] else { assertionFailure(); throw ObvError.creationSessionIsNil }
        
        creationSession.continuationForAdminsSelection?.finish()
        creationSession.continuationForAdminsSelection = nil
        creationSession.streamUUIDForAdminsSelection = nil
        
        let newStreamUUID = UUID()
        creationSession.streamUUIDForAdminsSelection = newStreamUUID
        
        let stream = AsyncStream(ObvUIGroupV2.ListOfSingleGroupMemberViewModel.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.ListOfSingleGroupMemberViewModel>.Continuation) in
            guard let self else { continuation.finish(); return }
            creationSession.continuationForAdminsSelection = continuation
            let model = createListOfSingleGroupMemberViewModel(creationSession: creationSession, searchText: nil)
            continuation.yield(model)
        }
        
        return (newStreamUUID, stream)

    }
    
    
    /// Called when the user performs a search in the screen allowing to choose the admins, during a group creation.
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID, searchText: String?) {
        guard let creationSession = creationSessionForUUID.values.first(where: { $0.streamUUIDForAdminsSelection == streamUUID }) else { assertionFailure() ; return }
        guard let continuationForAdminsSelection = creationSession.continuationForAdminsSelection else { assertionFailure(); return }
        let model = createListOfSingleGroupMemberViewModel(creationSession: creationSession, searchText: searchText)
        continuationForAdminsSelection.yield(model)
    }

    
    private func createListOfSingleGroupMemberViewModel(creationSession: CreationSession, searchText: String?) -> ListOfSingleGroupMemberViewModel {
        
        let userIdentifiersOfAddedUsersFiltered = dataSource.filterUsersWithSearchText(users: creationSession.userIdentifiersOfAddedUsers,
                                                                                       searchText: searchText)
        
        var identifiers = [SingleGroupMemberViewModelIdentifier]()
        for userIdentifierOfAddedUser in userIdentifiersOfAddedUsersFiltered {
            let identifier: SingleGroupMemberViewModelIdentifier
            switch userIdentifierOfAddedUser {
            case .contactIdentifier(contactIdentifier: let contactIdentifier):
                identifier = .contactIdentifierForCreatingGroup(contactIdentifier: contactIdentifier)
            case .objectIDOfPersistedObvContactIdentity(objectID: let objectID):
                identifier = .objectIDOfPersistedContact(objectID: objectID)
            }
            identifiers.append(identifier)
        }
        let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: identifiers)
        return model
    }
    
    
    /// Called during group creation when the user leaves the screen allowing to choose the admins of the group.
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID) {
        guard let creationSession = creationSessionForUUID.values.first(where: { $0.streamUUIDForAdminsSelection == streamUUID }) else { return }
        creationSession.streamUUIDForAdminsSelection = nil
        creationSession.continuationForAdminsSelection?.finish()
        creationSession.continuationForAdminsSelection = nil
    }
    

    func getGroupLightweightModelDuringGroupCreation(creationSessionUUID: UUID) throws -> GroupLightweightModel {
        guard let creationSession = creationSessionForUUID[creationSessionUUID] else { assertionFailure(); throw ObvError.creationSessionIsNil }
        return GroupLightweightModel(ownedIdentityIsAdmin: true, groupType: creationSession.selectedGroupType, updateInProgressDuringGroupEdition: false, isKeycloakManaged: false)
    }
    
    
    func getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        assertionFailure("Not expected to be called during a group creation")
        throw ObvError.unexpectedDuringGroupCreation
    }
    
    
    func finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(streamUUID: UUID) {
        assertionFailure("Not expected to be called during a group creation as we don't show the tab restricting to admins in this case")
    }
    
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        assertionFailure("Unexpected to be called during a group creation")
        throw ObvError.unexpectedDuringGroupCreation
    }
    
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberViewModel>) {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try dataSource.getAsyncSequenceOfSingleGroupMemberViewModels(parentRouter, memberIdentifier: identifier)
    }
    
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier, streamUUID: UUID) {
        guard let parentRouter else { assertionFailure(); return }
        dataSource.finishAsyncSequenceOfSingleGroupMemberViewModels(parentRouter, memberIdentifier: identifier, streamUUID: streamUUID)
    }

    
    func finishAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, streamUUID: UUID) {
        assertionFailure("Unexpected to be called during a group creation")
    }
    
    
    func fetchAvatarImageForGroupMember(contactIdentifier: ObvTypes.ObvContactIdentifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let parentRouter else { assertionFailure(); throw ObvError.dataSourceOrParentRouterIsNil }
        return try await dataSource.fetchAvatarImage(parentRouter, photoURL: photoURL, avatarSize: avatarSize)
    }
    
    
    func getAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<GroupLightweightModel>) {
        assertionFailure("Unexpected to be called during a group creation")
        throw ObvError.unexpectedDuringGroupCreation
    }

}
