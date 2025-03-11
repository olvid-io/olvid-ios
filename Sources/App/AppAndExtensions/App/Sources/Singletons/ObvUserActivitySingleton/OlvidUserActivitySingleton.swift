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
import ObvTypes
import ObvUICoreData
import ObvAppTypes


final class OlvidUserActivitySingleton: NSObject {
    
    static let shared = OlvidUserActivitySingleton()
    
    private override init() {}

    private let internalQueue = DispatchQueue(label: "OlvidUserActivitySingleton internal queue")

    @Published private(set) var currentUserActivity: OlvidUserActivity?
    @Published private(set) var currentDiscussionPermanentID: DiscussionPermanentID?
    
    /// Allows to track the current active appearance. Particularly useful under macOS, e.g., when deciding whether to show a user notification or not.
    @Published private(set) var traitCollectionActiveAppearance: UIUserInterfaceActiveAppearance?

}


// MARK: - Setting the UIUserInterfaceActiveAppearance

extension OlvidUserActivitySingleton {
    
    /// Called by the root view controller each time the user interface active appearance changes.
    @MainActor
    func setTraitCollectionActiveAppearance(_ traitCollectionActiveAppearance: UIUserInterfaceActiveAppearance) {
        self.traitCollectionActiveAppearance = traitCollectionActiveAppearance
    }
    
}


// MARK: - UINavigationControllerDelegate

extension OlvidUserActivitySingleton: UINavigationControllerDelegate {
    
