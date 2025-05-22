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
import ObvDesignSystem
import ObvTypes
import ObvAppTypes


@MainActor
protocol EditGroupNameAndPictureViewControllerDelegate: AnyObject {
    func userWantsToLeaveGroupFlow(_ vc: EditGroupNameAndPictureViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier)
    func userWantsObtainAvatar(_ vc: EditGroupNameAndPictureViewController, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    func userWantsToSaveImageToTempFile(_ vc: EditGroupNameAndPictureViewController, image: UIImage) async throws -> URL
    func userWantsToUpdateGroupV2(_ vc: EditGroupNameAndPictureViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws
    func userWantsToCancelAndDismiss(_ vc: EditGroupNameAndPictureViewController)
    func groupDetailsWereSuccessfullyUpdated(_ vc: EditGroupNameAndPictureViewController, groupIdentifier: ObvGroupV2Identifier)
    func userWantsToPublishCreatedGroupWithDetails(_ vc: EditGroupNameAndPictureViewController, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails) async throws
    func groupWasSuccessfullyCreated(_ vc: EditGroupNameAndPictureViewController, ownedCryptoId: ObvTypes.ObvCryptoId)
}




final class EditGroupNameAndPictureViewController: UIHostingController<EditGroupNameAndPictureView> {
    
    private let mode: EditGroupNameAndPictureView.Mode
    private let viewsActions = ViewsActions()
    private weak var internalDelegate: EditGroupNameAndPictureViewControllerDelegate?
    
    init(mode: EditGroupNameAndPictureView.Mode, dataSource: EditGroupNameAndPictureViewDataSource, delegate: EditGroupNameAndPictureViewControllerDelegate) {
        self.mode = mode
        let rootView = EditGroupNameAndPictureView(mode: mode, dataSource: dataSource, actions: viewsActions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        viewsActions.delegate = self
        
        self.title = String(localizedInThisBundle: "EDIT_GROUP_DETAILS")
        
    }
    
    
    var groupIdentifier: ObvGroupV2Identifier? {
        switch mode {
        case .creation: return nil
        case .edition(groupIdentifier: let groupIdentifier): return groupIdentifier
        }
    }
    
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        
        switch mode {
        case .creation:
            navigationItem.rightBarButtonItem = barButtonItem
        case .edition:
            if self.isBeingPresented || self.navigationController?.isBeingPresented == true {
                navigationItem.leftBarButtonItem = barButtonItem
            }
        }

    }
    
    enum ObvError: Error {
        case delegateIsNil
    }

}


extension EditGroupNameAndPictureViewController: EditGroupNameAndPictureViewActionsProtocol {
    
    func userWantsToLeaveGroupFlow(groupIdentifier: ObvGroupV2Identifier) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToLeaveGroupFlow(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsObtainAvatar(avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await internalDelegate.userWantsObtainAvatar(self, avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    func userWantsToSaveImageToTempFile(image: UIImage) async throws -> URL {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await internalDelegate.userWantsToSaveImageToTempFile(self, image: image)
    }
    
    func userWantsToUpdateGroupV2(groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await internalDelegate.userWantsToUpdateGroupV2(self, groupIdentifier: groupIdentifier, changeset: changeset)
    }

    func groupDetailsWereSuccessfullyUpdated(groupIdentifier: ObvGroupV2Identifier) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.groupDetailsWereSuccessfullyUpdated(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToPublishCreatedGroupWithDetails(creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await internalDelegate.userWantsToPublishCreatedGroupWithDetails(self, creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, groupDetails: groupDetails)
    }
    
    func groupWasSuccessfullyCreated(ownedCryptoId: ObvTypes.ObvCryptoId) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.groupWasSuccessfullyCreated(self, ownedCryptoId: ownedCryptoId)
    }
    
}


private final class ViewsActions: EditGroupNameAndPictureViewActionsProtocol {
                
    weak var delegate: EditGroupNameAndPictureViewActionsProtocol?
    
    func userWantsToLeaveGroupFlow(groupIdentifier: ObvGroupV2Identifier) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToLeaveGroupFlow(groupIdentifier: groupIdentifier)
    }
    
    func userWantsObtainAvatar(avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsObtainAvatar(avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    enum ObvError: Error {
        case delegateIsNil
    }

    func userWantsToSaveImageToTempFile(image: UIImage) async throws -> URL {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToSaveImageToTempFile(image: image)
    }
    
    func userWantsToUpdateGroupV2(groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToUpdateGroupV2(groupIdentifier: groupIdentifier, changeset: changeset)
    }

    func groupDetailsWereSuccessfullyUpdated(groupIdentifier: ObvGroupV2Identifier) {
        guard let delegate else { assertionFailure(); return }
        delegate.groupDetailsWereSuccessfullyUpdated(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToPublishCreatedGroupWithDetails(creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToPublishCreatedGroupWithDetails(creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, groupDetails: groupDetails)
    }
    
    func groupWasSuccessfullyCreated(ownedCryptoId: ObvTypes.ObvCryptoId) {
        guard let delegate else { assertionFailure(); return }
        delegate.groupWasSuccessfullyCreated(ownedCryptoId: ownedCryptoId)
    }

}
