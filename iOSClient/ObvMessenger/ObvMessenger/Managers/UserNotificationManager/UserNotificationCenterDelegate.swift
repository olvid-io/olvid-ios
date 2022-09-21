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
    
    private var tokens = [NSObjectProtocol]()
    
    private var requestIdentifiersThatPlayedSound = Set<String>()
    
    // Answering an invitation from a notification creates a background operation that, e.g., accepts/rejects an invitation. Eventually, the app will have to modify the badge associated to the persisted invitations. To make sure we are still in the background in order to update this badge, we create a long-running background task when responding to an invitation. This backgroud task ends when we are notified that the badge has been updated. While not bullet proof, this is usually enough.
    
    private var backgroundTaskIdForWaitingUntilApplicationIconBadgeNumberWasUpdatedNotification: UIBackgroundTaskIdentifier?
    private var notificationTokenForApplicationIconBadgeNumberWasUpdatedNotification: NSObjectProtocol?

    
}


// MARK: - UNUserNotificationCenterDelegate

extension UserNotificationCenterDelegate {

    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        
        os_log("🥏 Call to userNotificationCenter didReceive withCompletionHandler", log: log, type: .info)

        _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        
        do {
            if try await handleAction(within: response) {
                // The action was handled, there nothing left to do
            } else {
                // The action was not handled, we are certainly dealing with a deep link
                await handleDeepLink(within: response)
            }
        } catch {
            os_log("Could not handle action: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
        
    }
    

    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        
        // In general, we do not want to present "minimal" new message notifications
        if notification.request.content.userInfo["isMinimalNewMessageNotification"] as? Bool == true {
            return []
        }
        
        // When the application is running, we do not show static notification
        if ObvUserNotificationIdentifier.identifierIsStaticIdentifier(identifier: notification.request.identifier) {
            return []
        }
        
        // Wait until the app is initialized
        _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()

        guard let rawId = notification.request.content.userInfo[UserNotificationKeys.id] as? Int,
              let id = ObvUserNotificationID(rawValue: rawId) else {
                  assertionFailure()
            return .alert
        }

        // If we reach this point, we know we are initialized and active. We decide what to show depending on the current activity of the user.
        switch ObvUserActivitySingleton.shared.currentUserActivity {
        case .continueDiscussion(persistedDiscussionObjectID: let currentPersistedDiscussionObjectID):
            switch id {
            case .newReactionNotificationWithHiddenContent, .newReaction:
                // Always show reaction notification even if it is a reaction for the current discussion.
                return .alert
            case .newMessageNotificationWithHiddenContent, .newMessage, .missedCall:
                // The current activity type is `continueDiscussion`. We check whether the notification concerns the "single discussion". If this is the case, we do not display the notification, otherwise, we do.
                guard let notificationPersistedDiscussionObjectURI = notification.request.content.userInfo[UserNotificationKeys.persistedDiscussionObjectURI] as? String,
                      let notificationPersistedDiscussionObjectURI = URL(string: notificationPersistedDiscussionObjectURI),
                      let notificationPersistedDiscussionObjectID = ObvStack.shared.managedObjectID(forURIRepresentation: notificationPersistedDiscussionObjectURI) else {
                          assertionFailure()
                    return .alert
                }

                if notificationPersistedDiscussionObjectID == currentPersistedDiscussionObjectID.objectID {
                    return []
                } else {
                    return .alert
                }
            case .acceptInvite, .sasExchange, .mutualTrustConfirmed, .acceptMediatorInvite, .acceptGroupInvite, .autoconfirmedContactIntroduction, .increaseMediatorTrustLevelRequired, .oneToOneInvitationReceived, .shouldGrantRecordPermissionToReceiveIncomingCalls:
                return .alert
            case .staticIdentifier:
                assertionFailure()
                return []
            }

        case .watchLatestDiscussions:
            switch id {
            case .newMessageNotificationWithHiddenContent, .newMessage:
                // Do not show notifications related to new messages if the user is within the latest discussions view controller. Just play a sound.
                if requestIdentifiersThatPlayedSound.contains(notification.request.identifier) {
                    return []
                } else {
                    requestIdentifiersThatPlayedSound.insert(notification.request.identifier)
                    return .sound
                }
            case .newReactionNotificationWithHiddenContent, .newReaction, .acceptInvite, .sasExchange, .mutualTrustConfirmed, .acceptMediatorInvite, .acceptGroupInvite, .autoconfirmedContactIntroduction, .increaseMediatorTrustLevelRequired, .missedCall, .oneToOneInvitationReceived, .staticIdentifier, .shouldGrantRecordPermissionToReceiveIncomingCalls:
                return .alert
            }
        case .displayInvitations:
            /* The user is currently looking at the invitiation tab.
             * 2020-10-08: We used to prevent
             * the display of the notification if it concerned an invitation,
             * or if it concerned a sas exchange or a mutual trust confirmation.
             * Now, we always show it
             */
            return .alert
        case .other,
             .displaySingleContact,
             .displayContacts,
             .displayGroups,
             .displaySingleGroup,
             .displaySettings:
            return .alert
        }
        
    }
    
}


