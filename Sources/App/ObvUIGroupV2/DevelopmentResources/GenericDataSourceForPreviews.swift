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
import ObvUIGroupSharedBetweenV1AndV2
import ObvAppTypes
import ObvTypes
import ObvDesignSystem


@MainActor
final class GenericDataSourceForPreviews {}

extension GenericDataSourceForPreviews {
    
    enum ObvError: Error {
        case error
    }
    
}

extension GenericDataSourceForPreviews: SelectUsersToRemoveViewDataSource {
    
    func getAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, searchText: String?) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView.Model>) {
        let stream = AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView.Model> { (continuation: AsyncStream<SelectUsersToRemoveView.Model>.Continuation) in
            Task {
                let model: SelectUsersToRemoveView.Model = .init(
                    groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                    allOtherGroupMembers: [],
                    filteredOtherGroupMembers: [])
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView, streamUUID: UUID, searchText: String?) {}
    
    func finishAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView, streamUUID: UUID) {}
    
}

extension GenericDataSourceForPreviews: SingleGroupV2MainViewDataSource {
    
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>) {
        let stream = AsyncStream(SingleGroupV2MainViewModelOrNotFound.self) { (continuation: AsyncStream<SingleGroupV2MainViewModelOrNotFound>.Continuation) in
            let model = PreviewsHelper.singleGroupV2MainViewModels[0]
            continuation.yield(.model(model: model))
        }
        return (UUID(), stream)
    }

    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: SingleGroupV2MainView, streamUUID: UUID) {}

}


extension GenericDataSourceForPreviews: ListOfGroupMembersViewDataSource {
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        let otherGroupMembers: [SingleGroupMemberView.Model.Identifier] = PreviewsHelper.groupMembers.map({ .contactIdentifierForExistingGroupForPreviews(groupIdentifier: groupIdentifier, contactIdentifier: $0.contactIdentifier) })
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, streamUUID: UUID, searchText: String?) {}
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, streamUUID: UUID) {}
    
}

extension GenericDataSourceForPreviews: OwnedIdentityAsGroupMemberViewDataSource {
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel>) {
        let stream = AsyncStream(OwnedIdentityAsGroupMemberViewModel.self) { (continuation: AsyncStream<OwnedIdentityAsGroupMemberViewModel>.Continuation) in
            let model = OwnedIdentityAsGroupMemberViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, streamUUID: UUID) {}
    
}


extension GenericDataSourceForPreviews: SingleGroupMemberViewDataSource {
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model>) {
        switch identifier {
            
        case .contactIdentifierForExistingGroupForPreviews(groupIdentifier: _, contactIdentifier: let contactIdentifier),
                .contactIdentifierForCreatingGroupForPreviews(contactIdentifier: let contactIdentifier):
            
            let stream = AsyncStream(SingleGroupMemberView.Model.self) { (continuation: AsyncStream<SingleGroupMemberView.Model>.Continuation) in
                if let groupMember = PreviewsHelper.groupMembers.first(where: { $0.contactIdentifier == contactIdentifier }) {
                    continuation.yield(groupMember)
                }
            }
            
            return (UUID(), stream)
            
        case .objectIDOfPersistedGroupV2Member, .objectIDOfPersistedContact, .objectIDOfPersistedPendingGroupMember:
            throw ObvError.error
        }
    }
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier, streamUUID: UUID) {}
    
}


extension GenericDataSourceForPreviews: OneToOneInvitableViewDataSource {
    
    func getAsyncSequenceOfOneToOneInvitableViewModel(_ view: OneToOneInvitableView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<OneToOneInvitableViewModel>) {
        let stream = AsyncStream(OneToOneInvitableViewModel.self) { (continuation: AsyncStream<OneToOneInvitableViewModel>.Continuation) in
            Task {
                do {
                    let model = OneToOneInvitableViewModel(numberOfGroupMembersThatAreContactsButNotOneToOne: 0, numberOfOneToOneInvitationsSent: 0, numberOfPendingMembersWithNoAssociatedContact: 1, groupHasNoOtherMember: false)
                    continuation.yield(model)
                }
                try! await Task.sleep(seconds: 2)
                do {
                    let model = OneToOneInvitableViewModel(numberOfGroupMembersThatAreContactsButNotOneToOne: 3, numberOfOneToOneInvitationsSent: 3, numberOfPendingMembersWithNoAssociatedContact: 0, groupHasNoOtherMember: false)
                    continuation.yield(model)
                }
            }
        }
        return (UUID(), stream)
    }

