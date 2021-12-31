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

final class DiscussionsFlowViewController: UINavigationController, ObvFlowController {

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    var ownedCryptoId: ObvCryptoId!
    private var observationTokens = [NSObjectProtocol]()

    // Factory (required because creating a custom init does not work under iOS 12)
    static func create(ownedCryptoId: ObvCryptoId) -> DiscussionsFlowViewController {

        let recentDiscussionsVC = RecentDiscussionsViewController(ownedCryptoId: ownedCryptoId, logCategory: "RecentDiscussionsViewController")
        recentDiscussionsVC.title = CommonString.Word.Discussions
        let vc = self.init(rootViewController: recentDiscussionsVC)
        
        vc.ownedCryptoId = ownedCryptoId
        
        recentDiscussionsVC.delegate = vc
        
        vc.title = CommonString.Word.Discussions

        if #available(iOS 13, *) {
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
            let image = UIImage(systemName: "bubble.left.and.bubble.right", withConfiguration: symbolConfiguration)
            vc.tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
        } else {
            let iconImage = UIImage(named: "tabbar_icon_chat")
            vc.tabBarItem = UITabBarItem(title: vc.title, image: iconImage, tag: 0)
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
    }
        
    // Required in order to prevent a crash under iOS 12
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }
 
    weak var flowDelegate: ObvFlowControllerDelegate?
    
}


// MARK: - Lifecycle

extension DiscussionsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 13, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            navigationBar.standardAppearance = appearance
        }
        
    }
    
}

// MARK: - RecentDiscussionsViewControllerDelegate and DiscussionPickerViewControllerDelegate

extension DiscussionsFlowViewController: RecentDiscussionsViewControllerDelegate {
        
    func userWantsToDeleteDiscussion(_ persistedDiscussion: PersistedDiscussion, completionHandler: @escaping (Bool) -> Void) {
        
        assert(Thread.isMainThread)
        
        let alert = UIAlertController(title: Strings.AlertConfirmAllDiscussionMessagesDeletion.title,
                                      message: Strings.AlertConfirmAllDiscussionMessagesDeletion.message,
                                      preferredStyleForTraitCollection: self.traitCollection)
        if persistedDiscussion is PersistedOneToOneDiscussion || persistedDiscussion is PersistedGroupDiscussion {
            alert.addAction(UIAlertAction(title: Strings.AlertConfirmAllDiscussionMessagesDeletion.actionDeleteAllGlobally, style: .destructive, handler: { [weak self] (action) in
                alert.dismiss(animated: true) {
                    self?.ensureUserWantsToGloballyDeleteDiscussion(persistedDiscussion, completionHandler: completionHandler)
                }
            }))
        }
        alert.addAction(UIAlertAction(title: Strings.AlertConfirmAllDiscussionMessagesDeletion.actionDeleteAll, style: .destructive, handler: { (action) in
            ObvMessengerInternalNotification.userRequestedDeletionOfPersistedDiscussion(persistedDiscussionObjectID: persistedDiscussion.objectID, deletionType: .local, completionHandler: completionHandler)
                .postOnDispatchQueue()
        }))
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { (action) in
            completionHandler(false)
        })
        
        present(alert, animated: true)
        
    }
    
    func ensureUserWantsToGloballyDeleteDiscussion(_ discussion: PersistedDiscussion, completionHandler: @escaping (Bool) -> Void) {
        assert(Thread.current.isMainThread)
        
        let alert = UIAlertController(title: Strings.AlertConfirmAllDiscussionMessagesDeletionGlobally.title,
                                      message: Strings.AlertConfirmAllDiscussionMessagesDeletionGlobally.message,
                                      preferredStyleForTraitCollection: self.traitCollection)
        alert.addAction(UIAlertAction(title: Strings.AlertConfirmAllDiscussionMessagesDeletion.actionDeleteAllGlobally, style: .destructive, handler: { (action) in
            ObvMessengerInternalNotification.userRequestedDeletionOfPersistedDiscussion(persistedDiscussionObjectID: discussion.objectID, deletionType: .global, completionHandler: completionHandler)
                .postOnDispatchQueue()
        }))
        alert.addAction(UIAlertAction.init(title: CommonString.Word.Cancel, style: .cancel) { (action) in
            completionHandler(false)
        })
        present(alert, animated: true)
    }
    
    
    @objc
    func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }

    func userAskedToRefreshDiscussions(completionHandler: @escaping () -> Void) {
        flowDelegate?.userAskedToRefreshDiscussions(completionHandler: completionHandler)
    }

    func observePersistedDiscussionWasLockedNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeNewLockedPersistedDiscussion(queue: OperationQueue.main) { [weak self] (previousDiscussionUriRepresentation, newLockedDiscussionId) in
            guard let _self = self else { return }
            _self.replaceDiscussionViewController(discussionToReplace: previousDiscussionUriRepresentation, newDiscussionId: newLockedDiscussionId)
        })
    }
}
