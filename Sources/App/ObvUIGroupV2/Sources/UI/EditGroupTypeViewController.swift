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


@MainActor
protocol EditGroupTypeViewControllerDelegate: AnyObject {
    func userWantsToLeaveGroupFlow(_ vc: EditGroupTypeViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier)
    func userWantsToUpdateGroupV2(_ vc: EditGroupTypeViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws
    func userChosedGroupTypeAndWantsToSelectAdmins(_ vc: EditGroupTypeViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, selectedGroupType: ObvAppTypes.ObvGroupType)
    func userWantsToCancelAndDismiss(_ vc: EditGroupTypeViewController)
    func userChosedGroupTypeDuringGroupCreation(_ vc: EditGroupTypeViewController, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, selectedGroupType: ObvGroupType)
}


final class EditGroupTypeViewController: UIHostingController<EditGroupTypeView> {
    
    private let mode: EditGroupTypeView.Mode
    private let viewsActions = ViewsActions()
    private weak var internalDelegate: EditGroupTypeViewControllerDelegate?
    
    init(mode: EditGroupTypeView.Mode, dataSource: EditGroupTypeViewDataSource, delegate: EditGroupTypeViewControllerDelegate) {
        self.mode = mode
        let rootView = EditGroupTypeView(mode: mode,
                                         dataSource: dataSource,
                                         actions: viewsActions)
        super.init(rootView: rootView)
        internalDelegate = delegate
        viewsActions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var groupIdentifier: ObvGroupV2Identifier? {
        switch mode {
        case .creation: return nil
        case .edition(groupIdentifier: let groupIdentifier): return groupIdentifier
        }
    }
    
    enum ObvError: Error {
        case internalDelegateIsNil
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

}


// MARK: - Implementing EditGroupTypeViewActionsProtocol

extension EditGroupTypeViewController: EditGroupTypeViewActionsProtocol {
    
    func userWantsToLeaveGroupFlow(groupIdentifier: ObvGroupV2Identifier) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToLeaveGroupFlow(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToUpdateGroupV2(groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        guard let internalDelegate else { assertionFailure(); return }
        try await internalDelegate.userWantsToUpdateGroupV2(self, groupIdentifier: groupIdentifier, changeset: changeset)
    }
    
    func userChosedGroupTypeAndWantsToSelectAdmins(groupIdentifier: ObvTypes.ObvGroupV2Identifier, selectedGroupType: ObvAppTypes.ObvGroupType) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userChosedGroupTypeAndWantsToSelectAdmins(self, groupIdentifier: groupIdentifier, selectedGroupType: selectedGroupType)
    }
    
    func userChosedGroupTypeDuringGroupCreation(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, selectedGroupType: ObvGroupType) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userChosedGroupTypeDuringGroupCreation(self, creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, selectedGroupType: selectedGroupType)
    }
    
}


private final class ViewsActions: EditGroupTypeViewActionsProtocol {
    
    weak var delegate: EditGroupTypeViewActionsProtocol?
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
    func userWantsToLeaveGroupFlow(groupIdentifier: ObvGroupV2Identifier) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToLeaveGroupFlow(groupIdentifier: groupIdentifier)
    }
    
    func userChosedGroupTypeDuringGroupCreation(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, selectedGroupType: ObvGroupType) {
        guard let delegate else { assertionFailure(); return }
        delegate.userChosedGroupTypeDuringGroupCreation(creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, selectedGroupType: selectedGroupType)
    }
    
    func userWantsToUpdateGroupV2(groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToUpdateGroupV2(groupIdentifier: groupIdentifier, changeset: changeset)
    }
    
    func userChosedGroupTypeAndWantsToSelectAdmins(groupIdentifier: ObvTypes.ObvGroupV2Identifier, selectedGroupType: ObvAppTypes.ObvGroupType) {
        guard let delegate else { assertionFailure(); return }
        delegate.userChosedGroupTypeAndWantsToSelectAdmins(groupIdentifier: groupIdentifier, selectedGroupType: selectedGroupType)
    }
    
}
