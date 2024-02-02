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

import UIKit
import SwiftUI
import ObvTypes


protocol SuccessfulTransferConfirmationViewControllerDelegate: AnyObject {
    func userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(controller: SuccessfulTransferConfirmationViewController, transferredOwnedCryptoId: ObvCryptoId, userWantsToAddAnotherProfile: Bool) async
}


final class SuccessfulTransferConfirmationViewController: UIHostingController<SuccessfulTransferConfirmationView>, SuccessfulTransferConfirmationViewActionsProtocol {
    
    private weak var delegate: SuccessfulTransferConfirmationViewControllerDelegate?
    
    init(model: SuccessfulTransferConfirmationView.Model, delegate: SuccessfulTransferConfirmationViewControllerDelegate) {
        let actions = SuccessfulTransferConfirmationViewActions()
        let view = SuccessfulTransferConfirmationView(actions: actions, model: model)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        configureNavigation(animated: false)
    }

    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        configureNavigation(animated: animated)
    }


    private func configureNavigation(animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // SuccessfulTransferConfirmationViewActionsProtocol
    
    func userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(transferredOwnedCryptoId: ObvCryptoId, userWantsToAddAnotherProfile: Bool) async {
        await delegate?.userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(
            controller: self,
            transferredOwnedCryptoId: transferredOwnedCryptoId,
            userWantsToAddAnotherProfile: userWantsToAddAnotherProfile)
    }
    
}


private final class SuccessfulTransferConfirmationViewActions: SuccessfulTransferConfirmationViewActionsProtocol {
    
    weak var delegate: SuccessfulTransferConfirmationViewActionsProtocol?
    
    func userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(transferredOwnedCryptoId: ObvCryptoId, userWantsToAddAnotherProfile: Bool) async {
        await delegate?.userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(
            transferredOwnedCryptoId: transferredOwnedCryptoId,
            userWantsToAddAnotherProfile: userWantsToAddAnotherProfile)
    }
    
}
