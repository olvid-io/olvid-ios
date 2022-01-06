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
import UserNotifications
import os.log


final class UserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    
    private let appDelegate = UIApplication.shared.delegate as! AppDelegate
        
    private var tokens = [NSObjectProtocol]()
    
    private var requestIdentifiersThatPlayedSound = Set<String>()
    
    // Answering an invitation from a notification creates a background operation that, e.g., accepts/rejects an invitation. Eventually, the app will have to modify the badge associated to the persisted invitations. To make sure we are still in the background in order to update this badge, we create a long-running background task when responding to an invitation. This backgroud task ends when we are notified that the badge has been updated. While not bullet proof, this is usually enough.
    
    private var backgroundTaskIdForWaitingUntilApplicationIconBadgeNumberWasUpdatedNotification: UIBackgroundTaskIdentifier?
    private var notificationTokenForApplicationIconBadgeNumberWasUpdatedNotification: NSObjectProtocol?

    
}


// MARK: - UNUserNotificationCenterDelegate

extension UserNotificationCenterDelegate {
    
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        assert(Thread.isMainThread)
                
        os_log("🥏 Call to userNotificationCenter didReceive withCompletionHandler", log: log, type: .info)
        
        AppStateManager.shared.addCompletionHandlerToExecuteWhenInitialized { [weak self] in
            
            assert(Thread.isMainThread)
            assert(AppStateManager.shared.currentState.isInitialized)
            
            self?.handleActions(within: response) { actionHandled in
                assert(Thread.isMainThread)

                if actionHandled {
                    
                    completionHandler()
                    
                } else {
                    
                    AppStateManager.shared.addCompletionHandlerToExecuteWhenInitializedAndActive { [weak self] in
                        assert(Thread.isMainThread)
                        assert(AppStateManager.shared.currentState.isInitializedAndActive)
                        self?.handleDeepLink(within: response)
                        completionHandler()
                    }

                }
            }
            
        }
                
    }
    
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // In general, we do not want to present "minimal" new message notifications
        if notification.request.content.userInfo["isMinimalNewMessageNotification"] as? Bool == true {
            completionHandler([])
            return
        }
        
        // When the application is running, we do not show static notification
        if ObvUserNotificationIdentifier.identifierIsStaticIdentifier(identifier: notification.request.identifier) {
            completionHandler([])
            return
        }
        
        // If we are not initialized or not active, we always show a notification
        guard AppStateManager.shared.currentState.isInitializedAndActive else {
            completionHandler(.alert)
            return
        }
                
        // If we reach this point, we know we are initialized and active. We decide what to show depending on the current activity of the user.
        switch ObvUserActivitySingleton.shared.currentUserActivity {
        case .continueDiscussion(persistedDiscussionObjectID: let currentPersistedDiscussionObjectID):
            // The current activity type is `continueDiscussion`. We check whether the notification concerns the "single discussion". If this is the case, we do not display the notification, otherwise, we do.
            if let notificationPersistedDiscussionObjectURI = notification.request.content.userInfo["persistedDiscussionObjectURI"] as? String,
               let notificationPersistedDiscussionObjectURI = URL(string: notificationPersistedDiscussionObjectURI) {
                                
                guard let notificationPersistedDiscussionObjectID = ObvStack.shared.managedObjectID(forURIRepresentation: notificationPersistedDiscussionObjectURI) else {
                    assertionFailure()
                    completionHandler(.alert)
                    return
                }
                            
                if notificationPersistedDiscussionObjectID == currentPersistedDiscussionObjectID.objectID {
                    completionHandler([])
                    return
                } else {
                    completionHandler(.alert)
                    return
                }
                
            }
        case .watchLatestDiscussions:
            // Do not show notifications related to new messages if the user is within the latest discussions view controller. Just play a sound.
            if notification.request.content.userInfo["persistedDiscussionObjectURI"] != nil {
                debugPrint(notification.request.identifier)
                if requestIdentifiersThatPlayedSound.contains(notification.request.identifier) {
                    completionHandler([])
                    return
                } else {
                    requestIdentifiersThatPlayedSound.insert(notification.request.identifier)
                    completionHandler(.sound)
                    return
                }
            } else {
                completionHandler(.alert)
                return
            }
        case .displayInvitations:
            /* The user is currently looking at the invitiation tab.
             * 2020-10-08: We used to prevent
             * the display of the notification if it concerned an invitation,
             * or if it concerned a sas exchange or a mutual trust confirmation.
             * Now, we always show it
             */
            completionHandler(.alert)
            return
        case .other,
             .displaySingleContact,
             .displayContacts,
             .displayGroups,
             .displaySingleGroup,
             .displaySettings:
            completionHandler(.alert)
            return
        }
        
    }
    
    
}


