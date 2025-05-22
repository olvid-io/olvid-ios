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
import ObvEngine
import ObvTypes
import ObvUI
import ObvUICoreData
import ObvSettings
import ObvDesignSystem
import ObvAppCoreConstants
import ObvUIGroupV2


final class GroupsFlowViewController: UINavigationController, ObvFlowController {
    
    // Variables
    
    private(set) var currentOwnedCryptoId: ObvCryptoId
    let delegatesStack = ObvFlowControllerDelegatesStack()
    let obvEngine: ObvEngine
    var floatingButton: UIButton? // Used on iOS 18+ only, set at the ObvFlowController level
    private var floatingButtonAnimator: FloatingButtonAnimator?
    let appDataSourceForObvUIGroupV2Router: AppDataSourceForObvUIGroupV2Router

    var observationTokens = [NSObjectProtocol]()

    static let errorDomain = "GroupsFlowViewController"
    
    /// This router allows to present the flow allowing to create a new group v2.
    /// It is expected to be set only once.
    /// The delegate methods are implemented in an extension of `ObvFlowController`.
    private(set) lazy var routerForGroupCreation: ObvUIGroupV2Router = {
        ObvUIGroupV2Router(mode: .creation(delegate: self),
                           dataSource: appDataSourceForObvUIGroupV2Router)
    }()
    /// This router allows to push the flow allowing to edit a new group v2.
    /// It is expected to be set only once.
    /// The delegate methods are implemented in an extension of `ObvFlowController`.
    private(set) lazy var routerForGroupEdition: ObvUIGroupV2Router = {
        ObvUIGroupV2Router(mode: .edition(delegate: self),
                           dataSource: appDataSourceForObvUIGroupV2Router)
    }()
        
    
    // Constants
    
    let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: GroupsFlowViewController.self))

    // Delegate
    
    weak var flowDelegate: ObvFlowControllerDelegate?

    // MARK: - Factory
    
    init(ownedCryptoId: ObvCryptoId, appListOfGroupMembersViewDataSource: AppDataSourceForObvUIGroupV2Router, obvEngine: ObvEngine) {
        
        self.currentOwnedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        self.appDataSourceForObvUIGroupV2Router = appListOfGroupMembersViewDataSource
        
        let allGroupsViewController = NewAllGroupsViewController(ownedCryptoId: ownedCryptoId)
        super.init(rootViewController: allGroupsViewController)
        
        allGroupsViewController.delegate = self

        self.delegate = delegatesStack

    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override var delegate: UINavigationControllerDelegate? {
        get {
            super.delegate
        }
        set {
            guard newValue is ObvFlowControllerDelegatesStack else { assertionFailure(); return }
            super.delegate = newValue
        }
    }

    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }

}


// MARK: - View controller lifecycle

extension GroupsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = CommonString.Word.Groups
        
        if #available(iOS 18, *) {
            // The tabbar is configured with iOS 18 APIs, we don't need to specify a tabBarItem
        } else {
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
            let image = UIImage(systemName: "person.3", withConfiguration: symbolConfiguration)
            tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
        }
        
        delegatesStack.addDelegate(OlvidUserActivitySingleton.shared)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navigationBar.standardAppearance = appearance

        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        
        observeNotificationsImpactingTheNavigationStack()
        
        // This is required to activate the interactive pop gesture recognizer. Activating this interactive gesture also requires
        // to override gestureRecognizerShouldBegin(_:).
        // See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
        if #available(iOS 18, *) {
            interactivePopGestureRecognizer?.delegate = self
        }

    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 18, *) {
            addFloatingButtonIfRequired()
            let floatingButtonAnimator = FloatingButtonAnimator(floatingButton: floatingButton)
            self.delegatesStack.addDelegate(floatingButtonAnimator)
            self.floatingButtonAnimator = floatingButtonAnimator
        }
    }

}


// MARK: - UIGestureRecognizerDelegate

extension GroupsFlowViewController: UIGestureRecognizerDelegate {
    
    /// This is only used under iOS18+, in order to be the delegate of the `interactivePopGestureRecognizer`, allowing to activate the interactive pop gesture recognizer.
    /// See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
    @objc func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
    
}


// MARK: - Switching current owned identity

extension GroupsFlowViewController {
    
    @MainActor
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        popToRootViewController(animated: false)
        self.currentOwnedCryptoId = newOwnedCryptoId
        guard let newAllGroupsViewController = viewControllers.first as? NewAllGroupsViewController else { assertionFailure(); return }
        await newAllGroupsViewController.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }
    
}



// MARK: - NewAllGroupsViewControllerDelegate

extension GroupsFlowViewController: NewAllGroupsViewControllerDelegate {
    
    func userDidSelect(_ contactGroup: PersistedContactGroup, within nav: UINavigationController?) {
        guard let singleGroupVC = try? SingleGroupViewController(persistedContactGroup: contactGroup, obvEngine: obvEngine) else { return }
        singleGroupVC.delegate = self
        pushViewController(singleGroupVC, animated: true)
    }
    

    func userDidSelect(_ group: PersistedGroupV2, within navigationController: UINavigationController?) {
        guard let groupV2Identifier = try? group.obvGroupIdentifier else { assertionFailure(); return }
        // The following method is implemented at the ObvFlowController level
        self.userWantsToNavigateToSingleGroupView(groupIdentifier: groupV2Identifier, within: navigationController)
    }

    
    func userWantsToAddContactGroup() {
        assert(Thread.isMainThread)
        let ownedCryptoId = self.currentOwnedCryptoId
        let obvEngine = self.obvEngine
        
        if ObvMessengerConstants.developmentMode {
            
            let alert = UIAlertController(title: NSLocalizedString("CHOOSE_GROUP_TYPE_TITLE", comment: ""),
                                          message: NSLocalizedString("CHOOSE_GROUP_TYPE_MESSAGE", comment: ""),
                                          preferredStyleForTraitCollection: self.traitCollection)
            alert.addAction(UIAlertAction(title: NSLocalizedString("CHOOSE_GROUP_V1", comment: ""), style: .default, handler: { [weak self] (action) in
                let groupCreationFlowVC = GroupEditionFlowViewController(ownedCryptoId: ownedCryptoId, editionType: .createGroupV1, obvEngine: obvEngine)
                self?.present(groupCreationFlowVC, animated: true)
            }))
            alert.addAction(UIAlertAction(title: NSLocalizedString("CHOOSE_GROUP_V2", comment: ""), style: .default, handler: { [weak self] (action) in
                guard let self else { return }
                routerForGroupCreation.presentInitialViewControllerForGroupCreation(ownedCryptoId: currentOwnedCryptoId,
                                                                                    presentingViewController: self,
                                                                                    creationMode: .fromScratch)
            }))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            
            if let presentedViewController = self.presentedViewController {
                presentedViewController.present(alert, animated: true)
            } else {
                self.present(alert, animated: true)
            }

        } else {
            
            // Starting with version 0.12.0, we only allow the creation of groups v2.
            // The group creation flow was completely refactored in version 2.4
            // 2025-04-21: the group creation flow was re-coded from scratch.
            routerForGroupCreation.presentInitialViewControllerForGroupCreation(ownedCryptoId: currentOwnedCryptoId,
                                                                                presentingViewController: self,
                                                                                creationMode: .fromScratch)
            
        }
    }
        
    
    @objc
    func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }

}
