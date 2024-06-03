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


protocol NewAutorisationRequesterViewControllerDelegate: AnyObject {
    func requestAutorisation(autorisationRequester: NewAutorisationRequesterViewController, now: Bool, for autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory) async
}


final class NewAutorisationRequesterViewController: UIHostingController<NewAutorisationRequesterView>, NewAutorisationRequesterViewActionsProtocol {
    
    enum AutorisationCategory {
        case localNotifications
        case recordPermission
    }
    
    weak var delegate: NewAutorisationRequesterViewControllerDelegate?

    init(autorisationCategory: AutorisationCategory, delegate: NewAutorisationRequesterViewControllerDelegate) {
        let actions = NewAutorisationRequesterViewActions()
        
        let view = NewAutorisationRequesterView(autorisationCategory: autorisationCategory, actions: actions)
        super.init(rootView: view)
        
        
        actions.delegate = self
        self.delegate = delegate
    }
    
    deinit {
        debugPrint("NewAutorisationRequesterViewController deinit")
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
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationItem.hidesBackButton = true
    }

    // NewAutorisationRequesterViewActionsProtocol
    
    func requestAutorisation(now: Bool, for autorisationCategory: AutorisationCategory) async {
        await delegate?.requestAutorisation(autorisationRequester: self, now: now, for: autorisationCategory)
    }
    
}


private final class NewAutorisationRequesterViewActions: NewAutorisationRequesterViewActionsProtocol {
    weak var delegate: NewAutorisationRequesterViewActionsProtocol?

    func requestAutorisation(now: Bool, for autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory) async {
        await delegate?.requestAutorisation(now: now, for: autorisationCategory)
    }
            
}
