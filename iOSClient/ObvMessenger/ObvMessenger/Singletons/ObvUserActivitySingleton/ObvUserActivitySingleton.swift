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

final class ObvUserActivitySingleton: NSObject, UINavigationControllerDelegate {
    
    static let shared: ObvUserActivitySingleton = ObvUserActivitySingleton()

    private let internalQueue = DispatchQueue(label: "ObvUserActivitySingleton internal queue")
    
    @Published private(set) var currentUserActivity = ObvUserActivityType.other
        
    var currentDiscussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>? {
        switch currentUserActivity {
        case .continueDiscussion(let discussionPermanentID):
            return discussionPermanentID
        case .watchLatestDiscussions,
             .displaySingleContact,
             .displayContacts,
             .displayGroups,
             .displaySingleGroup,
             .displayInvitations,
             .displaySettings,
             .other:
            return nil
        }
    }
    
}


// MARK: - UINavigationControllerDelegate

extension ObvUserActivitySingleton {
    
    /// This singleton is set as the delegate of the four UINavigationControllers (which are ObvFlowControllers) corresponding to the four main tabs (discussions, contacts,
    /// groups, and invitations). It is also the delegate of the navigation controller constructed when using a split screen (e.g., on an iPad), where the split view controller shows
    /// a UINavigationController for its secondary view controller. Being a delegate of these UINavigationControllers makes it possible to be notified each time their stack of
    /// controllers is updated (which happens, e.g., when the user pushes a new discussion on screen, or pops one). Each time this happens, we get a change to update
    /// the current user activity.
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        
        let newUserActivity: ObvUserActivityType
        switch viewController {
        case is RecentDiscussionsViewController:
            newUserActivity = .watchLatestDiscussions
        case let vc as SomeSingleDiscussionViewController:
            let discussionPermanentID = vc.discussionPermanentID
            newUserActivity = .continueDiscussion(discussionPermanentID: discussionPermanentID)
        case is SomeSingleContactViewController:
            newUserActivity = .displaySingleContact
        case is AllContactsViewController:
            newUserActivity = .displayContacts
        case is NewAllGroupsViewController:
            newUserActivity = .displayGroups
        case is SingleGroupViewController:
            newUserActivity = .displaySingleGroup
        case is SingleGroupV2ViewController:
            newUserActivity = .displaySingleGroup
        case is InvitationsCollectionViewController:
            newUserActivity = .displayInvitations
        default:
            newUserActivity = .other
        }

        internalQueue.async { [weak self] in
            
            guard let _self = self else { return }
            
            let previousUserActivity = _self.currentUserActivity
                                    
            guard newUserActivity != previousUserActivity else { return }
            
            self?.currentUserActivity = newUserActivity
            
            debugPrint("📺 Current user activity is \(String(describing: self?.currentUserActivity.debugDescription))")
            
            // Inform the system about the user new activity
            
            if let newUserActivity = self?.currentUserActivity {
                DispatchQueue.main.async {
                    let newUserActivity = ObvUserActivity(activityType: newUserActivity)
                    viewController.userActivity = newUserActivity
                }
            }
            
            // Notify
            
            if previousUserActivity != _self.currentUserActivity {
                ObvMessengerInternalNotification.currentUserActivityDidChange(
                    previousUserActivity: previousUserActivity,
                    currentUserActivity: _self.currentUserActivity
                )
                .postOnDispatchQueue()
            }
            
            // If the activity changed, re-enable the idle timer of the app
            
            if previousUserActivity != _self.currentUserActivity {
                DispatchQueue.main.async {
                    IdleTimerManager.shared.forceEnableIdleTimer()
                }
            }

        }

    }
    
}




fileprivate final class ObvUserActivity: NSUserActivity {
    
    let type: ObvUserActivityType
    
    init(activityType: ObvUserActivityType) {
        self.type = activityType
        super.init(activityType: activityType.nsUserActivityType)
        switch activityType {
        case .continueDiscussion(discussionPermanentID: let discussionPermanentID):
            self.title = "Continue Discussion"
            self.userInfo = ["discussionPermanentIDDescription": discussionPermanentID.description]
        case .watchLatestDiscussions:
            self.title = "Watch latest discussions"
        case .displaySingleContact:
            self.title = "Display single contact"
        case .displayContacts:
            self.title = "displayContacts"
        case .displayGroups:
            self.title = "displayGroups"
        case .displayInvitations:
            self.title = "displayInvitations"
        case .displaySettings:
            self.title = "displaySettings"
        case .displaySingleGroup:
            self.title = "displaySingleGroup"
        case .other:
            self.title = "Other"
        }
    }
    
    override var debugDescription: String {
        assert(self.title != nil)
        switch type {
        case .continueDiscussion(discussionPermanentID: let discussionPermanentID):
            return "\(self.title ?? "No title") - \(discussionPermanentID.description)"
        default:
            return self.title ?? "No title"
        }
    }

}
