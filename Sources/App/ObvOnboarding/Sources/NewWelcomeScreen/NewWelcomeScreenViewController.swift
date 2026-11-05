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
protocol NewWelcomeScreenViewControllerDelegate: AnyObject {
    func userWantsToCloseOnboarding(controller: NewWelcomeScreenViewController) async
    func userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet(controller: NewWelcomeScreenViewController) async
    func userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile(controller: NewWelcomeScreenViewController) async
    func userWantsToLeaveWelcomeScreenAndFinishOnboarding(controller: NewWelcomeScreenViewController, ownedIdentityThatCanBeOpened: ObvTypes.ObvCryptoId)
}


final class NewWelcomeScreenViewController: UIHostingController<NewWelcomeScreenView>, NewWelcomeScreenViewActionsProtocol {
    
    private weak var delegate: NewWelcomeScreenViewControllerDelegate?
    
    init(delegate: NewWelcomeScreenViewControllerDelegate, dataSource: NewWelcomeScreenViewDataSource, showCloseButton: Bool) {
        let actions = NewWelcomeScreenViewActions()
        let view = NewWelcomeScreenView(actions: actions, dataSource: dataSource, showCloseButton: showCloseButton)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
    }
    
    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        configureNavigation(animated: animated)
    }
    
    
    private func configureNavigation(animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // NewWelcomeScreenViewActionsProtocol
    
    func userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile() async {
        await delegate?.userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile(controller: self)
    }
    
    
    func userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet() async {
        await delegate?.userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet(controller: self)
    }

    func userWantsToLeaveWelcomeScreenAndFinishOnboarding(ownedIdentityThatCanBeOpened: ObvTypes.ObvCryptoId) {
        delegate?.userWantsToLeaveWelcomeScreenAndFinishOnboarding(controller: self, ownedIdentityThatCanBeOpened: ownedIdentityThatCanBeOpened)
    }
    
    
    func userWantsToCloseOnboarding() async {
        await delegate?.userWantsToCloseOnboarding(controller: self)
    }
    
}



private final class NewWelcomeScreenViewActions: NewWelcomeScreenViewActionsProtocol {
        
    weak var delegate: NewWelcomeScreenViewActionsProtocol?
    
    func userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile() async {
        await delegate?.userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile()
    }
    
    
    func userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet() async {
        await delegate?.userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet()
    }

    func userWantsToLeaveWelcomeScreenAndFinishOnboarding(ownedIdentityThatCanBeOpened: ObvTypes.ObvCryptoId) {
        delegate?.userWantsToLeaveWelcomeScreenAndFinishOnboarding(ownedIdentityThatCanBeOpened: ownedIdentityThatCanBeOpened)
    }

    func userWantsToCloseOnboarding() async {
        await delegate?.userWantsToCloseOnboarding()
    }

}
