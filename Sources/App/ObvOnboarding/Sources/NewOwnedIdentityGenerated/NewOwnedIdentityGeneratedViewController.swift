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


import SwiftUI
import UIKit


protocol NewOwnedIdentityGeneratedViewControllerDelegate: AnyObject {
    func userWantsToStartUsingOlvid(controller: NewOwnedIdentityGeneratedViewController) async
}

final class NewOwnedIdentityGeneratedViewController: UIHostingController<NewOwnedIdentityGeneratedView>, NewOwnedIdentityGeneratedViewActionsProtocol {

    private weak var delegate: NewOwnedIdentityGeneratedViewControllerDelegate?
    
    init(delegate: NewOwnedIdentityGeneratedViewControllerDelegate) {
        let actions = NewOwnedIdentityGeneratedViewActions()
        let view = NewOwnedIdentityGeneratedView(actions: actions)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
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
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    // NewOwnedIdentityGeneratedViewActions
    
    func startUsingOlvidAction() async {
        await delegate?.userWantsToStartUsingOlvid(controller: self)
    }
    
}


private final class NewOwnedIdentityGeneratedViewActions: NewOwnedIdentityGeneratedViewActionsProtocol {
    
    weak var delegate: NewOwnedIdentityGeneratedViewActionsProtocol?
    
    func startUsingOlvidAction() async {
        await delegate?.startUsingOlvidAction()
    }
    
}
