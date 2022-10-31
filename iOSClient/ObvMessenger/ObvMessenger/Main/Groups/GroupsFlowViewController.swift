/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import os.log
import ObvEngine
import ObvTypes


final class GroupsFlowViewController: UINavigationController, ObvFlowController {
    
    // Variables
    
    let ownedCryptoId: ObvCryptoId
    let obvEngine: ObvEngine

    var observationTokens = [NSObjectProtocol]()

    // Constants
    
    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: GroupsFlowViewController.self))

    // Delegate
    
    weak var flowDelegate: ObvFlowControllerDelegate?

    // MARK: - Factory
    
    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine) {
        
        self.ownedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        
        let allGroupsViewController = NewAllGroupsViewController(ownedCryptoId: ownedCryptoId)
        super.init(rootViewController: allGroupsViewController)
        
        allGroupsViewController.delegate = self

    }
    
    override var delegate: UINavigationControllerDelegate? {
        get {
            super.delegate
        }
        set {
            // The ObvUserActivitySingleton properly iff it is the delegate of this UINavigationController
            guard newValue is ObvUserActivitySingleton else { assertionFailure(); return }
            super.delegate = newValue
        }
    }

    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    private func observeContactGroupDeletedNotifications() {
        do {
            let NotificationType = ObvEngineNotification.ContactGroupDeleted.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: OperationQueue.main) { [weak self] (notification) in
                guard let _self = self else { return }
                guard let (_, _, groupUid) = NotificationType.parse(notification) else { return }
                _self.removeGroupViewController(groupUid: groupUid)
            }
            observationTokens.append(token)
        }
    }
}


// MARK: - View controller lifecycle

extension GroupsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = CommonString.Word.Groups
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemName: "person.3", withConfiguration: symbolConfiguration)
        tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
        
        delegate = ObvUserActivitySingleton.shared

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navigationBar.standardAppearance = appearance

        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        
        observeContactGroupDeletedNotifications()
        observePersistedGroupV2WasDeletedNotifications()
        
    }
    
}


// MARK: - NewAllGroupsViewControllerDelegate

extension GroupsFlowViewController: NewAllGroupsViewControllerDelegate {
    
    func userDidSelect(_ contactGroup: PersistedContactGroup, within nav: UINavigationController?) {
        guard let singleGroupVC = try? SingleGroupViewController(persistedContactGroup: contactGroup, obvEngine: obvEngine) else { return }
        singleGroupVC.delegate = self
        pushViewController(singleGroupVC, animated: true)
    }
    
    func userDidSelect(_ group: PersistedGroupV2, within: UINavigationController?) {
        guard let vc = try? SingleGroupV2ViewController(group: group, obvEngine: obvEngine, delegate: self) else { assertionFailure(); return }
        pushViewController(vc, animated: true)
    }
    
    func userWantsToAddContactGroup() {
        assert(Thread.isMainThread)
        let ownedCryptoId = self.ownedCryptoId
        let obvEngine = self.obvEngine
        
        // For now, groups v2 can only be created when beta settings are shown.
        // Otherwise, we only allow the creation of legacy groups.
        
        if ObvMessengerSettings.BetaConfiguration.showBetaSettings || ObvMessengerConstants.developmentMode {
            
            let alert = UIAlertController(title: NSLocalizedString("CHOOSE_GROUP_TYPE_TITLE", comment: ""),
                                          message: NSLocalizedString("CHOOSE_GROUP_TYPE_MESSAGE", comment: ""),
                                          preferredStyleForTraitCollection: self.traitCollection)
            alert.addAction(UIAlertAction(title: NSLocalizedString("CHOOSE_GROUP_V1", comment: ""), style: .default, handler: { [weak self] (action) in
                let groupCreationFlowVC = GroupEditionFlowViewController(ownedCryptoId: ownedCryptoId, editionType: .createGroupV1, obvEngine: obvEngine)
                self?.present(groupCreationFlowVC, animated: true)
            }))
            alert.addAction(UIAlertAction(title: NSLocalizedString("CHOOSE_GROUP_V2", comment: ""), style: .default, handler: { [weak self] (action) in
                let groupCreationFlowVC = GroupEditionFlowViewController(ownedCryptoId: ownedCryptoId, editionType: .createGroupV2, obvEngine: obvEngine)
                self?.present(groupCreationFlowVC, animated: true)
            }))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            
            if let presentedViewController = self.presentedViewController {
                presentedViewController.present(alert, animated: true)
            } else {
                self.present(alert, animated: true)
            }

        } else {

            let groupCreationFlowVC = GroupEditionFlowViewController(ownedCryptoId: ownedCryptoId, editionType: .createGroupV1, obvEngine: obvEngine)
            present(groupCreationFlowVC, animated: true)
            
        }
        
    }
        
    
    @objc
    func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }

}
