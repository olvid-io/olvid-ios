/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import SwiftUI
import UIKit
import ObvTypes
import ObvUICoreData


final class OlvidCallViewController: UIHostingController<OlvidCallView<OlvidCall>> {

    private var continuationWhenPresentingMultipleContactsViewController: CheckedContinuation<Set<ObvCryptoId>, Never>?
    
    struct Model {
        let call: OlvidCall
        let manager: OlvidCallManager
    }
    
    init(model: Model) {
        let navigationActions = OlvidCallViewNavigationActions()
        let view = OlvidCallView(model: model.call, actions: model.manager, navigationActions: navigationActions)
        super.init(rootView: view)
        navigationActions.delegate = self
    }
    
    deinit {
        debugPrint("deinit OlvidCallViewController")
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


// MARK: - Implementing OlvidCallViewNavigationActionsProtocol

extension OlvidCallViewController: OlvidCallViewNavigationActionsProtocol {
    
    @MainActor
    func userWantsToAddParticipantToCall(ownedCryptoId: ObvCryptoId, currentOtherParticipants: Set<ObvCryptoId>) async -> Set<ObvCryptoId> {
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<Set<ObvCryptoId>, Never>) in
            
            continuationWhenPresentingMultipleContactsViewController = continuation
            
            let vc = MultipleContactsViewController(
                ownedCryptoId: ownedCryptoId,
                mode: .excluded(from: currentOtherParticipants, oneToOneStatus: .any, requiredCapabilitites: nil),
                button: .floating(title: NSLocalizedString("ADD_SELECTED_CONTACTS_TO_CALL", comment: ""), systemIcon: .phoneFill),
                disableContactsWithoutDevice: true,
                allowMultipleSelection: true,
                showExplanation: false,
                allowEmptySetOfContacts: false,
                textAboveContactList: NSLocalizedString("SELECT_NEW_CALL_PARTICIPANTS", comment: "")) { [weak self] selectedContacts in
                    self?.presentedViewController?.dismiss(animated: true)
                    self?.continuationWhenPresentingMultipleContactsViewController = nil
                    continuation.resume(returning: Set(selectedContacts.map({ $0.cryptoId })))
                } dismissAction: { [weak self] in
                    self?.presentedViewController?.dismiss(animated: true)
                    self?.continuationWhenPresentingMultipleContactsViewController = nil
                    continuation.resume(returning: Set([]))
                }
            
            let nav = UINavigationController(rootViewController: vc)
            
            nav.presentationController?.delegate = self
            
            self.present(nav, animated: true)

        }
        
    }
        
}


// MARK: - UIAdaptivePresentationControllerDelegate

extension OlvidCallViewController: UIAdaptivePresentationControllerDelegate {
    
    /// This `UIAdaptivePresentationControllerDelegate` delegate gets called when the user dismisses the presented `MultipleContactsViewController` manually.
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let continuation = self.continuationWhenPresentingMultipleContactsViewController else { return }
        self.continuationWhenPresentingMultipleContactsViewController = nil
        continuation.resume(returning: Set([]))
    }
    
}

// MARK: - OlvidCallViewNavigationActions

private final class OlvidCallViewNavigationActions: OlvidCallViewNavigationActionsProtocol {
    
    weak var delegate: OlvidCallViewNavigationActionsProtocol?
    
    func userWantsToAddParticipantToCall(ownedCryptoId: ObvCryptoId, currentOtherParticipants: Set<ObvCryptoId>) async -> Set<ObvCryptoId> {
        guard let delegate else { assertionFailure(); return Set([])}
        return await delegate.userWantsToAddParticipantToCall(ownedCryptoId: ownedCryptoId, currentOtherParticipants: currentOtherParticipants)
    }
    
}
