/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvTypes
import ObvEngine
import ObvUICoreData


final class DiscussionsFlowViewController: UINavigationController, ObvFlowController {

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: DiscussionsFlowViewController.self))

    private(set) var currentOwnedCryptoId: ObvCryptoId
    let obvEngine: ObvEngine
    
    static let errorDomain = "DiscussionsFlowViewController"

    var observationTokens = [NSObjectProtocol]()

    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine) {

        self.currentOwnedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        
        let recentDiscussionsVC = RecentDiscussionsViewController(ownedCryptoId: ownedCryptoId, logCategory: "RecentDiscussionsViewController")
        recentDiscussionsVC.setTitle(CommonString.Word.Discussions)
        super.init(rootViewController: recentDiscussionsVC)

        recentDiscussionsVC.delegate = self

    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
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
 
    weak var flowDelegate: ObvFlowControllerDelegate?
    
}


// MARK: - Lifecycle

extension DiscussionsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = CommonString.Word.Discussions

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemName: "bubble.left.and.bubble.right", withConfiguration: symbolConfiguration)
        tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)

        delegate = ObvUserActivitySingleton.shared

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navigationBar.standardAppearance = appearance
     
        observeNotificationsImpactingTheNavigationStack()

    }
    
}


// MARK: - Switching current owned identity

extension DiscussionsFlowViewController {
    
    @MainActor
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        popToRootViewController(animated: false)
        guard let recentDiscussionsViewController = viewControllers.first as? RecentDiscussionsViewController else { assertionFailure(); return }
        await recentDiscussionsViewController.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }
    
}


// MARK: - RecentDiscussionsViewControllerDelegate and DiscussionPickerViewControllerDelegate

extension DiscussionsFlowViewController: RecentDiscussionsViewControllerDelegate {
        
    func userWantsToDeleteDiscussion(_ persistedDiscussion: PersistedDiscussion, completionHandler: @escaping (Bool) -> Void) {
        
        assert(Thread.isMainThread)
        
        let ownedIdentityHasHasAnotherReachableDevice = persistedDiscussion.ownedIdentity?.hasAnotherDeviceWhichIsReachable ?? false
        let multipleContacts: Bool
        do {
            switch try persistedDiscussion.kind {
            case .oneToOne:
                multipleContacts = false
            case .groupV1:
                multipleContacts = true
            case .groupV2:
                multipleContacts = true
            }
        } catch {
            assertionFailure()
            multipleContacts = false
        }
        
        let alert = UIAlertController(title: Strings.Alert.ConfirmAllDeletionOfAllMessages.title,
                                      message: Strings.Alert.ConfirmAllDeletionOfAllMessages.message,
                                      preferredStyleForTraitCollection: self.traitCollection)
        
        for deletionType in persistedDiscussion.deletionTypesThatCanBeMadeAvailableForThisDiscussion.sorted() {
            let title = Strings.Alert.ConfirmAllDeletionOfAllMessages.actionTitle(for: deletionType, ownedIdentityHasHasAnotherReachableDevice: ownedIdentityHasHasAnotherReachableDevice, multipleContacts: multipleContacts)
            alert.addAction(UIAlertAction(title: title, style: .destructive, handler: { [weak self] (action) in
                guard let ownedCryptoId = persistedDiscussion.ownedIdentity?.cryptoId else { return }
                switch deletionType {
                case .fromThisDeviceOnly, .fromAllOwnedDevices:
                    ObvMessengerInternalNotification.userRequestedDeletionOfPersistedDiscussion(
                        ownedCryptoId: ownedCryptoId,
                        discussionObjectID: persistedDiscussion.typedObjectID,
                        deletionType: deletionType,
                        completionHandler: completionHandler)
                        .postOnDispatchQueue()
                case .fromAllOwnedDevicesAndAllContactDevices:
                    // Request a second confirmation in that case, as the discussion will also be delete from contact devices
                    self?.ensureUserWantsToGloballyDeleteDiscussion(persistedDiscussion,
                                                                    ownedIdentityHasHasAnotherReachableDevice: ownedIdentityHasHasAnotherReachableDevice,
                                                                    multipleContacts: multipleContacts,
                                                                    completionHandler: completionHandler)
                }
            }))
        }
        
        // Cancel action
        
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { (action) in
            completionHandler(false)
        })
        
        present(alert, animated: true)
        
    }
    
    func ensureUserWantsToGloballyDeleteDiscussion(_ discussion: PersistedDiscussion, ownedIdentityHasHasAnotherReachableDevice: Bool, multipleContacts: Bool, completionHandler: @escaping (Bool) -> Void) {
        assert(Thread.current.isMainThread)
        let alert = UIAlertController(title: Strings.AlertConfirmAllDiscussionMessagesDeletionGlobally.title,
                                      message: Strings.AlertConfirmAllDiscussionMessagesDeletionGlobally.message,
                                      preferredStyleForTraitCollection: self.traitCollection)
        let actionTitle = Strings.Alert.ConfirmAllDeletionOfAllMessages.actionTitle(for: .fromAllOwnedDevicesAndAllContactDevices, ownedIdentityHasHasAnotherReachableDevice: ownedIdentityHasHasAnotherReachableDevice, multipleContacts: multipleContacts)
        alert.addAction(UIAlertAction(title: actionTitle, style: .destructive, handler: { (action) in
            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId else { return }
            ObvMessengerInternalNotification.userRequestedDeletionOfPersistedDiscussion(
                ownedCryptoId: ownedCryptoId,
                discussionObjectID: discussion.typedObjectID,
                deletionType: .fromAllOwnedDevicesAndAllContactDevices,
                completionHandler: completionHandler)
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

    func userAskedToRefreshDiscussions() async throws {
        try await flowDelegate?.userAskedToRefreshDiscussions()
    }

}
