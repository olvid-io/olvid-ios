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


protocol CurrentDeviceNameChooserViewControllerDelegate: AnyObject {
    func userWantsToCloseOnboarding(controller: CurrentDeviceNameChooserViewController) async
    func userDidChooseCurrentDeviceName(controller: CurrentDeviceNameChooserViewController, deviceName: String) async
}


@MainActor
final class CurrentDeviceNameChooserViewController: UIHostingController<CurrentDeviceNameChooserView>, CurrentDeviceNameChooserViewActionsProtocol {
        
    private weak var delegate: CurrentDeviceNameChooserViewControllerDelegate?
    
    init(model: CurrentDeviceNameChooserView.Model, delegate: CurrentDeviceNameChooserViewControllerDelegate, showCloseButton: Bool) {
        let actions = CurrentDeviceNameChooserViewActions()
        let view = CurrentDeviceNameChooserView(actions: actions, model: model, showCloseButton: showCloseButton)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
        configureNavigation(animated: false)
    }
    
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation(animated: false)
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureNavigation(animated: animated)
    }
    
    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        configureNavigation(animated: animated)
    }
    

    private func configureNavigation(animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    
    // CurrentDeviceNameChooserViewActionsProtocol

    func userDidChooseCurrentDeviceName(deviceName: String) async {
        await delegate?.userDidChooseCurrentDeviceName(controller: self, deviceName: deviceName)
    }

    
    func userWantsToCloseOnboarding() async {
        await delegate?.userWantsToCloseOnboarding(controller: self)
    }

}




private final class CurrentDeviceNameChooserViewActions: CurrentDeviceNameChooserViewActionsProtocol {
    
    weak var delegate: CurrentDeviceNameChooserViewActionsProtocol?
        
    func userDidChooseCurrentDeviceName(deviceName: String) async {
        await delegate?.userDidChooseCurrentDeviceName(deviceName: deviceName)
    }
    
    func userWantsToCloseOnboarding() async {
        await delegate?.userWantsToCloseOnboarding()
    }
    
}