    @MainActor
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId, viewController: UIViewController) async {
                
        let newUserActivity: OlvidUserActivity

        if let currentUserActivity {
            newUserActivity = currentUserActivity
                .withUpdatedOwnedCryptoId(newOwnedCryptoId)
        } else {
            newUserActivity = .init(ownedCryptoId: newOwnedCryptoId, selectedTab: .latestDiscussions, currentDiscussion: nil)
        }
        
        // Update
        
        updateWith(newUserActivity: newUserActivity, viewController: viewController)

    }
    
    private func determineCurrentDiscussionWhenShowing(_ viewController: SomeSingleDiscussionViewController) -> ObvDiscussionIdentifier? {
        assert(Thread.isMainThread)
        if let persistedDiscussion = try? PersistedDiscussion.get(objectID: viewController.discussionObjectID.objectID, within: ObvStack.shared.viewContext),
           let discussionIdentifier = persistedDiscussion.discussionIdentifier {
            return discussionIdentifier
        } else {
            assertionFailure()
            return nil
        }
    }
    
    
    private func determineDiscussionPermanentID(from discussionActivityIdentifier: ObvDiscussionIdentifier) -> DiscussionPermanentID? {
        assert(Thread.isMainThread)
        let discussionId = discussionActivityIdentifier.toDiscussionIdentifier()
        if let discussion = try? PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: discussionActivityIdentifier.ownedCryptoId, discussionId: discussionId, within: ObvStack.shared.viewContext) {
            return discussion.discussionPermanentID
        } else {
            assertionFailure()
            return nil
        }
    }
    
    
    /// This singleton is set as the delegate of the four UINavigationControllers (which are ObvFlowControllers) corresponding to the four main tabs (discussions, contacts,
    /// groups, and invitations). It is also the delegate of the navigation controller constructed when using a split screen (e.g., on an iPad), where the split view controller shows
    /// a UINavigationController for its secondary view controller. Being a delegate of these UINavigationControllers makes it possible to be notified each time their stack of
    /// controllers is updated (which happens, e.g., when the user pushes a new discussion on screen, or pops one). Each time this happens, we get a change to update
    /// the current user activity.
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {

        guard navigationController.viewControllers.isEmpty == false else { // this sanity check is done when we're removing all of the view controllers (`navigationController.viewControllers = []`). there is no visible view controller, thus this method fails in swift
            currentUserActivity = nil
            currentDiscussionPermanentID = nil
            return
        }
        
        // Determine the current (single) discussion
        
        let currentDiscussion: ObvDiscussionIdentifier?
        
        switch viewController {
        case let vc as SomeSingleDiscussionViewController:
            currentDiscussion = determineCurrentDiscussionWhenShowing(vc)
        case is OlvidPlaceholderViewController:
            currentDiscussion = nil
        default:
            if navigationController is ObvFlowController {
                // This happens when changing tab on an iPhone or on an Mac
                assert(navigationController.parent?.parent is UISplitViewController == true)
                if (navigationController.parent?.parent as? UISplitViewController)?.isCollapsed == true {
                    // iPhone case: The ObvFlowController does define the shown discussion
                    currentDiscussion = nil
                } else {
                    assert((navigationController.parent?.parent as? UISplitViewController)?.isCollapsed == false)
                    // Mac case: The ObvFlowController does *not* define the shown discussion
                    currentDiscussion = currentUserActivity?.currentDiscussion
                }
            } else {
                currentDiscussion = currentUserActivity?.currentDiscussion
            }
        }
        
        // Determine the activity type
        
        let newUserActivity: OlvidUserActivity
        
        switch navigationController {
        case let flowController as DiscussionsFlowViewController:
            newUserActivity = .init(ownedCryptoId: flowController.currentOwnedCryptoId, selectedTab: .latestDiscussions, currentDiscussion: currentDiscussion)
        case let flowController as ContactsFlowViewController:
            newUserActivity = .init(ownedCryptoId: flowController.currentOwnedCryptoId, selectedTab: .contacts, currentDiscussion: currentDiscussion)
        case let flowController as GroupsFlowViewController:
            newUserActivity = .init(ownedCryptoId: flowController.currentOwnedCryptoId, selectedTab: .groups, currentDiscussion: currentDiscussion)
        case let flowController as NewInvitationsFlowViewController:
            newUserActivity = .init(ownedCryptoId: flowController.currentOwnedCryptoId, selectedTab: .invitations, currentDiscussion: currentDiscussion)
        default:
            if let mainFlowViewController = navigationController.parent as? MainFlowViewController {
                guard let currentUserActivity else { return }
                newUserActivity = currentUserActivity
                    .withUpdatedCurrentDiscussion(currentDiscussion)
                    .withUpdatedOwnedCryptoId(mainFlowViewController.currentOwnedCryptoId)
            } else {
                assertionFailure()
                return
            }
        }

        // Update
        
        updateWith(newUserActivity: newUserActivity, viewController: viewController)

    }
    
    
    private func updateWith(newUserActivity: OlvidUserActivity, viewController: UIViewController) {
        
        // Determine the current discussion's permanent ID
        
        let newCurrentDiscussionPermanentID: DiscussionPermanentID?
        if let currentDiscussion = newUserActivity.currentDiscussion {
            newCurrentDiscussionPermanentID = determineDiscussionPermanentID(from: currentDiscussion)
        } else {
            newCurrentDiscussionPermanentID = nil
        }

        // Check whether the owned identity associated to the new user activity corresponds to a hidden profile.
        // If this is the case, we won't publish the new user activity.
        
        let newUserActivityIsForHiddenProfile: Bool
        do {
            let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: newUserActivity.ownedCryptoId, within: ObvStack.shared.viewContext)
            newUserActivityIsForHiddenProfile = ownedIdentity?.isHidden ?? false
        } catch {
            assertionFailure()
            newUserActivityIsForHiddenProfile = false
        }
        
        internalQueue.async { [weak self] in
            
            guard let self else { return }
            
            let previousUserActivity = self.currentUserActivity
                                    
            guard newUserActivity != previousUserActivity else { return }
            
            let previousDiscussionPermanentID = self.currentDiscussionPermanentID
            
            self.currentUserActivity = newUserActivity
            self.currentDiscussionPermanentID = newCurrentDiscussionPermanentID
            
            debugPrint("📺 Current user activity is \(newUserActivity.debugDescription)")
            debugPrint("📺 Current discussion permanentID is \(currentDiscussionPermanentID?.debugDescription ?? "None")")

            // Inform the system about the user new activity
  
            if let newUserActivity = self.currentUserActivity, !newUserActivityIsForHiddenProfile {
                DispatchQueue.main.async {
                    viewController.userActivity = newUserActivity
                }
            }
            
            // Notify
  
            if previousDiscussionPermanentID != self.currentDiscussionPermanentID {
                ObvMessengerInternalNotification.currentDiscussionDidChange(previousDiscussion: previousDiscussionPermanentID, currentDiscussion: currentDiscussionPermanentID)
                    .postOnDispatchQueue()
            }
            
            // If the activity changed, re-enable the idle timer of the app
            
            if previousUserActivity != self.currentUserActivity {
                DispatchQueue.main.async {
                    IdleTimerManager.shared.forceEnableIdleTimer()
                }
            }

        }

    }
    
}