// MARK: - Helpers

extension UserNotificationCenterDelegate {
    
    /// This method handles a UNNotificationResponse action if it finds one. In that case, it calls the completion handler passing the value `true`. Otherwise, the completion
    /// handler is called with `false`.
    private func handleActions(within response: UNNotificationResponse, completionHandler: @escaping (Bool) -> Void) {
        
        guard AppStateManager.shared.currentState.isInitialized else {
            assertionFailure()
            completionHandler(false)
            return
        }

        guard let action = UserNotificationAction(rawValue: response.actionIdentifier) else {
            // This happens, e.g., when tapping a message notification. In that case, the action identifier is UNNotificationDefaultActionIdentifier
            assert(response.actionIdentifier == UNNotificationDefaultActionIdentifier)
            completionHandler(false)
            return
        }

        let userInfo = response.notification.request.content.userInfo

        switch action {
        case .accept, .decline:
            guard let persistedInvitationUuidAsString = userInfo["persistedInvitationUUID"] as? String,
                  let persistedInvitationUuid = UUID(uuidString: persistedInvitationUuidAsString)
            else {
                assertionFailure()
                completionHandler(false)
                return
            }
            handleInvitationActions(action: action, persistedInvitationUuid: persistedInvitationUuid, completionHandler: completionHandler)
        case .mute:
            guard let persistedDiscussionObjectURIAsString = userInfo["persistedDiscussionObjectURI"] as? String,
                  let persistedDiscussionObjectURI = URL(string: persistedDiscussionObjectURIAsString)
            else {
                assertionFailure()
                completionHandler(false)
                return
            }
            guard let objectID = ObvStack.shared.managedObjectID(forURIRepresentation: persistedDiscussionObjectURI) else {
                assertionFailure()
                completionHandler(false)
                return
            }
            guard let persistedGroupDiscussionEntityName = PersistedGroupDiscussion.entity().name,
                  let persistedOneToOneDiscussionEntityName = PersistedOneToOneDiscussion.entity().name,
                  let persistedDiscussionEntityName = PersistedDiscussion.entity().name
            else {
                assertionFailure()
                completionHandler(false)
                return
            }
            switch objectID.entity.name {
            case persistedGroupDiscussionEntityName, persistedOneToOneDiscussionEntityName, persistedDiscussionEntityName:
                let persistedDiscussionObjectID = TypeSafeManagedObjectID<PersistedDiscussion>(objectID: objectID)
                handleMuteActions(persistedDiscussionObjectID: persistedDiscussionObjectID, completionHandler: completionHandler)
                return
            default:
                assertionFailure()
                completionHandler(false)
                return
            }
        case .callBack:
            guard let callUUIDAsString = userInfo["callUUID"] as? String,
                  let callUUID = UUID(callUUIDAsString)
            else {
                assertionFailure()
                completionHandler(false)
                return
            }
            handleCallBackAction(callUUID: callUUID, completionHandler: completionHandler)
        }
    }
    
    
    private func handleMuteActions(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, completionHandler: @escaping (Bool) -> Void) {
        ObvMessengerInternalNotification.userWantsToUpdateLocalConfigurationOfDiscussion(
            value: .muteNotificationsDuration(muteNotificationsDuration: .oneHour),
            persistedDiscussionObjectID: persistedDiscussionObjectID
        ).postOnDispatchQueue()
        completionHandler(true)
    }

    
    private func handleCallBackAction(callUUID: UUID, completionHandler: @escaping (Bool) -> Void) {
        ObvStack.shared.performBackgroundTask { (context) in
            if let item = try? PersistedCallLogItem.get(callUUID: callUUID, within: context) {
                let contacts = item.logContacts.compactMap { $0.contactIdentity?.typedObjectID }
                ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: contacts, groupId: try? item.getGroupId()).postOnDispatchQueue()
            }
            DispatchQueue.main.async {
                completionHandler(true)
            }
        }
    }

    
    private func handleInvitationActions(action: UserNotificationAction, persistedInvitationUuid: UUID, completionHandler: @escaping (Bool) -> Void) {

        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            guard let _self = self else { return }
            let persistedInvitation: PersistedInvitation
            do {
                guard let _persistedInvitation = try PersistedInvitation.get(uuid: persistedInvitationUuid, within: context) else {
                    DispatchQueue.main.async { completionHandler(false) }
                    return
                }
                persistedInvitation = _persistedInvitation
            } catch {
                os_log("Could not get persited invitation from database", log: _self.log, type: .error)
                DispatchQueue.main.async { completionHandler(false) }
                return
            }

            let obvDialog = persistedInvitation.obvDialog
            switch obvDialog.category {
            case .acceptInvite:
                var localDialog = obvDialog
                switch action {
                case .accept:
                    try? localDialog.setResponseToAcceptInvite(acceptInvite: true)
                    _self.appDelegate.obvEngine.respondTo(localDialog)
                    DispatchQueue.main.async { completionHandler(true) }
                    return
                case .decline:
                    _self.waitUntilApplicationIconBadgeNumberWasUpdatedNotification()
                    try? localDialog.setResponseToAcceptInvite(acceptInvite: false)
                    _self.appDelegate.obvEngine.respondTo(localDialog)
                    DispatchQueue.main.async { completionHandler(true) }
                    return
                case .mute, .callBack:
                    assertionFailure()
                    DispatchQueue.main.async { completionHandler(false) }
                    return
                }
            case .acceptMediatorInvite:
                var localDialog = obvDialog
                switch action {
                case .accept:
                    try? localDialog.setResponseToAcceptMediatorInvite(acceptInvite: true)
                    _self.appDelegate.obvEngine.respondTo(localDialog)
                    DispatchQueue.main.async { completionHandler(true) }
                    return
                case .decline:
                    _self.waitUntilApplicationIconBadgeNumberWasUpdatedNotification()
                    try? localDialog.setResponseToAcceptMediatorInvite(acceptInvite: false)
                    _self.appDelegate.obvEngine.respondTo(localDialog)
                    DispatchQueue.main.async { completionHandler(true) }
                    return
                case .mute, .callBack:
                    assertionFailure()
                    DispatchQueue.main.async { completionHandler(false) }
                    return
                }
            case .acceptGroupInvite:
                var localDialog = obvDialog
                switch action {
                case .accept:
                    try? localDialog.setResponseToAcceptGroupInvite(acceptInvite: true)
                    _self.appDelegate.obvEngine.respondTo(localDialog)
                    DispatchQueue.main.async { completionHandler(true) }
                    return
                case .decline:
                    _self.waitUntilApplicationIconBadgeNumberWasUpdatedNotification()
                    try? localDialog.setResponseToAcceptGroupInvite(acceptInvite: false)
                    _self.appDelegate.obvEngine.respondTo(localDialog)
                    DispatchQueue.main.async { completionHandler(true) }
                    return
                case .mute, .callBack:
                    assertionFailure()
                    DispatchQueue.main.async { completionHandler(false) }
                    return
                }
            default:
                assertionFailure()
                DispatchQueue.main.async { completionHandler(false) }
                return
            }
        }
        
    }
    
    
    private func waitUntilApplicationIconBadgeNumberWasUpdatedNotification() {
        
        cancelWaitingForApplicationIconBadgeNumberWasUpdatedNotification()
        
        let backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "Waiting for BadgeForInvitationsWasUpdated notification") { [weak self] in
            self?.cancelWaitingForApplicationIconBadgeNumberWasUpdatedNotification()
        }
        backgroundTaskIdForWaitingUntilApplicationIconBadgeNumberWasUpdatedNotification = backgroundTaskId
        
        let NotificationType = MessengerInternalNotification.ApplicationIconBadgeNumberWasUpdated.self
        notificationTokenForApplicationIconBadgeNumberWasUpdatedNotification = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil, using: { [weak self] (_) in
            self?.cancelWaitingForApplicationIconBadgeNumberWasUpdatedNotification()
        })
        
    }
    
    
    private func cancelWaitingForApplicationIconBadgeNumberWasUpdatedNotification() {
        if let backgroundTaskId = backgroundTaskIdForWaitingUntilApplicationIconBadgeNumberWasUpdatedNotification {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskIdForWaitingUntilApplicationIconBadgeNumberWasUpdatedNotification = nil
        }
        if let notificationToken = notificationTokenForApplicationIconBadgeNumberWasUpdatedNotification {
            NotificationCenter.default.removeObserver(notificationToken)
            notificationTokenForApplicationIconBadgeNumberWasUpdatedNotification = nil
        }
    }
    
    
    private func handleDeepLink(within response: UNNotificationResponse) {
        
        os_log("🥏 Call to handleDeepLink", log: log, type: .info)

        guard let deepLinkString = response.notification.request.content.userInfo["deepLink"] as? String else {
            return
        }
        guard let deepLinkURL = URL(string: deepLinkString) else { return }
        guard let deepLink = ObvDeepLink(url: deepLinkURL) else { return }
        
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()

    }

    
}
