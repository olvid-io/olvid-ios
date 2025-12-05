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
import ObvAppTypes
import ObvTypes
import ObvDesignSystem


@MainActor
final class GenericDataSourceAndActionsForPreviews {}

extension GenericDataSourceAndActionsForPreviews {
    
    enum ObvError: Error {
        case error
    }
    
}


extension GenericDataSourceAndActionsForPreviews: UIKitDelegateForSwiftUISheet {
    func userWantsToPresentView<Content>(_ view: some View, content: @escaping () -> Content) where Content : View {}
    func userWantsToDismissPresentedView(_ view: some View) {}
}


extension GenericDataSourceAndActionsForPreviews: ListOfMembersWithSegmentedControlViewDataSource {
    
    func getAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(_ view: ListOfMembersWithSegmentedControlView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, searchText: String?) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfMembersWithSegmentedControlView.Model>) {
        let stream = AsyncStream<ListOfMembersWithSegmentedControlView.Model> { (continuation: AsyncStream<ListOfMembersWithSegmentedControlView.Model>.Continuation) in
            Task {
                while true {
                    do {
                        let allOtherGroupMembers = SingleGroupMemberView.Model.Identifier.sampleIdentifiers
                        let allOtherGroupAdmins = [SingleGroupMemberView.Model.Identifier](allOtherGroupMembers.prefix(2))
                        let model: ListOfMembersWithSegmentedControlView.Model = .init(
                            groupIdentifier: ObvGroupIdentifier.sampleData,
                            allOtherGroupMembers: allOtherGroupMembers,
                            allOtherGroupAdmins: allOtherGroupAdmins,
                            isGroupV2UpdateInProgress: false,
                            isOwnedIdentityAnAdmin: true)
                        continuation.yield(model)
                    }
                    try? await Task.sleep(seconds: 3)
                    do {
                        let allOtherGroupMembers = SingleGroupMemberView.Model.Identifier.sampleIdentifiers
                        let allOtherGroupAdmins = [SingleGroupMemberView.Model.Identifier](allOtherGroupMembers.prefix(2))
                        let model: ListOfMembersWithSegmentedControlView.Model = .init(
                            groupIdentifier: ObvGroupIdentifier.sampleData,
                            allOtherGroupMembers: allOtherGroupMembers,
                            allOtherGroupAdmins: allOtherGroupAdmins,
                            isGroupV2UpdateInProgress: true,
                            isOwnedIdentityAnAdmin: true)
                        continuation.yield(model)
                    }
                    try? await Task.sleep(seconds: 3)
                }
            }
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(_ view: ListOfMembersWithSegmentedControlView, streamUUID: UUID, searchText: String?) {}
    
    func finishAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(_ view: ListOfMembersWithSegmentedControlView, streamUUID: UUID) {}
    
}

extension GenericDataSourceAndActionsForPreviews: ListOfMembersWithAddAndRemoveButtonsViewDataSource {
    
    func getAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(_ view: ListOfMembersWithAddAndRemoveButtonsView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, searchText: String?) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfMembersWithAddAndRemoveButtonsView.Model>) {
        let stream = AsyncStream<ListOfMembersWithAddAndRemoveButtonsView.Model> { (continuation: AsyncStream<ListOfMembersWithAddAndRemoveButtonsView.Model>.Continuation) in
            Task {
                while true {
                    do {
                        let model: ListOfMembersWithAddAndRemoveButtonsView.Model = .init(
                            groupIdentifier: ObvGroupIdentifier.sampleData,
                            allOtherGroupMembers: SingleGroupMemberView.Model.Identifier.sampleIdentifiers,
                            isGroupV2UpdateInProgress: false)
                        continuation.yield(model)
                    }
                    try? await Task.sleep(seconds: 3)
                    do {
                        let model: ListOfMembersWithAddAndRemoveButtonsView.Model = .init(
                            groupIdentifier: ObvGroupIdentifier.sampleData,
                            allOtherGroupMembers: SingleGroupMemberView.Model.Identifier.sampleIdentifiers,
                            isGroupV2UpdateInProgress: true)
                        continuation.yield(model)
                    }
                    try? await Task.sleep(seconds: 3)
                }
            }
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(_ view: ListOfMembersWithAddAndRemoveButtonsView, streamUUID: UUID, searchText: String?) {}
    
    func finishAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(_ view: ListOfMembersWithAddAndRemoveButtonsView, streamUUID: UUID) {}
    
}


extension GenericDataSourceAndActionsForPreviews: SelectUsersToAddViewDataSource {
    
    func getAsyncSequenceOfUsersToAddToCreatingGroup(_ view: SelectUsersToAddView, ownedCryptoId: ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        let model = PreviewsHelper.selectUsersToAddViewModel
        let stream = AsyncStream(SelectUsersToAddViewModel.self) { (continuation: AsyncStream<SelectUsersToAddViewModel>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }

    func getAsyncSequenceOfUsersToAddToExistingGroup(_ view: SelectUsersToAddView, groupIdentifier: ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        let model = PreviewsHelper.selectUsersToAddViewModel
        let stream = AsyncStream(SelectUsersToAddViewModel.self) { (continuation: AsyncStream<SelectUsersToAddViewModel>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }

    func filterAsyncSequenceOfUsersToAdd(_ view: SelectUsersToAddView.InternalView, streamUUID: UUID, searchText: String?) {
        // We don't simulate search
    }

    func finishAsyncSequenceOfSelectUsersToAddViewModel(_ view: SelectUsersToAddView, streamUUID: UUID) {}
    
}


extension GenericDataSourceAndActionsForPreviews: ListOfUsersViewCellDataSource {
    
    func getAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel.User>) {
        let model = PreviewsHelper.selectUsersToAddViewModelUser.first(where: { $0.identifier == identifier })!
        let stream = AsyncStream(SelectUsersToAddViewModel.User.self) { (continuation: AsyncStream<SelectUsersToAddViewModel.User>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier, streamUUID: UUID) {}
    
}


extension GenericDataSourceAndActionsForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        if let image = PreviewsHelper.profilePictureForURL[photoURL] {
            return image
        } else {
            return nil
        }
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        if let image = PreviewsHelper.profilePictureForURL[photoURL] {
            return image
        } else {
            return nil
        }
    }
    
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }

}


extension GenericDataSourceAndActionsForPreviews: SelectUsersToRemoveViewDataSource {
    
    func getAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: SelectUsersToRemoveView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, searchText: String?) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToRemoveView.Model>) {
        let stream = AsyncStream<SelectUsersToRemoveView.Model> { (continuation: AsyncStream<SelectUsersToRemoveView.Model>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 2)
                do {
                    let allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] = SingleGroupMemberView.Model.Identifier.sampleIdentifiers
                    let model: SelectUsersToRemoveView.Model = .init(
                        groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                        allOtherGroupMembers: allOtherGroupMembers,
                        filteredOtherGroupMembers: allOtherGroupMembers)
                    continuation.yield(model)
                }
            }
        }
        return (UUID(), stream)
    }

    func filterAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: SelectUsersToRemoveView, streamUUID: UUID, searchText: String?) {}
    
    func finishAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: SelectUsersToRemoveView, streamUUID: UUID) {}
    
}