// MARK: - Helpers

extension UserNotificationCenterDelegate {
    
    /// This method handles a UNNotificationResponse action if it finds one. In that case, it returns `true`, otherwise it returns `false`
    @MainActor
    private func handleAction(within response: UNNotificationResponse) async throws -> Bool {
        
        _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        
        guard let action = UserNotificationAction(rawValue: response.actionIdentifier) else {
            switch response.actionIdentifier {
            case UNNotificationDismissActionIdentifier:
                // If the user simply dismissed the notification, we consider that the action was handled
                return true
            case UNNotificationDefaultActionIdentifier:
                // If the user tapped the notification, it means she wishes to open Olvid and navigate to the discussion.
                // We consider that this notification is not handled and complete with `false`. The caller of this method will handle the rest.
                return false
            default:
                // This is not expected
                assertionFailure()
                return false
            }
        }

        let userInfo = response.notification.request.content.userInfo

        switch action {
        case .accept, .decline:
            guard let persistedInvitationUuidAsString = userInfo[UserNotificationKeys.persistedInvitationUUID] as? String,
                  let persistedInvitationUuid = UUID(uuidString: persistedInvitationUuidAsString)
            else {
                assertionFailure()
                return true
            }
            try await handleInvitationActions(action: action, persistedInvitationUuid: persistedInvitationUuid)
            return true
        case .mute:
            guard let persistedDiscussionObjectURIAsString = userInfo[UserNotificationKeys.persistedDiscussionObjectURI] as? String,
                  let persistedDiscussionObjectURI = URL(string: persistedDiscussionObjectURIAsString),
                  let objectID = ObvStack.shared.managedObjectID(forURIRepresentation: persistedDiscussionObjectURI),
                  let persistedGroupDiscussionEntityName = PersistedGroupDiscussion.entity().name,
                  let persistedOneToOneDiscussionEntityName = PersistedOneToOneDiscussion.entity().name,
                  let persistedDiscussionEntityName = PersistedDiscussion.entity().name
            else {
                assertionFailure()
                return true
            }
            switch objectID.entity.name {
            case persistedGroupDiscussionEntityName, persistedOneToOneDiscussionEntityName, persistedDiscussionEntityName:
                let persistedDiscussionObjectID = TypeSafeManagedObjectID<PersistedDiscussion>(objectID: objectID)
                await handleMuteAction(persistedDiscussionObjectID: persistedDiscussionObjectID)
            default:
                assertionFailure()
            }
            return true
        case .callBack:
            guard let callUUIDAsString = userInfo[UserNotificationKeys.callUUID] as? String,
                  let callUUID = UUID(callUUIDAsString)
            else {
                assertionFailure()
                return true
            }
            try await handleCallBackAction(callUUID: callUUID)
            return true
        case .replyTo:
            guard let messageIdentifierFromEngineAsString = userInfo[UserNotificationKeys.messageIdentifierFromEngine] as? String,
                  let messageIdentifierFromEngine = Data(hexString: messageIdentifierFromEngineAsString),
                  let persistedContactObjectURIAsString = userInfo[UserNotificationKeys.persistedContactObjectURI] as? String,
                  let persistedContactObjectURI = URL(string: persistedContactObjectURIAsString),
                  let persistedContactObjectID = ObvStack.shared.managedObjectID(forURIRepresentation: persistedContactObjectURI),
                  let textResponse = response as? UNTextInputNotificationResponse else {
                assertionFailure()
                return true
            }
            await handleReplyToMessageAction(messageIdentifierFromEngine: messageIdentifierFromEngine, persistedContactObjectID: persistedContactObjectID, textBody: textResponse.userText)
            return true
        case .sendMessage:
            guard let persistedDiscussionObjectURIAsString = userInfo[UserNotificationKeys.persistedDiscussionObjectURI] as? String,
                  let persistedDiscussionObjectURI = URL(string: persistedDiscussionObjectURIAsString),
                  let persistedDiscussionObjectID = ObvStack.shared.managedObjectID(forURIRepresentation: persistedDiscussionObjectURI),
                  let textResponse = response as? UNTextInputNotificationResponse else {
                assertionFailure()
                return true
            }
            await handleSendMessageAction(persistedDiscussionObjectID: persistedDiscussionObjectID, textBody: textResponse.userText)
            return true
        case .markAsRead:
            guard let messageIdentifierFromEngineAsString = userInfo[UserNotificationKeys.messageIdentifierFromEngine] as? String,
                  let messageIdentifierFromEngine = Data(hexString: messageIdentifierFromEngineAsString),
                  let persistedContactObjectURIAsString = userInfo[UserNotificationKeys.persistedContactObjectURI] as? String,
                  let persistedContactObjectURI = URL(string: persistedContactObjectURIAsString),
                  let persistedContactObjectID = ObvStack.shared.managedObjectID(forURIRepresentation: persistedContactObjectURI) else {
                assertionFailure()
                return true
            }
            await handleMarkAsReadAction(messageIdentifierFromEngine: messageIdentifierFromEngine, persistedContactObjectID: persistedContactObjectID)
            return true
        }
    }

    
    @MainActor
    private func handleMuteAction(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let completionHandler = { continuation.resume() }
            ObvMessengerInternalNotification.userWantsToUpdateLocalConfigurationOfDiscussion(
                value: .muteNotificationsDuration(muteNotificationsDuration: .oneHour),
                persistedDiscussionObjectID: persistedDiscussionObjectID,
                completionHandler: completionHandler).postOnDispatchQueue()
        }
    }
    
    
    @MainActor
    private func handleCallBackAction(callUUID: UUID) async throws {
        guard let item = try PersistedCallLogItem.get(callUUID: callUUID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        let contacts = item.logContacts.compactMap { $0.contactIdentity?.typedObjectID }
        ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: contacts, groupId: try? item.getGroupId())
            .postOnDispatchQueue()
    }

    
    @MainActor
    private func handleInvitationActions(action: UserNotificationAction, persistedInvitationUuid: UUID) async throws {
        
        let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        
        let persistedInvitation: PersistedInvitation
        do {
            guard let _persistedInvitation = try PersistedInvitation.get(uuid: persistedInvitationUuid, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                return
            }
            persistedInvitation = _persistedInvitation
        }
        
        let acceptInvite: Bool
        switch action {
        case .accept:
            acceptInvite = true
        case .decline:
            waitUntilApplicationIconBadgeNumberWasUpdatedNotification()
            acceptInvite = false
        case .mute, .callBack, .replyTo, .sendMessage, .markAsRead:
            assertionFailure()
            return
        }
        
        guard let obvDialog = persistedInvitation.obvDialog else { assertionFailure(); return }
        switch obvDialog.category {
        case .acceptInvite:
            var localDialog = obvDialog
            try localDialog.setResponseToAcceptInvite(acceptInvite: acceptInvite)
            let dialogForResponse = localDialog
            DispatchQueue(label: "Background queue for responding to a dialog").async {
                obvEngine.respondTo(dialogForResponse)
            }
        case .acceptMediatorInvite:
            var localDialog = obvDialog
            try localDialog.setResponseToAcceptMediatorInvite(acceptInvite: acceptInvite)
            let dialogForResponse = localDialog
            DispatchQueue(label: "Background queue for responding to a dialog").async {
                obvEngine.respondTo(dialogForResponse)
            }
        case .acceptGroupInvite:
            var localDialog = obvDialog
            try localDialog.setResponseToAcceptGroupInvite(acceptInvite: acceptInvite)
            let dialogForResponse = localDialog
            DispatchQueue(label: "Background queue for responding to a dialog").async {
                obvEngine.respondTo(dialogForResponse)
            }
        case .oneToOneInvitationReceived:
            var localDialog = obvDialog
            try localDialog.setResponseToOneToOneInvitationReceived(invitationAccepted: acceptInvite)
            let dialogForResponse = localDialog
            DispatchQueue(label: "Background queue for responding to a dialog").async {
                obvEngine.respondTo(dialogForResponse)
            }
        default:
            assertionFailure()
            return
        }
        
    }
    

    @MainActor
    private func handleReplyToMessageAction(messageIdentifierFromEngine: Data, persistedContactObjectID: NSManagedObjectID, textBody: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let completionHandler = { continuation.resume() }
            ObvMessengerInternalNotification.userRepliedToReceivedMessageWithinTheNotificationExtension(persistedContactObjectID: persistedContactObjectID,
                                                                                                        messageIdentifierFromEngine: messageIdentifierFromEngine,
                                                                                                        textBody: textBody,
                                                                                                        completionHandler: completionHandler)
            .postOnDispatchQueue()
        }
    }
    

    @MainActor
    private func handleSendMessageAction(persistedDiscussionObjectID: NSManagedObjectID, textBody: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let completionHandler = { continuation.resume() }
            ObvMessengerInternalNotification.userRepliedToMissedCallWithinTheNotificationExtension(persistedDiscussionObjectID: persistedDiscussionObjectID,
                                                                                                   textBody: textBody,
                                                                                                   completionHandler: completionHandler)
            .postOnDispatchQueue()
        }
    }

    
    @MainActor
    private func handleMarkAsReadAction(messageIdentifierFromEngine: Data, persistedContactObjectID: NSManagedObjectID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let completionHandler = { continuation.resume() }
            ObvMessengerInternalNotification.userWantsToMarkAsReadMessageWithinTheNotificationExtension(persistedContactObjectID: persistedContactObjectID,
                                                                                                        messageIdentifierFromEngine: messageIdentifierFromEngine,
                                                                                                        completionHandler: completionHandler)
            .postOnDispatchQueue()
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
    
    
    @MainActor
    private func handleDeepLink(within response: UNNotificationResponse) async {
        
        os_log("🥏 Call to handleDeepLink", log: log, type: .info)

        guard let deepLinkString = response.notification.request.content.userInfo[UserNotificationKeys.deepLink] as? String else {
            return
        }
        guard let deepLinkURL = URL(string: deepLinkString) else { return }
        guard let deepLink = ObvDeepLink(url: deepLinkURL) else { return }
        
        _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()

        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()

    }

    
}
