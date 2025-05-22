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
protocol OnetoOneInvitableGroupMembersViewControllerDelegate: AnyObject {
    func userWantsToSendOneToOneInvitationTo(_ vc: OnetoOneInvitableGroupMembersViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    func userWantsToCancelOneToOneInvitationSentTo(_ vc: OnetoOneInvitableGroupMembersViewController, contactIdentifier: ObvContactIdentifier) async throws
    func userWantsToSendOneToOneInvitationsTo(_ vc: OnetoOneInvitableGroupMembersViewController, contactIdentifiers: [OnetoOneInvitableGroupMembersViewModel.Identifier]) async throws
}

final class OnetoOneInvitableGroupMembersViewController: UIHostingController<OnetoOneInvitableGroupMembersView> {
    
    private let viewsActions = ViewsActions()
    private weak var internalDelegate: OnetoOneInvitableGroupMembersViewControllerDelegate?
    let groupIdentifier: ObvGroupV2Identifier
    
    init(groupIdentifier: ObvGroupV2Identifier, dataSource: OnetoOneInvitableGroupMembersViewDataSource, delegate: OnetoOneInvitableGroupMembersViewControllerDelegate) {
        self.groupIdentifier = groupIdentifier
        let rootView = OnetoOneInvitableGroupMembersView(groupIdentifier: groupIdentifier, dataSource: dataSource, actions: viewsActions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        self.viewsActions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
 
    enum ObvError: Error {
        case internalDelegateIsNil
    }
}


// MARK: - Implementing OnetoOneInvitableGroupMembersViewActionsProtocol

extension OnetoOneInvitableGroupMembersViewController: OnetoOneInvitableGroupMembersViewActionsProtocol {
    
    func userWantsToSendOneToOneInvitationTo(contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        try await internalDelegate.userWantsToSendOneToOneInvitationTo(self, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToCancelOneToOneInvitationSentTo(contactIdentifier: ObvContactIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        try await internalDelegate.userWantsToCancelOneToOneInvitationSentTo(self, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToSendOneToOneInvitationsTo(contactIdentifiers: [OnetoOneInvitableGroupMembersViewModel.Identifier]) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        try await internalDelegate.userWantsToSendOneToOneInvitationsTo(self, contactIdentifiers: contactIdentifiers)
    }
    
}


// MARK: - Views actions

final private class ViewsActions: OnetoOneInvitableGroupMembersViewActionsProtocol {
    
    weak var delegate: OnetoOneInvitableGroupMembersViewActionsProtocol?
    
    func userWantsToSendOneToOneInvitationTo(contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToSendOneToOneInvitationTo(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToCancelOneToOneInvitationSentTo(contactIdentifier: ObvContactIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToCancelOneToOneInvitationSentTo(contactIdentifier: contactIdentifier)
    }

    func userWantsToSendOneToOneInvitationsTo(contactIdentifiers: [OnetoOneInvitableGroupMembersViewModel.Identifier]) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToSendOneToOneInvitationsTo(contactIdentifiers: contactIdentifiers)
    }
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}