    func finishAsyncSequenceOfOneToOneInvitableViewModel(_ view: OneToOneInvitableView, streamUUID: UUID) {}
    
}


extension GenericDataSourceForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
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
        try await Task.sleep(seconds: 2)
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


extension GenericDataSourceForPreviews: EditGroupNameAndPictureViewDataSource {
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.ModelOrNotFound>) {
        let stream = AsyncStream(ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.ModelOrNotFound.self) { (continuation: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.ModelOrNotFound>.Continuation) in
            let model = PreviewsHelper.editGroupNameAndPictureViewModels[0]
            continuation.yield(.model(model))
        }
        return (UUID(), stream)
    }
        
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupNameAndPictureView, streamUUID: UUID) {}
    
}


extension GenericDataSourceForPreviews: EditGroupTypeViewDataSource {
    
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupTypeView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>) {
        let stream = AsyncStream(SingleGroupV2MainViewModelOrNotFound.self) { (continuation: AsyncStream<SingleGroupV2MainViewModelOrNotFound>.Continuation) in
            let model = PreviewsHelper.singleGroupV2MainViewModels[0]
            continuation.yield(.model(model: model))
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupTypeView, streamUUID: UUID) {}
    
}


extension GenericDataSourceForPreviews: FullListOfGroupMembersViewDataSource {
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: FullListOfGroupMembersView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, userIdentifiersOfAddedUsers: [ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier]) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        let stream = AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel> { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 1)
                let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: [])
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: FullListOfGroupMembersView.InternalView, streamUUID: UUID, userIdentifiersOfAddedUsers: [ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier], searchText: String?) {}
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: FullListOfGroupMembersView, streamUUID: UUID) {}
    
    func getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        let stream = AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel> { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 1)
                let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: [])
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(_ view: FullListOfGroupMembersView, streamUUID: UUID) {}
    
    func getAsyncSequenceOfGroupLightweightModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupLightweightModel>) {
        let stream = AsyncStream<ObvGroupLightweightModel> { (continuation: AsyncStream<ObvGroupLightweightModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 1)
                let model = ObvGroupLightweightModel(
                    ownedIdentityIsAdmin: true,
                    groupType: .standard,
                    updateInProgressDuringGroupEdition: false,
                    isKeycloakManaged: false)
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfGroupLightweightModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvTypes.ObvGroupV2Identifier, streamUUID: UUID) {}
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        let stream = AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel> { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 1)
                let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: [])
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: FullListOfGroupMembersView.InternalView, streamUUID: UUID, searchText: String?) {}
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: FullListOfGroupMembersView, streamUUID: UUID) {}
        
}


extension GenericDataSourceForPreviews: SelectUsersToAddViewDataSource {
    
    func getAsyncSequenceOfUsersToAddToCreatingGroup(_ view: SelectUsersToAddView, ownedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        let stream = AsyncStream<SelectUsersToAddViewModel> { (continuation: AsyncStream<SelectUsersToAddViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 1)
                let model = SelectUsersToAddViewModel(
                    textOnEmptySetOfUsers: "Test text on empty set of users",
                    allUserIdentifiers: [])
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func getAsyncSequenceOfUsersToAddToExistingGroup(_ view: SelectUsersToAddView, groupIdentifier: ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        let stream = AsyncStream<SelectUsersToAddViewModel> { (continuation: AsyncStream<SelectUsersToAddViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 1)
                let model = SelectUsersToAddViewModel(
                    textOnEmptySetOfUsers: "Test text on empty set of users",
                    allUserIdentifiers: [])
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfUsersToAdd(_ view: SelectUsersToAddView.InternalView, streamUUID: UUID, searchText: String?) {}
    
    func finishAsyncSequenceOfSelectUsersToAddViewModel(_ view: SelectUsersToAddView, streamUUID: UUID) {}
    
}


extension GenericDataSourceForPreviews: ListOfUsersViewCellDataSource {
    func getAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel.User>) {
        let stream = AsyncStream<SelectUsersToAddViewModel.User> { (continuation: AsyncStream<SelectUsersToAddViewModel.User>.Continuation) in
            // For now, we return nothing. This could be improved.
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier, streamUUID: UUID) {}
    
}