extension GenericDataSourceAndActionsForPreviews: OwnedIdentityAsGroupMemberViewDataSource {
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityAsGroupMemberViewModel>) {
        let stream = AsyncStream<OwnedIdentityAsGroupMemberViewModel> { (continuation: AsyncStream<OwnedIdentityAsGroupMemberViewModel>.Continuation) in
            Task {
                let model = OwnedIdentityAsGroupMemberViewModel.sampleData
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, streamUUID: UUID) {}
    
}


extension GenericDataSourceAndActionsForPreviews: SingleGroupMemberViewDataSource {
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(_ view: SingleGroupMemberView, withIdentifier identifier: SingleGroupMemberView.Model.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberView.Model>) {
        let stream = AsyncStream(SingleGroupMemberView.Model.self) { (continuation: AsyncStream<SingleGroupMemberView.Model>.Continuation) in
            switch identifier {
            case .contactIdentifierForExistingGroupForPreviews(groupIdentifier: _, contactIdentifier: let contactIdentifier),
                    .contactIdentifierForCreatingGroupForPreviews(contactIdentifier: let contactIdentifier):
                guard let groupMember = PreviewsHelper.groupMembers.first(where: { $0.contactIdentifier == contactIdentifier }) else {
                    assertionFailure()
                    return
                }
                continuation.yield(groupMember)
            case .objectIDOfPersistedGroupV2Member,
                    .objectIDOfPersistedContact,
                    .objectIDOfPersistedPendingGroupMember:
                assertionFailure()
                return
            }
        }
        return (UUID(), stream)
    }
    

    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ view: SingleGroupMemberView, withIdentifier identifier: SingleGroupMemberView.Model.Identifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }

}


// MARK: - Actions

extension GenericDataSourceAndActionsForPreviews: SelectUsersToAddViewActionsForEdition {
    
    func userWantsToAddSelectedUsersToExistingGroup(_ view: SelectUsersToAddView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {}
    
}


extension GenericDataSourceAndActionsForPreviews: SelectUsersToRemoveViewActions {
    
    func userWantsToRemoveMembersFromGroup(_ view: SelectUsersToRemoveView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, membersToRemove: Set<SingleGroupMemberView.Model.Identifier>) async throws {}
    
}


extension GenericDataSourceAndActionsForPreviews: SingleGroupMemberViewActionsProtocol {
    
}

extension GenericDataSourceAndActionsForPreviews: ListOfMembersWithAddAndRemoveButtonsViewActions {
    
}


extension GenericDataSourceAndActionsForPreviews: ListOfMembersWithSegmentedControlViewActions {
    
}


// MARK: - Navigation

extension GenericDataSourceAndActionsForPreviews: SingleGroupMemberViewNavigation {
    func userWantsToShowOtherUserProfile(_ view: SingleGroupMemberView.InternalView, contactIdentifier: ObvTypes.ObvContactIdentifier) async {}
}

extension GenericDataSourceAndActionsForPreviews: ListOfMembersWithAddAndRemoveButtonsViewNavigation {
    
    // Other protocol conformances are enough

}


extension GenericDataSourceAndActionsForPreviews: ListOfMembersWithSegmentedControlViewNavigation {

    // Other protocol conformances are enough

}
