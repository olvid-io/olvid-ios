/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
        let chooseParticipantsToAddAction = OlvidCallViewAddParticipantsActions()
        let view = OlvidCallView(model: model.call, actions: model.manager, chooseParticipantsToAddAction: chooseParticipantsToAddAction)
        super.init(rootView: view)
        chooseParticipantsToAddAction.delegate = self
    }
    
    deinit {
        debugPrint("deinit OlvidCallViewController")
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //overrideUserInterfaceStyle = .dark
    }
    
}


// MARK: - Implementing OlvidCallAddParticipantActionsProtocol

extension OlvidCallViewController: OlvidCallAddParticipantsActionsProtocol {
    
    @MainActor
    func userWantsToAddParticipantToCall(ownedCryptoId: ObvCryptoId, currentOtherParticipants: Set<ObvCryptoId>) async -> Set<ObvCryptoId> {
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<Set<ObvCryptoId>, Never>) in
            
            continuationWhenPresentingMultipleContactsViewController = continuation
            
            let verticalConfiguration = VerticalUsersViewConfiguration(
                showExplanation: false,
                disableUsersWithoutDevice: true,
                allowMultipleSelection: true,
                textAboveUserList: nil,
                selectionStyle: .checkmark)
            let horizontalConfiguration = HorizontalUsersViewConfiguration(
                textOnEmptySetOfUsers: NSLocalizedString("SELECT_NEW_CALL_PARTICIPANTS", comment: ""),
                canEditUsers: true)
            let buttonConfiguration = HorizontalAndVerticalUsersViewButtonConfiguration(
                title: NSLocalizedString("ADD_SELECTED_CONTACTS_TO_CALL", comment: ""),
                systemIcon: .phoneFill,
                action: { [weak self] selectedContacts in
                    self?.presentedViewController?.dismiss(animated: true)
                    self?.continuationWhenPresentingMultipleContactsViewController = nil
                    continuation.resume(returning: selectedContacts)
                },
                allowEmptySetOfContacts: false)
            let configuration = HorizontalAndVerticalUsersViewConfiguration(
                verticalConfiguration: verticalConfiguration,
                horizontalConfiguration: horizontalConfiguration,
                buttonConfiguration: buttonConfiguration)

            let multipleContactsVC = MultipleUsersHostingViewController(
                ownedCryptoId: ownedCryptoId,
                mode: .excluded(from: currentOtherParticipants, oneToOneStatus: .any, requiredCapabilitites: nil),
                configuration: configuration,
                delegate: nil)

            multipleContactsVC.navigationItem.searchController = multipleContactsVC.searchController
            multipleContactsVC.navigationItem.hidesSearchBarWhenScrolling = false

            multipleContactsVC.navigationItem.rightBarButtonItem = .init(systemItem: .cancel, primaryAction: .init(handler: { _ in
                multipleContactsVC.dismiss(animated: true)
            }))

            let nav = UINavigationController(rootViewController: multipleContactsVC)
            
            nav.presentationController?.delegate = self
            
            (self.presentedViewController ?? self).present(nav, animated: true)

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

// MARK: - OlvidCallViewAddParticipantsActions

private final class OlvidCallViewAddParticipantsActions: OlvidCallAddParticipantsActionsProtocol {
    
    weak var delegate: OlvidCallAddParticipantsActionsProtocol?
    
    func userWantsToAddParticipantToCall(ownedCryptoId: ObvCryptoId, currentOtherParticipants: Set<ObvCryptoId>) async -> Set<ObvCryptoId> {
        guard let delegate else { assertionFailure(); return Set([])}
        return await delegate.userWantsToAddParticipantToCall(ownedCryptoId: ownedCryptoId, currentOtherParticipants: currentOtherParticipants)
    }
    
}
