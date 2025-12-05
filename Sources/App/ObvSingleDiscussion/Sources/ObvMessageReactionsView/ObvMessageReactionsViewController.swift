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
import UIKit
import ObvDesignSystem

@MainActor
public protocol ObvMessageReactionsViewControllerDelegate: AnyObject {
    func userWantsToRemoveReaction(_ vc: ObvMessageReactionsViewController, reactionIdentifier: ObvMessageReactionsViewModel.ReactionIdentifier) async throws
    func userWantsToAddReactionToFavorites(_ vc: ObvMessageReactionsViewController, emoji: Character) async throws
    func userWantsToRemoveReactionFromFavorites(_ vc: ObvMessageReactionsViewController, emoji: Character) async throws
    func userWantsToDismissObvMessageReactionsViewController(_ vc: ObvMessageReactionsViewController)
}


public final class ObvMessageReactionsViewController: UIHostingController<ObvMessageReactionsView> {
    
    private let actions = ViewsActions()
    private weak var internalDelegate: ObvMessageReactionsViewControllerDelegate?
    
    public init(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier, dataSource: ObvMessageReactionsViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource, delegate: ObvMessageReactionsViewControllerDelegate) {
        let rootView = ObvMessageReactionsView(messageIdentifier: messageIdentifier, dataSource: dataSource, avatarViewDataSource: avatarViewDataSource, actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        self.actions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


extension ObvMessageReactionsViewController: ObvMessageReactionsViewActionsProtocol {
    
    func userWantsToRemoveReaction(reactionIdentifier: ObvMessageReactionsViewModel.ReactionIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        try await internalDelegate.userWantsToRemoveReaction(self, reactionIdentifier: reactionIdentifier)
    }
    
    func userWantsToAddReactionToFavorites(emoji: Character) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        try await internalDelegate.userWantsToAddReactionToFavorites(self, emoji: emoji)
    }
    
    func userWantsToRemoveReactionFromFavorites(emoji: Character) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        try await internalDelegate.userWantsToRemoveReactionFromFavorites(self, emoji: emoji)
    }

    func userWantsToDismissObvMessageReactionsView() {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToDismissObvMessageReactionsViewController(self)
    }
    
}


// MARK: - Errors

extension ObvMessageReactionsViewController {
    
    enum ObvError: Error {
        case internalDelegateIsNil
    }
    
}


// MARK: - View's actions

private final class ViewsActions: ObvMessageReactionsViewActionsProtocol {
    
    weak var delegate: ObvMessageReactionsViewActionsProtocol?
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
    func userWantsToRemoveReaction(reactionIdentifier: ObvMessageReactionsViewModel.ReactionIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToRemoveReaction(reactionIdentifier: reactionIdentifier)
    }
    
    func userWantsToAddReactionToFavorites(emoji: Character) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToAddReactionToFavorites(emoji: emoji)
    }
    
    func userWantsToRemoveReactionFromFavorites(emoji: Character) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToRemoveReactionFromFavorites(emoji: emoji)
    }
    
    func userWantsToDismissObvMessageReactionsView() {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToDismissObvMessageReactionsView()
    }
    
}
