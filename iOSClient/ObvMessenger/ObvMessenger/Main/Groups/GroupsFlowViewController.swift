/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
    
    private(set) var ownedCryptoId: ObvCryptoId!

    private var observationTokens = [NSObjectProtocol]()

    // Constants
    
    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    // Delegate
    
    weak var flowDelegate: ObvFlowControllerDelegate?

    // MARK: - Factory
    
    // Factory (required because creating a custom init does not work under iOS 12)
    static func create(ownedCryptoId: ObvCryptoId) -> GroupsFlowViewController {

        let allGroupsViewController = AllGroupsViewController(ownedCryptoId: ownedCryptoId)
        let vc = self.init(rootViewController: allGroupsViewController)

        vc.ownedCryptoId = ownedCryptoId

        allGroupsViewController.delegate = vc

        vc.title = CommonString.Word.Groups
        
        if #available(iOS 13, *) {
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
            let image = UIImage(systemName: "person.3", withConfiguration: symbolConfiguration)
            vc.tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
        } else {
            let iconImage = UIImage(named: "tabbar_icon_groups")
            vc.tabBarItem = UITabBarItem(title: CommonString.Word.Groups, image: iconImage, tag: 0)
        }
        
        vc.delegate = ObvUserActivitySingleton.shared

        return vc
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

    
    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)

        observePersistedDiscussionWasLockedNotifications()
        observeContactGroupDeletedNotifications()
    }
        
    // Required in order to prevent a crash under iOS 12
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    func observePersistedDiscussionWasLockedNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeNewLockedPersistedDiscussion(queue: OperationQueue.main) { [weak self] (previousDiscussionUriRepresentation, newLockedDiscussionId) in
            guard let _self = self else { return }
            _self.replaceDiscussionViewController(discussionToReplace: previousDiscussionUriRepresentation, newDiscussionId: newLockedDiscussionId)
        })
    }

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
        
        if #available(iOS 13, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            navigationBar.standardAppearance = appearance
        }

        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
    }
    
}


// MARK: - AllGroupsViewControllerDelegate

extension GroupsFlowViewController: AllGroupsViewControllerDelegate {
    
    func userDidSelect(_ contactGroup: PersistedContactGroup, within nav: UINavigationController?) {
        guard let singleGroupVC = try? SingleGroupViewController(persistedContactGroup: contactGroup) else { return }
        singleGroupVC.delegate = self
        pushViewController(singleGroupVC, animated: true)
    }
    
    func userWantsToAddContactGroup() {
        let groupCreationFlowVC = OwnedGroupEditionFlowViewController(ownedCryptoId: ownedCryptoId, editionType: .create)
        DispatchQueue.main.async { [weak self] in
            self?.present(groupCreationFlowVC, animated: true)
        }

    }
    
    
    @objc
    func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }

}
