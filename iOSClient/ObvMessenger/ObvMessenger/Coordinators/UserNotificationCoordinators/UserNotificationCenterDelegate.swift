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
import CoreData


final class UserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UserNotificationCenterDelegate.self))
    
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

        guard let rawId = notification.request.content.userInfo[UserNotificationKeys.id] as? Int,
              let id = ObvUserNotificationID(rawValue: rawId) else {
                  assertionFailure()
                  completionHandler(.alert)
                  return
              }

        // If we reach this point, we know we are initialized and active. We decide what to show depending on the current activity of the user.
        switch ObvUserActivitySingleton.shared.currentUserActivity {
        case .continueDiscussion(persistedDiscussionObjectID: let currentPersistedDiscussionObjectID):
            switch id {
            case .newReactionNotificationWithHiddenContent, .newReaction:
                // Always show reaction notification even if it is a reaction for the current discussion.
                completionHandler(.alert)
            case .newMessageNotificationWithHiddenContent, .newMessage, .missedCall, .shouldGrantRecordPermissionToReceiveIncomingCalls:
                // The current activity type is `continueDiscussion`. We check whether the notification concerns the "single discussion". If this is the case, we do not display the notification, otherwise, we do.
                guard let notificationPersistedDiscussionObjectURI = notification.request.content.userInfo[UserNotificationKeys.persistedDiscussionObjectURI] as? String,
                      let notificationPersistedDiscussionObjectURI = URL(string: notificationPersistedDiscussionObjectURI),
                      let notificationPersistedDiscussionObjectID = ObvStack.shared.managedObjectID(forURIRepresentation: notificationPersistedDiscussionObjectURI)else {
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
            case .acceptInvite, .sasExchange, .mutualTrustConfirmed, .acceptMediatorInvite, .acceptGroupInvite, .autoconfirmedContactIntroduction, .increaseMediatorTrustLevelRequired, .oneToOneInvitationReceived:
                completionHandler(.alert)
                return
            case .staticIdentifier:
                assertionFailure()
            }

        case .watchLatestDiscussions:
            switch id {
            case .newMessageNotificationWithHiddenContent, .newMessage:
                // Do not show notifications related to new messages if the user is within the latest discussions view controller. Just play a sound.
                if requestIdentifiersThatPlayedSound.contains(notification.request.identifier) {
                    completionHandler([])
                    return
                } else {
                    requestIdentifiersThatPlayedSound.insert(notification.request.identifier)
                    completionHandler(.sound)
                    return
                }
            case .newReactionNotificationWithHiddenContent, .newReaction, .acceptInvite, .sasExchange, .mutualTrustConfirmed, .acceptMediatorInvite, .acceptGroupInvite, .autoconfirmedContactIntroduction, .increaseMediatorTrustLevelRequired, .missedCall, .oneToOneInvitationReceived, .staticIdentifier, .shouldGrantRecordPermissionToReceiveIncomingCalls:
                completionHandler(.alert)
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
            switch response.actionIdentifier {
            case UNNotificationDismissActionIdentifier:
                // If the user simply dismissed the notification, we consider that the action was handled
                completionHandler(true)
                return
            case UNNotificationDefaultActionIdentifier:
                // If the user tapped the notification, it means she wishes to open Olvid and navigate to the discussion.
                // We consider that this notification is not handled and complete with `false`. The caller of this method will handle the rest.
                completionHandler(false)
                return
            default:
                // This is not expected
                assertionFailure()
                completionHandler(false)
                return
            }
        }

        let userInfo = response.notification.request.content.userInfo

        switch action {
        case .accept, .decline:
            guard let persistedInvitationUuidAsString = userInfo[UserNotificationKeys.persistedInvitationUUID] as? String,
                  let persistedInvitationUuid = UUID(uuidString: persistedInvitationUuidAsString)
            else {
                assertionFailure()
                completionHandler(false)
                return
            }
            handleInvitationActions(action: action, persistedInvitationUuid: persistedInvitationUuid, completionHandler: completionHandler)
        case .mute:
            guard let persistedDiscussionObjectURIAsString = userInfo[UserNotificationKeys.persistedDiscussionObjectURI] as? String,
                  let persistedDiscussionObjectURI = URL(string: persistedDiscussionObjectURIAsString),
                  let objectID = ObvStack.shared.managedObjectID(forURIRepresentation: persistedDiscussionObjectURI),
                  let persistedGroupDiscussionEntityName = PersistedGroupDiscussion.entity().name,
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
            guard let callUUIDAsString = userInfo[UserNotificationKeys.callUUID] as? String,
                  let callUUID = UUID(callUUIDAsString)
            else {
                assertionFailure()
                completionHandler(false)
                return
            }
            handleCallBackAction(callUUID: callUUID, completionHandler: completionHandler)
        case .replyTo:
            guard let messageIdentifierFromEngineAsString = userInfo[UserNotificationKeys.messageIdentifierFromEngine] as? String,
                  let messageIdentifierFromEngine = Data(hexString: messageIdentifierFromEngineAsString),
                  let persistedContactObjectURIAsString = userInfo[UserNotificationKeys.persistedContactObjectURI] as? String,
                  let persistedContactObjectURI = URL(string: persistedContactObjectURIAsString),
                  let persistedContactObjectID = ObvStack.shared.managedObjectID(forURIRepresentation: persistedContactObjectURI),
                  let textResponse = response as? UNTextInputNotificationResponse else {
                assertionFailure()
                completionHandler(false)
                return
            }
            handleReplyToMessageAction(messageIdentifierFromEngine: messageIdentifierFromEngine, persistedContactObjectID: persistedContactObjectID, textBody: textResponse.userText, completionHandler: completionHandler)
        case .sendMessage:
            guard let persistedDiscussionObjectURIAsString = userInfo[UserNotificationKeys.persistedDiscussionObjectURI] as? String,
                  let persistedDiscussionObjectURI = URL(string: persistedDiscussionObjectURIAsString),
                  let persistedDiscussionObjectID = ObvStack.shared.managedObjectID(forURIRepresentation: persistedDiscussionObjectURI),
                  let textResponse = response as? UNTextInputNotificationResponse else {
                      assertionFailure()
                      completionHandler(false)
                      return
                  }
            handleSendMessageAction(persistedDiscussionObjectID: persistedDiscussionObjectID, textBody: textResponse.userText, completionHandler: completionHandler)
        case .markAsRead:
            guard let messageIdentifierFromEngineAsString = userInfo[UserNotificationKeys.messageIdentifierFromEngine] as? String,
                  let messageIdentifierFromEngine = Data(hexString: messageIdentifierFromEngineAsString),
                  let persistedContactObjectURIAsString = userInfo[UserNotificationKeys.persistedContactObjectURI] as? String,
                  let persistedContactObjectURI = URL(string: persistedContactObjectURIAsString),
                  let persistedContactObjectID = ObvStack.shared.managedObjectID(forURIRepresentation: persistedContactObjectURI) else {
                      assertionFailure()
                      completionHandler(false)
                return
                  }
            handleMarkAsReadAction(messageIdentifierFromEngine: messageIdentifierFromEngine, persistedContactObjectID: persistedContactObjectID, completionHandler: completionHandler)
        }
    }
    
    
    private func handleMuteActions(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, completionHandler: @escaping (Bool) -> Void) {
        ObvMessengerInternalNotification.userWantsToUpdateLocalConfigurationOfDiscussion(
            value: .muteNotificationsDuration(muteNotificationsDuration: .oneHour),
            persistedDiscussionObjectID: persistedDiscussionObjectID,
            completionHandler: completionHandler).postOnDispatchQueue()
    }

    
    private func handleCallBackAction(callUUID: UUID, completionHandler: @escaping (Bool) -> Void) {
        ObvStack.shared.performBackgroundTask { (context) in
            if let item = try? PersistedCallLogItem.get(callUUID: callUUID, within: context) {
                let contacts = item.logContacts.compactMap { $0.contactIdentity?.typedObjectID }
                ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: contacts, groupId: try? item.getGroupId()).postOnDispatchQueue()
            }
            // The action launch the app in foreground to perform the call, we can terminate the action now
            DispatchQueue.main.async { completionHandler(true) }
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

            let acceptInvite: Bool
            switch action {
            case .accept:
                acceptInvite = true
            case .decline:
                _self.waitUntilApplicationIconBadgeNumberWasUpdatedNotification()
                acceptInvite = false
            case .mute, .callBack, .replyTo, .sendMessage, .markAsRead:
                assertionFailure()
                DispatchQueue.main.async { completionHandler(false) }
                return
            }

            guard let obvDialog = persistedInvitation.obvDialog else { assertionFailure(); return }
            switch obvDialog.category {
            case .acceptInvite:
                var localDialog = obvDialog
                try? localDialog.setResponseToAcceptInvite(acceptInvite: acceptInvite)
                _self.appDelegate.obvEngine.respondTo(localDialog)
                DispatchQueue.main.async { completionHandler(true) }
            case .acceptMediatorInvite:
                var localDialog = obvDialog
                try? localDialog.setResponseToAcceptMediatorInvite(acceptInvite: acceptInvite)
                _self.appDelegate.obvEngine.respondTo(localDialog)
                DispatchQueue.main.async { completionHandler(true) }
                return
            case .acceptGroupInvite:
                var localDialog = obvDialog
                try? localDialog.setResponseToAcceptGroupInvite(acceptInvite: acceptInvite)
                _self.appDelegate.obvEngine.respondTo(localDialog)
                DispatchQueue.main.async { completionHandler(true) }
            case .oneToOneInvitationReceived:
                var localDialog = obvDialog
                try? localDialog.setResponseToOneToOneInvitationReceived(invitationAccepted: acceptInvite)
                _self.appDelegate.obvEngine.respondTo(localDialog)
                DispatchQueue.main.async { completionHandler(true) }
            default:
                assertionFailure()
                DispatchQueue.main.async { completionHandler(false) }
                return
            }
        }
        
    }


    private func handleReplyToMessageAction(messageIdentifierFromEngine: Data, persistedContactObjectID: NSManagedObjectID, textBody: String, completionHandler: @escaping (Bool) -> Void) {
        ObvStack.shared.performBackgroundTask { (context) in
            ObvMessengerInternalNotification.userRepliedToReceivedMessageWithinTheNotificationExtension(persistedContactObjectID: persistedContactObjectID, messageIdentifierFromEngine: messageIdentifierFromEngine, textBody: textBody, completionHandler: completionHandler).postOnDispatchQueue()
        }
    }


    private func handleSendMessageAction(persistedDiscussionObjectID: NSManagedObjectID, textBody: String, completionHandler: @escaping (Bool) -> Void) {
        ObvStack.shared.performBackgroundTask { (context) in
            ObvMessengerInternalNotification.userRepliedToMissedCallWithinTheNotificationExtension(persistedDiscussionObjectID: persistedDiscussionObjectID, textBody: textBody, completionHandler: completionHandler).postOnDispatchQueue()
        }
    }

    private func handleMarkAsReadAction(messageIdentifierFromEngine: Data, persistedContactObjectID: NSManagedObjectID, completionHandler: @escaping (Bool) -> Void) {
        ObvStack.shared.performBackgroundTask { (context) in
            ObvMessengerInternalNotification.userWantsToMarkAsReadMessageWithinTheNotificationExtension(persistedContactObjectID: persistedContactObjectID, messageIdentifierFromEngine: messageIdentifierFromEngine, completionHandler: completionHandler).postOnDispatchQueue()
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

        guard let deepLinkString = response.notification.request.content.userInfo[UserNotificationKeys.deepLink] as? String else {
            return
        }
        guard let deepLinkURL = URL(string: deepLinkString) else { return }
        guard let deepLink = ObvDeepLink(url: deepLinkURL) else { return }
        
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()

    }

    
}
