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
import ObvTypes
import ObvUICoreData


final class ObvUserActivitySingleton: NSObject, UINavigationControllerDelegate {
    
    static let shared: ObvUserActivitySingleton = ObvUserActivitySingleton()
    
    private override init() {}

    private let internalQueue = DispatchQueue(label: "ObvUserActivitySingleton internal queue")
    
    @Published private(set) var currentUserActivity = ObvUserActivityType.unknown
        
    var currentDiscussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>? {
        switch currentUserActivity {
        case .continueDiscussion(_, let discussionPermanentID):
            return discussionPermanentID
        case .watchLatestDiscussions,
             .displaySingleContact,
             .displayContacts,
             .displayGroups,
             .displaySingleGroup,
             .displayInvitations,
             .displaySettings,
             .other,
             .unknown:
            return nil
        }
    }
    
    var currentOwnedCryptoId: ObvCryptoId? {
        switch currentUserActivity {
        case .watchLatestDiscussions(let ownedCryptoId):
            return ownedCryptoId
        case .continueDiscussion(let ownedCryptoId, _):
            return ownedCryptoId
        case .displaySingleContact(ownedCryptoId: let ownedCryptoId, contactPermanentID: _):
            return ownedCryptoId
        case .displayContacts(let ownedCryptoId):
            return ownedCryptoId
        case .displayGroups(let ownedCryptoId):
            return ownedCryptoId
        case .displaySingleGroup(ownedCryptoId: let ownedCryptoId, displayedContactGroupPermanentID: _):
            return ownedCryptoId
        case .displayInvitations(let ownedCryptoId):
            return ownedCryptoId
        case .displaySettings(let ownedCryptoId):
            return ownedCryptoId
        case .other(let ownedCryptoId):
            return ownedCryptoId
        case .unknown:
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
        guard navigationController.viewControllers.isEmpty == false else { // this sanity check is done when we're removing all of the view controllers (`navigationController.viewControllers = []`). there is no visible view controller, thus this method fails in swift
            switch currentUserActivity {
            case .watchLatestDiscussions,
                    .displaySingleContact,
                    .displayContacts,
                    .displayGroups,
                    .displaySingleGroup,
                    .displayInvitations,
                    .displaySettings,
                    .other,
                    .unknown:
                break

            case .continueDiscussion(ownedCryptoId: let value, discussionPermanentID: _):
                currentUserActivity = .watchLatestDiscussions(ownedCryptoId: value) // reset the current user activity when we delete a conversation
            }

            return
        }

        let newUserActivity: ObvUserActivityType

        switch viewController {

        case let vc as RecentDiscussionsViewController:
            let ownedCryptoId = vc.currentOwnedCryptoId
            newUserActivity = .watchLatestDiscussions(ownedCryptoId: ownedCryptoId)

        case let vc as SomeSingleDiscussionViewController:
            let discussionPermanentID = vc.discussionPermanentID
            let ownedCryptoId = vc.currentOwnedCryptoId
            newUserActivity = .continueDiscussion(ownedCryptoId: ownedCryptoId, discussionPermanentID: discussionPermanentID)

        case let vc as SomeSingleContactViewController:
            let ownedCryptoId = vc.currentOwnedCryptoId
            let contactPermanentID = vc.contactPermanentID
            newUserActivity = .displaySingleContact(ownedCryptoId: ownedCryptoId, contactPermanentID: contactPermanentID)

        case let vc as AllContactsViewController:
            let ownedCryptoId = vc.currentOwnedCryptoId
            newUserActivity = .displayContacts(ownedCryptoId: ownedCryptoId)

        case let vc as NewAllGroupsViewController:
            let ownedCryptoId = vc.currentOwnedCryptoId
            newUserActivity = .displayGroups(ownedCryptoId: ownedCryptoId)

        case let vc as SingleGroupViewController:
            let ownedCryptoId = vc.currentOwnedCryptoId
            let displayedContactGroupPermanentID = vc.displayedContactGroupPermanentID
            newUserActivity = .displaySingleGroup(ownedCryptoId: ownedCryptoId, displayedContactGroupPermanentID: displayedContactGroupPermanentID)

        case let vc as SingleGroupV2ViewController:
            let ownedCryptoId = vc.currentOwnedCryptoId
            let displayedContactGroupPermanentID = vc.displayedContactGroupPermanentID
            newUserActivity = .displaySingleGroup(ownedCryptoId: ownedCryptoId, displayedContactGroupPermanentID: displayedContactGroupPermanentID)

        case let vc as AllInvitationsViewController:
            let ownedCryptoId = vc.currentOwnedCryptoId
            newUserActivity = .displayInvitations(ownedCryptoId: ownedCryptoId)
            
        case is OlvidPlaceholderViewController:
            // We keep the existing user activity
            return

        default:
            if let ownedCryptoId = currentUserActivity.ownedCryptoId {
                newUserActivity = .other(ownedCryptoId: ownedCryptoId)
            } else {
                assertionFailure("The unknown type is expect to bet set as an initial value only. VC is \(viewController.debugDescription)")
                newUserActivity = .unknown
            }
        }
        
        // Check whether the owned identity associated to the new user activity corresponds to a hidden profile.
        // If this is the case, we won't publish the new user activity.
        
        let newUserActivityIsForHiddenProfile: Bool
        if let ownedCryptoId = newUserActivity.ownedCryptoId {
            do {
                let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext)
                newUserActivityIsForHiddenProfile = ownedIdentity?.isHidden ?? false
            } catch {
                assertionFailure()
                newUserActivityIsForHiddenProfile = false
            }
        } else {
            newUserActivityIsForHiddenProfile = false
        }

        internalQueue.async { [weak self] in
            
            guard let _self = self else { return }
            
            let previousUserActivity = _self.currentUserActivity
                                    
            guard newUserActivity != previousUserActivity else { return }
            
            self?.currentUserActivity = newUserActivity
            
            debugPrint("📺 Current user activity is \(String(describing: self?.currentUserActivity.debugDescription))")
            
            // Inform the system about the user new activity
            
            if let newUserActivity = self?.currentUserActivity, !newUserActivityIsForHiddenProfile {
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
        case .continueDiscussion(ownedCryptoId: let ownedCryptoId, discussionPermanentID: let discussionPermanentID):
            self.title = "Continue Discussion"
            self.userInfo = [
                "ownedCryptoIdDescription": ownedCryptoId.description,
                "discussionPermanentIDDescription": discussionPermanentID.description,
            ]
        case .watchLatestDiscussions(ownedCryptoId: let ownedCryptoId):
            self.title = "Watch latest discussions"
            self.userInfo = [
                "ownedCryptoIdDescription": ownedCryptoId.description,
            ]
        case .displaySingleContact(ownedCryptoId: let ownedCryptoId, contactPermanentID: let contactPermanentID):
            self.title = "Display single contact"
            self.userInfo = [
                "ownedCryptoIdDescription": ownedCryptoId.description,
                "contactPermanentIDDescription": contactPermanentID.description,
            ]
        case .displayContacts(ownedCryptoId: let ownedCryptoId):
            self.title = "displayContacts"
            self.userInfo = [
                "ownedCryptoIdDescription": ownedCryptoId.description,
            ]
        case .displayGroups(ownedCryptoId: let ownedCryptoId):
            self.title = "displayGroups"
            self.userInfo = [
                "ownedCryptoIdDescription": ownedCryptoId.description,
            ]
        case .displayInvitations(ownedCryptoId: let ownedCryptoId):
            self.title = "displayInvitations"
            self.userInfo = [
                "ownedCryptoIdDescription": ownedCryptoId.description,
            ]
        case .displaySettings(ownedCryptoId: let ownedCryptoId):
            self.title = "displaySettings"
            self.userInfo = [
                "ownedCryptoIdDescription": ownedCryptoId.description,
            ]
        case .displaySingleGroup(ownedCryptoId: let ownedCryptoId, displayedContactGroupPermanentID: let displayedContactGroupPermanentID):
            self.title = "displaySingleGroup"
            self.userInfo = [
                "ownedCryptoIdDescription": ownedCryptoId.description,
                "displayedContactGroupPermanentIDDescription": displayedContactGroupPermanentID.description,
            ]
        case .other(ownedCryptoId: let ownedCryptoId):
            self.title = "Other"
            self.userInfo = [
                "ownedCryptoIdDescription": ownedCryptoId.description,
            ]
        case .unknown:
            self.title = "Unknown"
        }
    }
    
    override var debugDescription: String {
        assert(self.title != nil)
        switch type {
        case .watchLatestDiscussions(let ownedCryptoId):
            return "\(self.title ?? "No title") - \(ownedCryptoId.debugDescription)"
        case .continueDiscussion(let ownedCryptoId, let discussionPermanentID):
            return "\(self.title ?? "No title") - \(ownedCryptoId.debugDescription) - \(discussionPermanentID.debugDescription)"
        case .displaySingleContact(let ownedCryptoId, let contactPermanentID):
            return "\(self.title ?? "No title") - \(ownedCryptoId.debugDescription) - \(contactPermanentID.debugDescription)"
        case .displayContacts(let ownedCryptoId):
            return "\(self.title ?? "No title") - \(ownedCryptoId.debugDescription)"
        case .displayGroups(let ownedCryptoId):
            return "\(self.title ?? "No title") - \(ownedCryptoId.debugDescription)"
        case .displaySingleGroup(let ownedCryptoId, let displayedContactGroupPermanentID):
            return "\(self.title ?? "No title") - \(ownedCryptoId.debugDescription) - \(displayedContactGroupPermanentID.debugDescription)"
        case .displayInvitations(let ownedCryptoId):
            return "\(self.title ?? "No title") - \(ownedCryptoId.debugDescription)"
        case .displaySettings(let ownedCryptoId):
            return "\(self.title ?? "No title") - \(ownedCryptoId.debugDescription)"
        case .other(let ownedCryptoId):
            return "\(self.title ?? "No title") - \(ownedCryptoId.debugDescription)"
        case .unknown:
            return self.title ?? "No title"
        }
    }

}
