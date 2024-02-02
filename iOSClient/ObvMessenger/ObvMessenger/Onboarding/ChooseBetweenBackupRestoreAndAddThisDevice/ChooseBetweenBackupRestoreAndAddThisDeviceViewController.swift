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


protocol ChooseBetweenBackupRestoreAndAddThisDeviceViewControllerDelegate: AnyObject {
    func userWantsToRestoreBackup(controller: ChooseBetweenBackupRestoreAndAddThisDeviceViewController) async
    func userWantsToActivateHerProfileOnThisDevice(controller: ChooseBetweenBackupRestoreAndAddThisDeviceViewController) async
    func userIndicatedHerProfileIsManagedByOrganisation(controller: ChooseBetweenBackupRestoreAndAddThisDeviceViewController) async
}


final class ChooseBetweenBackupRestoreAndAddThisDeviceViewController: UIHostingController<ChooseBetweenBackupRestoreAndAddThisDeviceView>, ChooseBetweenBackupRestoreAndAddThisDeviceViewActionsProtocol {
    
    weak var delegate: ChooseBetweenBackupRestoreAndAddThisDeviceViewControllerDelegate?
    
    init(delegate: ChooseBetweenBackupRestoreAndAddThisDeviceViewControllerDelegate) {
        let actions = ChooseBetweenBackupRestoreAndAddThisDeviceViewActions()
        let view = ChooseBetweenBackupRestoreAndAddThisDeviceView(actions: actions)
        super.init(rootView: view)
        actions.delegate = self
        self.delegate = delegate
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

    // ChooseBetweenBackupRestoreAndAddThisDeviceViewActionsProtocol
    
    func userWantsToRestoreBackup() {
        Task { await delegate?.userWantsToRestoreBackup(controller: self) }
    }
    
    func userWantsToActivateHerProfileOnThisDevice() {
        Task { await delegate?.userWantsToActivateHerProfileOnThisDevice(controller: self) }
    }
    
    func userIndicatedHerProfileIsManagedByOrganisation() {
        Task { await delegate?.userIndicatedHerProfileIsManagedByOrganisation(controller: self) }
    }
    
}


// MARK: - ChooseBetweenBackupRestoreAndAddThisDeviceViewActions

private final class ChooseBetweenBackupRestoreAndAddThisDeviceViewActions: ChooseBetweenBackupRestoreAndAddThisDeviceViewActionsProtocol {
    
    weak var delegate: ChooseBetweenBackupRestoreAndAddThisDeviceViewActionsProtocol?
    
    func userWantsToRestoreBackup() {
        delegate?.userWantsToRestoreBackup()
    }
    
    func userWantsToActivateHerProfileOnThisDevice() {
        delegate?.userWantsToActivateHerProfileOnThisDevice()
    }
    
    func userIndicatedHerProfileIsManagedByOrganisation() {
        delegate?.userIndicatedHerProfileIsManagedByOrganisation()
    }
    
    
}
