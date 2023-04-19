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
import ObvTypes


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
        case .continueDiscussion(discussionPermanentID: let currentDiscussionPermanentID):
            switch id {
            case .newReactionNotificationWithHiddenContent, .newReaction:
                // Always show reaction notification even if it is a reaction for the current discussion.
                return .alert
            case .newMessageNotificationWithHiddenContent, .newMessage, .missedCall:
                // The current activity type is `continueDiscussion`. We check whether the notification concerns the "single discussion". If this is the case, we do not display the notification, otherwise, we do.
                guard let persistedDiscussionPermanentIDDescription = notification.request.content.userInfo[UserNotificationKeys.persistedDiscussionPermanentIDDescription] as? String,
                      let expectedEntityName = PersistedDiscussion.entity().name,
                      let notificationPersistedDiscussionPermanentID = ObvManagedObjectPermanentID<PersistedDiscussion>(persistedDiscussionPermanentIDDescription, expectedEntityName: expectedEntityName) else {
                          assertionFailure()
                    return .alert
                }

                if notificationPersistedDiscussionPermanentID == currentDiscussionPermanentID {
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
                  let persistedInvitationUuid = UUID(uuidString: persistedInvitationUuidAsString),
                  let ownedIdentityAsHexString = userInfo[UserNotificationKeys.ownedIdentityAsHexString] as? String,
                  let ownedIdentity = Data(hexString: ownedIdentityAsHexString),
                  let ownedCryptoId = try? ObvCryptoId(identity: ownedIdentity)
            else {
                assertionFailure()
                return true
            }
            try await handleInvitationActions(action: action, persistedInvitationUuid: persistedInvitationUuid, ownedCryptoId: ownedCryptoId)
            return true
        case .mute:
            guard let persistedDiscussionPermanentIDDescription = userInfo[UserNotificationKeys.persistedDiscussionPermanentIDDescription] as? String,
                  let discussionPermanentID = ObvManagedObjectPermanentID<PersistedDiscussion>(persistedDiscussionPermanentIDDescription)
            else {
                assertionFailure()
                return true
            }
            await handleMuteAction(discussionPermanentID: discussionPermanentID)
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
                  let persistedContactPermanentIDDescription = userInfo[UserNotificationKeys.persistedContactPermanentIDDescription] as? String,
                  let persistedContactPermanentID = ObvManagedObjectPermanentID<PersistedObvContactIdentity>(persistedContactPermanentIDDescription),
                  let textResponse = response as? UNTextInputNotificationResponse else {
                assertionFailure()
                return true
            }
            await handleReplyToMessageAction(messageIdentifierFromEngine: messageIdentifierFromEngine, persistedContactPermanentID: persistedContactPermanentID, textBody: textResponse.userText)
            return true
        case .sendMessage:
            guard let persistedDiscussionPermanentIDDescription = userInfo[UserNotificationKeys.persistedDiscussionPermanentIDDescription] as? String,
                  let discussionPermanentID = ObvManagedObjectPermanentID<PersistedDiscussion>(persistedDiscussionPermanentIDDescription),
                  let textResponse = response as? UNTextInputNotificationResponse else {
                assertionFailure()
                return true
            }
            await handleSendMessageAction(discussionPermanentID: discussionPermanentID, textBody: textResponse.userText)
            return true
        case .markAsRead:
            guard let messageIdentifierFromEngineAsString = userInfo[UserNotificationKeys.messageIdentifierFromEngine] as? String,
                  let messageIdentifierFromEngine = Data(hexString: messageIdentifierFromEngineAsString),
                  let persistedContactPermanentIDDescription = userInfo[UserNotificationKeys.persistedContactPermanentIDDescription] as? String,
                  let persistedContactPermanentID = ObvManagedObjectPermanentID<PersistedObvContactIdentity>(persistedContactPermanentIDDescription) else {
                assertionFailure()
                return true
            }
            await handleMarkAsReadAction(messageIdentifierFromEngine: messageIdentifierFromEngine, persistedContactPermanentID: persistedContactPermanentID)
            return true
        }
    }

    
    @MainActor
    private func handleMuteAction(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let completionHandler = { continuation.resume() }
            ObvMessengerInternalNotification.userWantsToUpdateLocalConfigurationOfDiscussion(
                value: .muteNotificationsDuration(.oneHour),
                discussionPermanentID: discussionPermanentID,
                completionHandler: completionHandler).postOnDispatchQueue()
        }
    }
    
    
    @MainActor
    private func handleCallBackAction(callUUID: UUID) async throws {
        guard let item = try PersistedCallLogItem.get(callUUID: callUUID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        let contacts = item.logContacts.compactMap { $0.contactIdentity?.typedObjectID }
        ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(
            contactIDs: contacts,
            groupId: try? item.getGroupIdentifier())
            .postOnDispatchQueue()
    }


    @MainActor
    private func handleInvitationActions(action: UserNotificationAction, persistedInvitationUuid: UUID, ownedCryptoId: ObvCryptoId) async throws {
        
        let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        
        let persistedInvitation: PersistedInvitation
        do {
            guard let _persistedInvitation = try PersistedInvitation.getPersistedInvitation(uuid: persistedInvitationUuid, ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else {
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
        case .acceptGroupV2Invite:
            var localDialog = obvDialog
            try localDialog.setResponseToAcceptGroupV2Invite(acceptInvite: acceptInvite)
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
    private func handleReplyToMessageAction(messageIdentifierFromEngine: Data, persistedContactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>, textBody: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let completionHandler = { continuation.resume() }
            ObvMessengerInternalNotification.userRepliedToReceivedMessageWithinTheNotificationExtension(contactPermanentID: persistedContactPermanentID,
                                                                                                        messageIdentifierFromEngine: messageIdentifierFromEngine,
                                                                                                        textBody: textBody,
                                                                                                        completionHandler: completionHandler)
            .postOnDispatchQueue()
        }
    }
    

    @MainActor
    private func handleSendMessageAction(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, textBody: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let completionHandler = { continuation.resume() }
            ObvMessengerInternalNotification.userRepliedToMissedCallWithinTheNotificationExtension(discussionPermanentID: discussionPermanentID,
                                                                                                   textBody: textBody,
                                                                                                   completionHandler: completionHandler)
            .postOnDispatchQueue()
        }
    }

    
    @MainActor
    private func handleMarkAsReadAction(messageIdentifierFromEngine: Data, persistedContactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let completionHandler = { continuation.resume() }
            ObvMessengerInternalNotification.userWantsToMarkAsReadMessageWithinTheNotificationExtension(contactPermanentID: persistedContactPermanentID,
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

        guard let deepLinkDescription = response.notification.request.content.userInfo[UserNotificationKeys.deepLinkDescription] as? String else {
            return
        }
        guard let deepLink = ObvDeepLink(deepLinkDescription) else { return }
        
        _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()

        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()

    }

    
}
