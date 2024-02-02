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


protocol NewWelcomeScreenViewControllerDelegate: AnyObject {
    func userWantsToCloseOnboarding(controller: NewWelcomeScreenViewController) async
    func userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet(controller: NewWelcomeScreenViewController) async
    func userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile(controller: NewWelcomeScreenViewController) async
}


final class NewWelcomeScreenViewController: UIHostingController<NewWelcomeScreenView>, NewWelcomeScreenViewActionsProtocol {
    
    private weak var delegate: NewWelcomeScreenViewControllerDelegate?
    
    private let showCloseButton: Bool
    
    init(delegate: NewWelcomeScreenViewControllerDelegate, showCloseButton: Bool) {
        self.showCloseButton = showCloseButton
        let actions = NewWelcomeScreenViewActions()
        let view = NewWelcomeScreenView(actions: actions)
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
        if showCloseButton {
            let handler: UIActionHandler = { [weak self] _ in self?.closeAction() }
            let closeButton = UIBarButtonItem(systemItem: .close, primaryAction: .init(handler: handler))
            navigationItem.rightBarButtonItem = closeButton
        }
    }
    
    
    private func closeAction() {
        Task { [weak self] in
            guard let self else { return }
            await delegate?.userWantsToCloseOnboarding(controller: self)
        }
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

}



private final class NewWelcomeScreenViewActions: NewWelcomeScreenViewActionsProtocol {
    
    weak var delegate: NewWelcomeScreenViewActionsProtocol?
    
    func userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile() async {
        await delegate?.userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile()
    }
    
    
    func userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet() async {
        await delegate?.userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet()
    }

}
