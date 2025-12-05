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
import ObvDesignSystem
import ObvTypes
import ObvAppTypes
import ObvUIGroupSharedBetweenV1AndV2


#if DEBUG

@MainActor
class GenericActionsForPreviews {
    
    // Implementing GenericActionsForPreviews in the body, so that the method can be overriden by a subclass
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ view: GroupPublishedDetailsValidationView, publishedDetails: PublishedDetailsValidationViewModel) async throws {}

}

extension GenericActionsForPreviews: PersonalNoteEditorViewActions {
    func userWantsToDismissPersonalNoteEditorView(_ view: ObvDesignSystem.PersonalNoteEditorView) {}
    func userWantsToUpdatePersonalNote(_ view: ObvDesignSystem.PersonalNoteEditorView, with newText: String?, about: ObvDesignSystem.PersonalNoteEditorView.Model.About) {}
}

extension GenericActionsForPreviews: EditGroupTypeViewActionsForEdition {
    //func userWantsToLeaveGroupFlow(_ view: EditGroupTypeView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {}
    func userWantsToUpdateGroupV2(_ view: EditGroupTypeView, groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {}
    //func userChosedGroupTypeAndWantsToSelectAdmins(_ view: EditGroupTypeView, groupIdentifier: ObvTypes.ObvGroupV2Identifier, selectedGroupType: ObvAppTypes.ObvGroupType) {}
    //func userChosedGroupTypeDuringGroupCreation(_ view: EditGroupTypeView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, selectedGroupType: ObvAppTypes.ObvGroupType) {}
}

extension GenericActionsForPreviews: EditGroupNameAndPictureViewActionsProtocol {
    
    func userWantsToSaveImageToTempFile(_ view: EditGroupNameAndPictureView.InternalView, image: UIImage) async throws -> URL {
        return PreviewsHelper.photoURLForGroupPicture[0]
    }
    
    func userWantsToUpdateGroupNameAndPicture(_ view: EditGroupNameAndPictureView.InternalView, groupIdentifier: ObvGroupIdentifier, changes: Set<EditGroupNameAndPictureView.Change>) async throws {
        try await Task.sleep(seconds: 1)
    }
    
    func userWantsToPublishCreatedGroupWithDetails(_ view: EditGroupNameAndPictureView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails) async throws {
        try await Task.sleep(seconds: 1)
    }

    func userWantsObtainAvatar(_ view: EditGroupNameAndPictureView.InternalView, avatarSource: ObvAppTypes.ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        let url: URL
        switch avatarSource {
        case .camera:
            url = PreviewsHelper.photoURLForGroupPicture[2]
        case .photoLibrary:
            url = PreviewsHelper.photoURLForGroupPicture[0]
        case .files:
            url = PreviewsHelper.photoURLForGroupPicture[2]
        }
        return PreviewsHelper.profilePictureForURL[url]!
    }
    
    func userWantsToLeaveGroupFlow(_ view: EditGroupNameAndPictureView, groupIdentifier: ObvGroupV2Identifier) {
        // Nothing to simulate
    }
    
    func groupDetailsWereSuccessfullyUpdated(_ view: EditGroupNameAndPictureView.InternalView, groupIdentifier: ObvGroupV2Identifier) {
        // Nothing to simulate
    }

    func groupWasSuccessfullyCreated(_ view: EditGroupNameAndPictureView.InternalView, ownedCryptoId: ObvCryptoId) {
        // Nothing to simulate
    }
    
}

extension GenericActionsForPreviews: SingleGroupMemberViewActionsProtocol {
    func userWantsToShowOtherUserProfile(_ view: SingleGroupMemberView.InternalView, contactIdentifier: ObvContactIdentifier) async {}
}

extension GenericActionsForPreviews: PublishedDetailsValidationViewActionsProtocol {
    // func userWantsToReplaceTrustedDetailsByPublishedDetails(...) is declared in the body of GenericActionsForPreviews so that it can be overriden
    func userHasSeenPublishedDetails(_ view: GroupPublishedDetailsValidationView, publishedDetails: PublishedDetailsValidationViewModel) async throws {}
}

extension GenericActionsForPreviews: SelectUsersToAddViewActionsForEdition {
    func userWantsToAddSelectedUsersToExistingGroup(_ view: SelectUsersToAddView.InternalView, groupIdentifier: ObvGroupIdentifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {}
    func viewShouldBeDismissed(_ view: SelectUsersToAddView.InternalView) {}
}


extension GenericActionsForPreviews: SingleGroupV2MainViewActionsProtocol {
    func userWantsToUpdateGroupV2(_ view: FullListOfGroupMembersView.InternalView, groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {}
    func userWantsToEditGroupNicknameAndCustomPicture(_ view: SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {}
    func userWantsToLeaveGroup(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws {}
    func userWantsToDisbandGroup(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws {}
    func userWantsToChat(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async {}
    func userWantsToCall(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) {}
    func userWantsToLeaveGroupFlow(_ view: SingleGroupV2MainView) {}
    func userWantsToCloneGroup(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws {}
    func userTappedOnManualResyncOfGroupV2Button(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws {}
}

#endif
